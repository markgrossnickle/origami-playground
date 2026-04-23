--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)
local ChunkBufferPool = require(ReplicatedStorage.Shared.ChunkBufferPool)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local SAVE_INTERVAL = 60
-- Evict chunks that haven't been touched in this many seconds. Tight enough
-- that an exploring player doesn't accumulate hundreds of chunks worth of
-- buffers + deltas in memory (GC pressure → periodic atomic pauses).
local CHUNK_EVICT_TIME = 30
local EVICT_INTERVAL = 15

type ChunkData = {
	cx: number,
	cy: number,
	cz: number,
	blocks: buffer,
	-- Cached RLE-compressed view of `blocks`. Computed lazily on first
	-- Subscribe; invalidated (set to nil) whenever SetBlock mutates `blocks`.
	-- Avoids redundant re-compression when multiple players subscribe to the
	-- same chunk or when a player re-subscribes after wandering away.
	compressed: buffer?,
	dirty: boolean,
	refCount: number,
	lastAccess: number,
}

type ChunkDelta = { [number]: number }

--[=[
	@class WorldService
	Server-authoritative world state for Origami Expedition.
]=]
local WorldService = Knit.CreateService({
	Name = "WorldService",

	BlockBroken = Signal.new(),

	Client = {
		ChunkData = Knit.CreateSignal(),
		ChunkUnload = Knit.CreateSignal(),
		BlockUpdate = Knit.CreateSignal(),
		RequestMine = Knit.CreateSignal(),
	},
})

local seed: number = 0
local chunks: { [number]: ChunkData } = {}
local deltas: { [number]: ChunkDelta } = {}
local savedDeltas: { [number]: ChunkDelta } = {}
local dirtyRegions: { [string]: boolean } = {}
local playerSubscriptions: { [Player]: { [number]: boolean } } = {}
local chunkSubscribers: { [number]: { [Player]: boolean } } = {}

-- Per-player pending block updates, drained at BLOCK_UPDATE_FLUSH_HZ.
-- Shape: pendingBlockUpdates[player][chunkKey][flatIndex] = blockTypeId.
-- Using nested dicts collapses repeat-edits in the flush window to the latest
-- value, so a player rapidly mining + replacing the same block only sends one
-- update per flush instead of two.
local pendingBlockUpdates: { [Player]: { [number]: { [number]: number } } } = {}
local BLOCK_UPDATE_FLUSH_HZ = 10

local WorldStore: DataStore?
local SeedStore: DataStore?
local pendingChunks: { [number]: boolean } = {}

-- Internal helpers

local function _getOrCreateSeed(): number
	if RunService:IsStudio() then
		return 12345
	end

	local store = SeedStore :: DataStore
	local success, result = pcall(function()
		return store:GetAsync("WorldSeed")
	end)

	if success and result then
		return result :: number
	end

	local newSeed = math.random(1, 2 ^ 31 - 1)
	local writeSuccess, writeErr = pcall(function()
		store:SetAsync("WorldSeed", newSeed)
	end)
	if not writeSuccess then
		warn("[WorldService] Failed to save seed:", writeErr)
	end
	return newSeed
end

local function _loadRegionDeltas(regionKey: string): { [string]: { [string]: number } }?
	if RunService:IsStudio() then
		return nil
	end

	local store = WorldStore :: DataStore
	local success, result = pcall(function()
		return store:GetAsync(regionKey)
	end)

	if success and result then
		return result :: { [string]: { [string]: number } }
	end
	if not success then
		warn("[WorldService] Failed to load region", regionKey, ":", result)
	end
	return nil
end

local function _saveRegionDeltas(regionKey: string, regionData: { [string]: { [string]: number } })
	if RunService:IsStudio() then
		return
	end

	local store = WorldStore :: DataStore
	local success, err = pcall(function()
		store:SetAsync(regionKey, regionData)
	end)
	if not success then
		warn("[WorldService] Failed to save region", regionKey, ":", err)
	end
end

local function _markDirty(chunkKey: number, cx: number, cy: number, cz: number)
	local regionKey = ChunkUtil.regionKey(cx, cy, cz)
	dirtyRegions[regionKey] = true

	if not deltas[chunkKey] then
		deltas[chunkKey] = {}
	end

	local chunk = chunks[chunkKey]
	if chunk then
		chunk.dirty = true
	end
end

-- Chunk lifecycle

function WorldService:_loadDeltasForChunk(chunkKey: number, cx: number, cy: number, cz: number)
	if savedDeltas[chunkKey] then
		return
	end

	local regionKey = ChunkUtil.regionKey(cx, cy, cz)
	local regionData = _loadRegionDeltas(regionKey)
	if not regionData then
		return
	end

	-- DataStore keys are strings ("cx,cy,cz") — convert back to packed number.
	for storedChunkKeyStr, serializedDelta in regionData do
		local storedKey = ChunkUtil.chunkKeyFromString(storedChunkKeyStr)
		if storedKey and not savedDeltas[storedKey] then
			savedDeltas[storedKey] = ChunkSerializer.deserializeDelta(serializedDelta)
		end
	end
end

-- Pre-warm savedDeltas for the regions surrounding (cx, cy, cz) by issuing
-- background DataStore reads. Each Subscribe normally yields on the first
-- chunk in a region (DataStore GetAsync, ~50-500ms). Pre-fetching means the
-- player's chunk subscribes hit savedDeltas instantly when they walk in.
--
-- Spawned as a background task so the caller never waits. Calls are spaced
-- with task.wait(0.05) to avoid bursting the DataStore request budget
-- (60 + 10·players per minute).
--
-- Region size is 8 chunks each axis; prefetch radius 1 = 27 regions covering
-- ±8 chunks (±640 studs) of player movement before the next prefetch is
-- needed.
function WorldService:PrefetchRegionsAround(cx: number, cy: number, cz: number)
	task.spawn(function()
		local seenRegions: { [string]: boolean } = {}
		for drx = -1, 1 do
			for dry = -1, 1 do
				for drz = -1, 1 do
					-- Pick any chunk inside this neighboring region — regionKey
					-- is computed by floor-dividing chunk coords by 8.
					local sampleCx = cx + drx * 8
					local sampleCy = cy + dry * 8
					local sampleCz = cz + drz * 8
					local regionKey = ChunkUtil.regionKey(sampleCx, sampleCy, sampleCz)
					if seenRegions[regionKey] then
						continue
					end
					seenRegions[regionKey] = true

					-- Reuse the existing per-chunk loader; it's a no-op if the
					-- region is already cached and otherwise issues one
					-- GetAsync per region.
					local sampleChunkKey = ChunkUtil.chunkKey(sampleCx, sampleCy, sampleCz)
					self:_loadDeltasForChunk(sampleChunkKey, sampleCx, sampleCy, sampleCz)
					task.wait(0.05)
				end
			end
		end
	end)
end

function WorldService:GetOrCreateChunk(cx: number, cy: number, cz: number): ChunkData
	local chunkKey = ChunkUtil.chunkKey(cx, cy, cz)

	local existing = chunks[chunkKey]
	if existing then
		existing.lastAccess = os.clock()
		return existing
	end

	-- Guard against duplicate generation when generateChunk yields
	if pendingChunks[chunkKey] then
		while pendingChunks[chunkKey] do
			task.wait()
		end
		local result = chunks[chunkKey]
		if result then
			result.lastAccess = os.clock()
			return result
		end
	end

	pendingChunks[chunkKey] = true

	local ok, blockBuffer = pcall(WorldGenModule.generateChunk, seed, cx, cy, cz)
	if not ok then
		pendingChunks[chunkKey] = nil
		warn("[WorldService] generateChunk failed:", blockBuffer)
		blockBuffer = buffer.create(BLOCKS_PER_CHUNK)
	end

	self:_loadDeltasForChunk(chunkKey, cx, cy, cz)

	local chunkDelta = savedDeltas[chunkKey]
	if chunkDelta then
		for flatIndex, blockTypeId in chunkDelta do
			buffer.writeu8(blockBuffer, flatIndex, blockTypeId)
		end
	end

	local memDelta = deltas[chunkKey]
	if memDelta then
		for flatIndex, blockTypeId in memDelta do
			buffer.writeu8(blockBuffer, flatIndex, blockTypeId)
		end
	end

	local chunkData: ChunkData = {
		cx = cx,
		cy = cy,
		cz = cz,
		blocks = blockBuffer,
		compressed = nil,
		dirty = false,
		refCount = 0,
		lastAccess = os.clock(),
	}

	chunks[chunkKey] = chunkData
	pendingChunks[chunkKey] = nil

	return chunkData
end

function WorldService:GetBlock(chunkKey: number, flatIndex: number): number
	local chunk = chunks[chunkKey]
	if not chunk then
		return BlockType.Air
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end
	return buffer.readu8(chunk.blocks, flatIndex)
end

function WorldService:SetBlock(chunkKey: number, flatIndex: number, blockTypeId: number)
	local chunk = chunks[chunkKey]
	if not chunk then
		warn("[WorldService] SetBlock on unloaded chunk:", chunkKey)
		return
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return
	end

	local oldBlock = buffer.readu8(chunk.blocks, flatIndex)
	if oldBlock == blockTypeId then
		return
	end

	buffer.writeu8(chunk.blocks, flatIndex, blockTypeId)
	-- Invalidate cached compressed view — blocks just changed.
	chunk.compressed = nil

	if not deltas[chunkKey] then
		deltas[chunkKey] = {}
	end
	deltas[chunkKey][flatIndex] = blockTypeId

	_markDirty(chunkKey, chunk.cx, chunk.cy, chunk.cz)

	-- Queue the update for each subscriber. The 10Hz flush loop in KnitStart
	-- coalesces a burst of mining edits into one batched fire per player —
	-- replaces firing N events when a player breaks N blocks in a 100ms
	-- window with a single event carrying all N. Reduces chunk-handover and
	-- mining-burst replication storms.
	local subscribers = chunkSubscribers[chunkKey]
	if subscribers then
		for player in subscribers do
			local perPlayer = pendingBlockUpdates[player]
			if not perPlayer then
				perPlayer = {}
				pendingBlockUpdates[player] = perPlayer
			end
			local perChunk = perPlayer[chunkKey]
			if not perChunk then
				perChunk = {}
				perPlayer[chunkKey] = perChunk
			end
			perChunk[flatIndex] = blockTypeId
		end
	end

	if oldBlock ~= BlockType.Air and blockTypeId == BlockType.Air then
		self.BlockBroken:Fire(chunkKey, flatIndex, oldBlock)
	end
end

-- Drain pendingBlockUpdates and fire one batched event per player. Each
-- entry in the wire array is 3 consecutive numbers: chunkKey, flatIndex,
-- blockTypeId. Flat array beats a dict-of-dicts on the wire (Roblox's
-- serializer pays per-key overhead for tables).
local function _flushPendingBlockUpdates(self)
	for player, perPlayer in pendingBlockUpdates do
		if not player.Parent then
			continue
		end
		local flat: { number } = {}
		local i = 0
		for chunkKey, perChunk in perPlayer do
			for flatIndex, blockTypeId in perChunk do
				flat[i + 1] = chunkKey
				flat[i + 2] = flatIndex
				flat[i + 3] = blockTypeId
				i += 3
			end
		end
		if i > 0 then
			self.Client.BlockUpdate:Fire(player, flat)
		end
	end
	-- Single allocation cleanup — fresh table for the next batch window.
	pendingBlockUpdates = {}
end

function WorldService:BreakBlock(chunkKey: number, flatIndex: number): number
	local oldBlock = self:GetBlock(chunkKey, flatIndex)
	if oldBlock == BlockType.Air then
		return BlockType.Air
	end
	self:SetBlock(chunkKey, flatIndex, BlockType.Air)
	return oldBlock
end

-- Subscription management

function WorldService:Subscribe(player: Player, chunkKey: number)
	if not playerSubscriptions[player] then
		playerSubscriptions[player] = {}
	end
	if playerSubscriptions[player][chunkKey] then
		return
	end
	playerSubscriptions[player][chunkKey] = true

	if not chunkSubscribers[chunkKey] then
		chunkSubscribers[chunkKey] = {}
	end
	chunkSubscribers[chunkKey][player] = true

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local chunk = self:GetOrCreateChunk(cx, cy, cz)
	chunk.refCount += 1

	-- Lazily compute + cache the RLE-compressed buffer. Invalidated by
	-- SetBlock, so this recomputes only when the chunk has actually changed.
	local compressed = chunk.compressed
	if not compressed then
		compressed = ChunkSerializer.compress(chunk.blocks)
		chunk.compressed = compressed
	end
	self.Client.ChunkData:Fire(player, chunkKey, compressed)
end

function WorldService:Unsubscribe(player: Player, chunkKey: number)
	if not playerSubscriptions[player] or not playerSubscriptions[player][chunkKey] then
		return
	end
	playerSubscriptions[player][chunkKey] = nil

	if chunkSubscribers[chunkKey] then
		chunkSubscribers[chunkKey][player] = nil
		if not next(chunkSubscribers[chunkKey]) then
			chunkSubscribers[chunkKey] = nil
		end
	end

	local chunk = chunks[chunkKey]
	if chunk then
		chunk.refCount = math.max(0, chunk.refCount - 1)
	end

	self.Client.ChunkUnload:Fire(player, chunkKey)
end

function WorldService:UnsubscribeAll(player: Player)
	local subs = playerSubscriptions[player]
	if not subs then
		return
	end

	for chunkKey in subs do
		if chunkSubscribers[chunkKey] then
			chunkSubscribers[chunkKey][player] = nil
			if not next(chunkSubscribers[chunkKey]) then
				chunkSubscribers[chunkKey] = nil
			end
		end

		local chunk = chunks[chunkKey]
		if chunk then
			chunk.refCount = math.max(0, chunk.refCount - 1)
		end
	end

	playerSubscriptions[player] = nil
end

function WorldService:GetPlayerSubscriptions(player: Player): { [number]: boolean }?
	return playerSubscriptions[player]
end

function WorldService:IsSubscribed(player: Player, chunkKey: number): boolean
	local subs = playerSubscriptions[player]
	return subs ~= nil and subs[chunkKey] == true
end

-- Persistence

function WorldService:_saveAllDirtyRegions()
	-- Snapshot + clear: subsequent SetBlock calls go to a fresh `deltas` table
	-- while this cycle operates on its own copy. Avoids mutation races with
	-- gameplay and lets us move the merge to a background task safely.
	local deltasSnapshot = deltas
	local dirtyRegionsSnapshot = dirtyRegions
	deltas = {}
	dirtyRegions = {}

	-- Pre-group deltas by region to avoid O(n*m) scanning in _saveRegion
	local deltasByRegion: { [string]: { [number]: ChunkDelta } } = {}
	for chunkKey, chunkDelta in deltasSnapshot do
		local cx2, cy2, cz2 = ChunkUtil.parseChunkKey(chunkKey)
		local rk = ChunkUtil.regionKey(cx2, cy2, cz2)
		if not deltasByRegion[rk] then
			deltasByRegion[rk] = {}
		end
		deltasByRegion[rk][chunkKey] = chunkDelta
	end

	for regionKey in dirtyRegionsSnapshot do
		self:_saveRegion(regionKey, deltasByRegion[regionKey])
		task.wait()
	end

	-- Merge into savedDeltas in the background, frame-budgeted. The snapshot
	-- is owned by this closure so nothing else can observe a half-merged
	-- state; _saveRegion on the next cycle only reads savedDeltas that are
	-- fully committed.
	task.spawn(function()
		local start = os.clock()
		for chunkKey, chunkDelta in deltasSnapshot do
			if not savedDeltas[chunkKey] then
				savedDeltas[chunkKey] = {}
			end
			local target = savedDeltas[chunkKey]
			for flatIndex, blockTypeId in chunkDelta do
				target[flatIndex] = blockTypeId
			end
			if os.clock() - start > 0.004 then
				task.wait()
				start = os.clock()
			end
		end
	end)
end

function WorldService:_saveRegion(regionKey: string, regionDeltas: { [number]: ChunkDelta }?)
	-- DataStore key format is string "cx,cy,cz" for backward compatibility.
	local regionData: { [string]: { [string]: number } } = {}

	-- Process pre-grouped deltas for this region (O(k) instead of O(n))
	if regionDeltas then
		for chunkKey, chunkDelta in regionDeltas do
			local merged = {}
			local saved = savedDeltas[chunkKey]
			if saved then
				for flatIndex, blockTypeId in saved do
					merged[flatIndex] = blockTypeId
				end
			end
			for flatIndex, blockTypeId in chunkDelta do
				merged[flatIndex] = blockTypeId
			end

			if next(merged) then
				regionData[ChunkUtil.chunkKeyToString(chunkKey)] = ChunkSerializer.serializeDelta(merged)
			end
		end
	end

	-- Include savedDeltas for this region that have no new in-memory deltas
	local savedCount = 0
	for chunkKey, saved in savedDeltas do
		local chunkKeyStr = ChunkUtil.chunkKeyToString(chunkKey)
		if not regionData[chunkKeyStr] then
			local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
			local chunkRegionKey = ChunkUtil.regionKey(cx, cy, cz)
			if chunkRegionKey == regionKey and next(saved) then
				regionData[chunkKeyStr] = ChunkSerializer.serializeDelta(saved)
			end
		end
		savedCount += 1
		if savedCount % 20 == 0 then
			task.wait()
		end
	end

	if next(regionData) then
		_saveRegionDeltas(regionKey, regionData)
	end
end

function WorldService:_evictUnusedChunks(): number
	local now = os.clock()
	local evictList = {}
	for chunkKey, chunk in chunks do
		local hasSubscribers = chunkSubscribers[chunkKey] and next(chunkSubscribers[chunkKey])
		if chunk.refCount <= 0 and not hasSubscribers and (now - chunk.lastAccess) > CHUNK_EVICT_TIME then
			table.insert(evictList, chunkKey)
		end
	end
	for _, chunkKey in evictList do
		-- Return the block buffer to the pool before dropping the chunk —
		-- WorldGenModule's next acquire() will reuse it instead of allocating
		-- a fresh 4 KB buffer.
		local chunk = chunks[chunkKey]
		if chunk then
			ChunkBufferPool.release(chunk.blocks)
		end
		chunks[chunkKey] = nil
	end
	return #evictList
end

-- Knit lifecycle

function WorldService:KnitInit()
	WorldStore = DataStoreService:GetDataStore("WorldData")
	SeedStore = DataStoreService:GetDataStore("WorldSeed")

	seed = _getOrCreateSeed()
	print("[WorldService] World seed:", seed)

	Players.PlayerRemoving:Connect(function(player)
		self:UnsubscribeAll(player)
		pendingBlockUpdates[player] = nil
	end)
end

function WorldService:KnitStart()
	-- Forward mine requests (MiningService connects to this)
	self.Client.RequestMine:Connect(function(player: Player, chunkKey: number, flatIndex: number)
		if type(chunkKey) ~= "number" or type(flatIndex) ~= "number" then
			return
		end
		if chunkKey ~= math.floor(chunkKey) or chunkKey < 0 then
			return
		end
		if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK or flatIndex ~= math.floor(flatIndex) then
			return
		end
		if not self:IsSubscribed(player, chunkKey) then
			return
		end
		if not chunks[chunkKey] then
			return
		end

		self._onMineRequest:Fire(player, chunkKey, flatIndex)
	end)

	-- Periodic save loop
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)

			local cycleStart = os.clock()
			self:_saveAllDirtyRegions()
			local saveElapsed = os.clock() - cycleStart

			local chunkCount = 0
			for _ in chunks do
				chunkCount += 1
			end

			print(string.format("[WorldService] Save: %.1fms | loaded=%d", saveElapsed * 1000, chunkCount))
		end
	end)

	-- Independent, faster eviction loop so unused chunks don't pile up for up
	-- to 2x SAVE_INTERVAL. Eviction itself is cheap (one pass over `chunks`).
	task.spawn(function()
		while true do
			task.wait(EVICT_INTERVAL)
			self:_evictUnusedChunks()
		end
	end)

	-- 10Hz BlockUpdate batch flush. Drains pendingBlockUpdates and fires one
	-- combined event per player. See _flushPendingBlockUpdates.
	task.spawn(function()
		local interval = 1 / BLOCK_UPDATE_FLUSH_HZ
		while true do
			task.wait(interval)
			_flushPendingBlockUpdates(self)
		end
	end)

	game:BindToClose(function()
		self:_saveAllDirtyRegions()
	end)
end

WorldService._onMineRequest = Signal.new()

function WorldService:_clearAndReseed(newSeed: number)
	-- Clear all in-memory chunks
	table.clear(chunks)
	table.clear(pendingChunks)

	-- Clear deltas (unsaved modifications are lost intentionally)
	table.clear(deltas)
	table.clear(savedDeltas)
	table.clear(dirtyRegions)

	-- Clear subscription tracking
	table.clear(chunkSubscribers)

	-- Set new seed
	seed = newSeed
	print("[WorldService] World regenerated with seed:", seed)
end

function WorldService:GetSeed(): number
	return seed
end

function WorldService.Client:GetWorldSeed(_player: Player): number
	return self.Server:GetSeed()
end

return WorldService
