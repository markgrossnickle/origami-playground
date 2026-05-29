--!strict
--[[
	RegionContentService — durable, PORTABLE per-player region content.

	A Region's builds belong to the PLAYER, not a fixed island location. This
	service is the source of truth for that content. It is stored in LOCAL
	coordinates (relative to a slot's min corner; see RegionConfig) so the same
	build renders into whichever of the 12 display slots the player currently
	leases.

	Storage decisions (vetted):
	  * A DEDICATED DataStore ("PlayerRegion_v1"), NOT the player's profile.
	    Profiles have a 4 MB whole-document cap and save as one unit; coupling
	    voxel builds to economy/progression data risks bricking a save on a big
	    build. One key per player.
	  * BINARY encoding (3 bytes/changed block) wrapped in Base64 for DataStore
	    byte-safety — far smaller than a JSON sparse map, and the binary cap
	    (~1M edited blocks) is unreachable by hand-building. If that ever
	    changes, shard the key by sub-region; the on-disk format is versioned.

	In-memory shape (per loaded user):
	  _content[userId] = { [localChunkKey] = { [flatIndex] = blockType } }
	  localChunkKey = "lcx,cy,lcz"  (Y is global; only XZ is rebased per slot)

	A delta value of BlockType.Air means "this base-terrain block was mined
	out" — same semantics as WorldService deltas.

	This phase is storage only. Painting content into a leased slot (and
	capturing edits back) is wired in later phases.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Base64 = require(ReplicatedStorage.Shared.Base64)

local DATASTORE_NAME = "PlayerRegion_v1"
local FORMAT_VERSION = 1
local SAVE_DEBOUNCE = 6

type ChunkDelta = { [number]: number }
type RegionContent = { [string]: ChunkDelta }

local RegionContentService = Knit.CreateService({
	Name = "RegionContentService",
	Client = {},
})

local _store: DataStore? = nil
local _content: { [number]: RegionContent } = {}
local _loaded: { [number]: boolean } = {}
local _loading: { [number]: boolean } = {}
local _dirty: { [number]: boolean } = {}
local _lastSave: { [number]: number } = {}
local _savePending: { [number]: boolean } = {}

local function _isStudio(): boolean
	return RunService:IsStudio()
end

local function _localChunkKey(lcx: number, cy: number, lcz: number): string
	return string.format("%d,%d,%d", lcx, cy, lcz)
end

-- ── Serialization ───────────────────────────────────────────────────────────
-- Layout (all little-endian via buffer):
--   u8  version
--   u16 chunkCount
--   per chunk: i16 lcx, i16 cy, i16 lcz, u16 deltaCount,
--              deltaCount * (u16 flatIndex, u8 blockType)

local function _serialize(content: RegionContent): string
	-- First pass: count chunks + total deltas to size the buffer exactly.
	local chunkCount = 0
	local totalDeltas = 0
	for _, delta in content do
		local n = 0
		for _ in delta do
			n += 1
		end
		if n > 0 then
			chunkCount += 1
			totalDeltas += n
		end
	end

	local size = 1 + 2 + chunkCount * 8 + totalDeltas * 3
	local buf = buffer.create(size)
	buffer.writeu8(buf, 0, FORMAT_VERSION)
	buffer.writeu16(buf, 1, chunkCount)
	local offset = 3

	for key, delta in content do
		local n = 0
		for _ in delta do
			n += 1
		end
		if n > 0 then
			local lcx, cy, lcz = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
			buffer.writei16(buf, offset, tonumber(lcx) :: number)
			buffer.writei16(buf, offset + 2, tonumber(cy) :: number)
			buffer.writei16(buf, offset + 4, tonumber(lcz) :: number)
			buffer.writeu16(buf, offset + 6, n)
			offset += 8
			for flatIndex, blockType in delta do
				buffer.writeu16(buf, offset, flatIndex)
				buffer.writeu8(buf, offset + 2, blockType)
				offset += 3
			end
		end
	end

	return Base64.encode(buffer.tostring(buf))
end

local function _deserialize(encoded: string): RegionContent
	local content: RegionContent = {}
	if encoded == "" then
		return content
	end
	local ok, raw = pcall(Base64.decode, encoded)
	if not ok or type(raw) ~= "string" or #raw < 3 then
		return content
	end
	local buf = buffer.fromstring(raw)
	local total = buffer.len(buf)

	local version = buffer.readu8(buf, 0)
	if version ~= FORMAT_VERSION then
		warn(`[RegionContentService] Unknown region format version {version}; ignoring`)
		return content
	end
	local chunkCount = buffer.readu16(buf, 1)
	local offset = 3

	for _ = 1, chunkCount do
		if offset + 8 > total then
			break
		end
		local lcx = buffer.readi16(buf, offset)
		local cy = buffer.readi16(buf, offset + 2)
		local lcz = buffer.readi16(buf, offset + 4)
		local n = buffer.readu16(buf, offset + 6)
		offset += 8

		local delta: ChunkDelta = {}
		for _ = 1, n do
			if offset + 3 > total then
				break
			end
			local flatIndex = buffer.readu16(buf, offset)
			local blockType = buffer.readu8(buf, offset + 2)
			delta[flatIndex] = blockType
			offset += 3
		end
		content[_localChunkKey(lcx, cy, lcz)] = delta
	end

	return content
end

-- ── Load / save ──────────────────────────────────────────────────────────────

function RegionContentService:Load(userId: number): RegionContent
	if _loaded[userId] then
		return _content[userId]
	end
	-- Coalesce concurrent loads.
	if _loading[userId] then
		while _loading[userId] do
			task.wait()
		end
		return _content[userId] or {}
	end

	_loading[userId] = true
	local content: RegionContent = {}
	if not _isStudio() and _store ~= nil then
		local ok, encoded = pcall(function()
			return (_store :: DataStore):GetAsync(tostring(userId))
		end)
		if ok then
			if type(encoded) == "string" then
				content = _deserialize(encoded)
			end
		else
			warn(`[RegionContentService] Load failed for {userId}: {encoded}`)
		end
	end
	_content[userId] = content
	_loaded[userId] = true
	_loading[userId] = nil
	return content
end

function RegionContentService:GetContent(userId: number): RegionContent?
	return _content[userId]
end

function RegionContentService:GetChunkDelta(userId: number, lcx: number, cy: number, lcz: number): ChunkDelta?
	local content = _content[userId]
	if not content then
		return nil
	end
	return content[_localChunkKey(lcx, cy, lcz)]
end

function RegionContentService:Save(userId: number)
	if not _dirty[userId] then
		return
	end
	local content = _content[userId]
	if content == nil then
		return
	end
	_dirty[userId] = false
	_lastSave[userId] = os.clock()
	if _isStudio() or _store == nil then
		return
	end
	local encoded = _serialize(content)
	local ok, err = pcall(function()
		(_store :: DataStore):SetAsync(tostring(userId), encoded)
	end)
	if not ok then
		warn(`[RegionContentService] Save failed for {userId}: {err}`)
		_dirty[userId] = true -- retry on the next debounce
	end
end

local function _scheduleSave(self, userId: number)
	local now = os.clock()
	local last = _lastSave[userId] or 0
	if now - last >= SAVE_DEBOUNCE then
		self:Save(userId)
		return
	end
	if _savePending[userId] then
		return
	end
	_savePending[userId] = true
	task.delay(SAVE_DEBOUNCE - (now - last), function()
		_savePending[userId] = nil
		self:Save(userId)
	end)
end

-- Set a single LOCAL block in the player's region content. blockType == Air
-- records a mined-out base block. Marks dirty + schedules a debounced save.
function RegionContentService:SetBlock(
	userId: number,
	lcx: number,
	cy: number,
	lcz: number,
	flatIndex: number,
	blockType: number
)
	local content = _content[userId]
	if content == nil then
		-- Caller should Load first; create lazily so an edit is never lost.
		content = {}
		_content[userId] = content
		_loaded[userId] = true
	end
	local key = _localChunkKey(lcx, cy, lcz)
	local delta = content[key]
	if delta == nil then
		delta = {}
		content[key] = delta
	end
	delta[flatIndex] = blockType
	_dirty[userId] = true
	_scheduleSave(self, userId)
end

function RegionContentService:Unload(userId: number)
	self:Save(userId)
	_content[userId] = nil
	_loaded[userId] = nil
	_loading[userId] = nil
	_dirty[userId] = nil
	_lastSave[userId] = nil
	_savePending[userId] = nil
end

function RegionContentService:FlushAll()
	for userId in _content do
		self:Save(userId)
	end
end

function RegionContentService:KnitInit() end

function RegionContentService:KnitStart()
	if not _isStudio() then
		_store = DataStoreService:GetDataStore(DATASTORE_NAME)
	end

	-- Preload a player's region the moment they join so their content is ready
	-- before the spawn flow tries to paint it.
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:Load(player.UserId)
		end)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Load(player.UserId)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:Unload(player.UserId)
	end)

	game:BindToClose(function()
		self:FlushAll()
	end)
end

return RegionContentService
