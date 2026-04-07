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
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local SAVE_INTERVAL = 60
local CHUNK_EVICT_TIME = 120

type ChunkData = {
	cx: number,
	cy: number,
	cz: number,
	blocks: buffer,
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
local chunks: { [string]: ChunkData } = {}
local deltas: { [string]: ChunkDelta } = {}
local savedDeltas: { [string]: ChunkDelta } = {}
local dirtyRegions: { [string]: boolean } = {}
local playerSubscriptions: { [Player]: { [string]: boolean } } = {}
local chunkSubscribers: { [string]: { [Player]: boolean } } = {}

local WorldStore: DataStore?
local SeedStore: DataStore?
local pendingChunks: { [string]: boolean } = {}

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

local function _markDirty(chunkKey: string, cx: number, cy: number, cz: number)
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

function WorldService:_loadDeltasForChunk(chunkKey: string, cx: number, cy: number, cz: number)
	if savedDeltas[chunkKey] then
		return
	end

	local regionKey = ChunkUtil.regionKey(cx, cy, cz)
	local regionData = _loadRegionDeltas(regionKey)
	if not regionData then
		return
	end

	for storedChunkKey, serializedDelta in regionData do
		if not savedDeltas[storedChunkKey] then
			savedDeltas[storedChunkKey] = ChunkSerializer.deserializeDelta(serializedDelta)
		end
	end
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
		dirty = false,
		refCount = 0,
		lastAccess = os.clock(),
	}

	chunks[chunkKey] = chunkData
	pendingChunks[chunkKey] = nil

	return chunkData
end

function WorldService:GetBlock(chunkKey: string, flatIndex: number): number
	local chunk = chunks[chunkKey]
	if not chunk then
		return BlockType.Air
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end
	return buffer.readu8(chunk.blocks, flatIndex)
end

function WorldService:SetBlock(chunkKey: string, flatIndex: number, blockTypeId: number)
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

	if not deltas[chunkKey] then
		deltas[chunkKey] = {}
	end
	deltas[chunkKey][flatIndex] = blockTypeId

	_markDirty(chunkKey, chunk.cx, chunk.cy, chunk.cz)

	local subscribers = chunkSubscribers[chunkKey]
	if subscribers then
		for player in subscribers do
			self.Client.BlockUpdate:Fire(player, chunkKey, flatIndex, blockTypeId)
		end
	end

	if oldBlock ~= BlockType.Air and blockTypeId == BlockType.Air then
		self.BlockBroken:Fire(chunkKey, flatIndex, oldBlock)
	end
end

function WorldService:BreakBlock(chunkKey: string, flatIndex: number): number
	local oldBlock = self:GetBlock(chunkKey, flatIndex)
	if oldBlock == BlockType.Air then
		return BlockType.Air
	end
	self:SetBlock(chunkKey, flatIndex, BlockType.Air)
	return oldBlock
end

-- Subscription management

function WorldService:Subscribe(player: Player, chunkKey: string)
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

	local compressed = ChunkSerializer.compress(chunk.blocks)
	self.Client.ChunkData:Fire(player, chunkKey, compressed)
end

function WorldService:Unsubscribe(player: Player, chunkKey: string)
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

function WorldService:GetPlayerSubscriptions(player: Player): { [string]: boolean }?
	return playerSubscriptions[player]
end

function WorldService:IsSubscribed(player: Player, chunkKey: string): boolean
	local subs = playerSubscriptions[player]
	return subs ~= nil and subs[chunkKey] == true
end

-- Persistence

function WorldService:_saveAllDirtyRegions()
	-- Pre-group deltas by region to avoid O(n*m) scanning in _saveRegion
	local deltasByRegion: { [string]: { [string]: ChunkDelta } } = {}
	for chunkKey, chunkDelta in deltas do
		local cx2, cy2, cz2 = ChunkUtil.parseChunkKey(chunkKey)
		local rk = ChunkUtil.regionKey(cx2, cy2, cz2)
		if not deltasByRegion[rk] then
			deltasByRegion[rk] = {}
		end
		deltasByRegion[rk][chunkKey] = chunkDelta
	end

	for regionKey in dirtyRegions do
		self:_saveRegion(regionKey, deltasByRegion[regionKey])
		task.wait()
	end
	dirtyRegions = {}

	local mergeCount = 0
	for chunkKey, chunkDelta in deltas do
		if not savedDeltas[chunkKey] then
			savedDeltas[chunkKey] = {}
		end
		for flatIndex, blockTypeId in chunkDelta do
			savedDeltas[chunkKey][flatIndex] = blockTypeId
		end
		mergeCount += 1
		if mergeCount % 10 == 0 then
			task.wait()
		end
	end
	deltas = {}
end

function WorldService:_saveRegion(regionKey: string, regionDeltas: { [string]: ChunkDelta }?)
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
				regionData[chunkKey] = ChunkSerializer.serializeDelta(merged)
			end
		end
	end

	-- Include savedDeltas for this region that have no new in-memory deltas
	local savedCount = 0
	for chunkKey, saved in savedDeltas do
		if not regionData[chunkKey] then
			local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
			local chunkRegionKey = ChunkUtil.regionKey(cx, cy, cz)
			if chunkRegionKey == regionKey and next(saved) then
				regionData[chunkKey] = ChunkSerializer.serializeDelta(saved)
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
	end)
end

function WorldService:KnitStart()
	-- Forward mine requests (MiningService connects to this)
	self.Client.RequestMine:Connect(function(player: Player, chunkKey: string, flatIndex: number)
		if type(chunkKey) ~= "string" or type(flatIndex) ~= "number" then
			return
		end
		if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK or flatIndex ~= math.floor(flatIndex) then
			return
		end
		local parts = string.split(chunkKey, ",")
		if #parts ~= 3 or not tonumber(parts[1]) or not tonumber(parts[2]) or not tonumber(parts[3]) then
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

			local evictStart = os.clock()
			local evictedCount = self:_evictUnusedChunks()
			local evictElapsed = os.clock() - evictStart

			local chunkCount = 0
			for _ in chunks do
				chunkCount += 1
			end

			print(
				string.format(
					"[WorldService] Save/Evict: %.1fms (save=%.1fms, evict=%.1fms) | evicted=%d | loaded=%d",
					(saveElapsed + evictElapsed) * 1000,
					saveElapsed * 1000,
					evictElapsed * 1000,
					evictedCount,
					chunkCount
				)
			)
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
