--!strict
--[[
	RegionContentService — durable, PORTABLE per-player region content.

	A Region's builds belong to the PLAYER, not a fixed island location. This
	service is the source of truth for that content. It is stored in LOCAL
	coordinates (relative to a slot's min corner; see RegionConfig) so the same
	build renders into whichever of the 12 display slots the player currently
	leases.

	Storage: a DEDICATED ProfileStore store ("PlayerRegionStore_v1"), separate
	from the main player profile.
	  * Separate store: the main profile has a 4 MB whole-document cap and
	    saves as one unit; coupling voxel builds to economy/progression data
	    risks bricking a save on a big build.
	  * ProfileStore (not a raw DataStore): session-locking closes the
	    server-hop race. With a raw DataStore, Server A's final SetAsync and
	    Server B's GetAsync are unordered — B can read stale content and later
	    overwrite A's last edits (lost update). ProfileStore makes B's
	    StartSessionAsync wait for A's session release, which force-saves
	    first, so B always loads current content.
	  * The voxel payload is ONE profile field: a versioned binary blob
	    (3 bytes/changed block) wrapped in Base64 for DataStore byte-safety.
	    Far smaller than a JSON sparse map; the ~1M-edited-block ceiling is
	    unreachable by hand-building.
	  * ProfileStore's mock mode also makes this work in Studio (the previous
	    raw-DataStore version was a Studio no-op).

	In-memory shape (per loaded user):
	  _content[userId] = { [localChunkKey] = { [flatIndex] = blockType } }
	  localChunkKey = "lcx,cy,lcz"  (Y is global; only XZ is rebased per slot)

	A delta value of BlockType.Air means "this base-terrain block was mined
	out" — same semantics as WorldService deltas.

	WorldService holds the same content table by reference for the leased slot
	(SetSlotOccupant) and fires RegionBlockChanged on ephemeral edits; we
	mirror the write into our cache (idempotent — same table) and own the
	dirty-tracking + persistence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local Knit = require(ReplicatedStorage.Packages.Knit)
local Base64 = require(ReplicatedStorage.Shared.Base64)

local FORMAT_VERSION = 1
local SAVE_DEBOUNCE = 6

type ChunkDelta = { [number]: number }
type RegionContent = { [string]: ChunkDelta }

type RegionData = {
	Blob: string,
}

local regionDataTemplate: RegionData = {
	Blob = "",
}

local RegionStore = ProfileStore.New("PlayerRegionStore_v1", regionDataTemplate)
type Profile = ProfileStore.Profile<RegionData>

local RegionContentService = Knit.CreateService({
	Name = "RegionContentService",
	Client = {},
})

local _profiles: { [number]: Profile } = {}
local _content: { [number]: RegionContent } = {}
local _loaded: { [number]: boolean } = {}
local _loading: { [number]: boolean } = {}
local _dirty: { [number]: boolean } = {}
local _lastSave: { [number]: number } = {}
local _savePending: { [number]: boolean } = {}

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

-- ── Session / load / save ────────────────────────────────────────────────────

local function _clearUser(userId: number)
	_profiles[userId] = nil
	_content[userId] = nil
	_loaded[userId] = nil
	_loading[userId] = nil
	_dirty[userId] = nil
	_lastSave[userId] = nil
	_savePending[userId] = nil
end

-- Start a ProfileStore session for the user and deserialize their content.
-- Blocks (StartSessionAsync waits out any other server's live session — this
-- is exactly the server-hop handshake we want). Returns the content table.
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

	local profile = RegionStore:StartSessionAsync(tostring(userId), {
		Cancel = function()
			-- Give up if the player left while we were waiting on the lock.
			return Players:GetPlayerByUserId(userId) == nil
		end,
	})

	-- Player left while we were waiting on the lock: PlayerRemoving's Unload
	-- already ran (it had nothing to clear), so caching now would leave a
	-- stale empty entry that a REJOIN would silently trust. End the session
	-- if we got one and cache nothing.
	if Players:GetPlayerByUserId(userId) == nil then
		if profile ~= nil then
			profile:EndSession()
		end
		_loading[userId] = nil
		return {}
	end

	local content: RegionContent = {}
	if profile ~= nil then
		profile:AddUserId(userId)
		profile:Reconcile()
		profile.OnSessionEnd:Connect(function()
			-- Session stolen by another server (player hopped) or released.
			-- Drop the cache so nothing stale gets painted; the other server
			-- owns the content now. WorldService's in-flight render of this
			-- user keeps its own reference and is cleared on slot release.
			_clearUser(userId)
		end)
		content = _deserialize(profile.Data.Blob)
		_profiles[userId] = profile
	else
		warn(`[RegionContentService] Could not start region session for {userId}; edits this session won't persist`)
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

-- Serialize the in-memory content into the profile and trigger a save.
function RegionContentService:Save(userId: number)
	if not _dirty[userId] then
		return
	end
	local content = _content[userId]
	local profile = _profiles[userId]
	if content == nil or profile == nil then
		return
	end
	_dirty[userId] = false
	_lastSave[userId] = os.clock()

	profile.Data.Blob = _serialize(content)
	if profile:IsActive() then
		profile:Save()
	else
		warn(`[RegionContentService] Region profile for {userId} inactive; save skipped`)
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
		-- No live session (load failed or session was stolen). Don't create a
		-- cache that would never persist — the edit is visual-only.
		return
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

-- Final save + session release. The release force-saves, which is what the
-- next server's StartSessionAsync waits on — closing the server-hop race.
function RegionContentService:Unload(userId: number)
	local profile = _profiles[userId]
	if profile ~= nil then
		local content = _content[userId]
		if content ~= nil and _dirty[userId] then
			profile.Data.Blob = _serialize(content)
			_dirty[userId] = false
		end
		profile:EndSession()
	end
	_clearUser(userId)
end

-- Serialize all loaded users into their profiles. ProfileStore's own
-- BindToClose then force-saves every active session; our flush is
-- yield-free, so the blobs are in place before those saves read Data.
function RegionContentService:FlushAll()
	for userId, content in _content do
		local profile = _profiles[userId]
		if profile ~= nil and _dirty[userId] then
			profile.Data.Blob = _serialize(content)
			_dirty[userId] = false
		end
	end
end

function RegionContentService:KnitInit() end

function RegionContentService:KnitStart()
	-- Persist every edit a player makes inside their leased slot. WorldService
	-- fires this from its ephemeral SetBlock path with LOCAL slot coords.
	local WorldService = Knit.GetService("WorldService")
	if WorldService and WorldService.RegionBlockChanged then
		WorldService.RegionBlockChanged:Connect(
			function(userId: number, lcx: number, cy: number, lcz: number, flatIndex: number, blockType: number)
				self:SetBlock(userId, lcx, cy, lcz, flatIndex, blockType)
			end
		)
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
