--!strict
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local DATASTORE_NAME = "RegionOwnership_v1"
local MESSAGING_TOPIC = "RegionClaimed"
local CLAIM_RETRY_BUDGET = 5

export type SlotState = {
	ownerUserId: number,
	claimedAt: number,
	lastSeenAt: number,
	version: number,
}

local RegionService = Knit.CreateService({
	Name = "RegionService",
	Client = {
		-- Fired whenever a slot's ownership becomes known on this server —
		-- either a fresh claim, the initial DataStore load, or a cross-shard
		-- MessagingService update. Payload: (slotId, ownerUserId, ownerName).
		SlotOwnerChanged = Knit.CreateSignal(),
	},
})

local _slots: { [string]: SlotState } = {}
local _ownerToSlot: { [number]: string } = {}
local _store: DataStore? = nil

-- userId → display name. Populated when an online player claims a slot
-- (player.Name is free) and lazily filled via GetNameFromUserIdAsync for
-- offline owners observed in DataStore / cross-shard messages. Kept process-
-- wide because two slots may belong to the same user across rejoins (we used
-- to leak the previous slot's row otherwise).
local _userNames: { [number]: string } = {}

local function _isStudio(): boolean
	return RunService:IsStudio()
end

local function _resolveName(userId: number): string?
	local cached = _userNames[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		_userNames[userId] = online.Name
		return online.Name
	end
	-- Offline: fall back to the web API. Yields. Studio + tests can spike
	-- this; cache the result (or failure) so we don't retry per frame.
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		_userNames[userId] = name
		return name
	end
	return nil
end

local function _publishOwnerChanged(slotId: string, ownerUserId: number, ownerName: string?)
	-- Fire-and-forget so we don't block the caller on Roblox event dispatch.
	task.spawn(function()
		RegionService.Client.SlotOwnerChanged:FireAll(slotId, ownerUserId, ownerName or "")
	end)
end

local function _setSlotCache(slotId: string, state: SlotState?)
	local prev = _slots[slotId]
	if prev and _ownerToSlot[prev.ownerUserId] == slotId then
		_ownerToSlot[prev.ownerUserId] = nil
	end
	_slots[slotId] = state
	if state then
		_ownerToSlot[state.ownerUserId] = slotId
	end
end

function RegionService:GetSlotState(slotId: string): SlotState?
	return _slots[slotId]
end

function RegionService:GetOwnerOf(slotId: string): number?
	local s = _slots[slotId]
	return s and s.ownerUserId or nil
end

function RegionService:GetSlotForOwner(userId: number): string?
	return _ownerToSlot[userId]
end

-- Snapshot of every claimed slot with the owner's display name. Returned to
-- clients via the RPC below; also used internally by the toast/HUD/minimap.
function RegionService:GetClaimedSlotsSnapshot(): { [string]: { ownerUserId: number, ownerName: string } }
	local snapshot = {}
	for slotId, state in _slots do
		local name = _userNames[state.ownerUserId]
		-- Best-effort lookup so brand-new clients get something readable on
		-- the first RPC; falls back to a placeholder if the API is rate-
		-- limited. We intentionally don't yield-fan-out here because this
		-- runs on the RPC hot path; the per-slot lookup happens elsewhere
		-- and writes _userNames so subsequent calls hit the cache.
		if not name then
			name = _resolveName(state.ownerUserId)
		end
		snapshot[slotId] = {
			ownerUserId = state.ownerUserId,
			ownerName = name or "Unknown",
		}
	end
	return snapshot
end

-- Client-callable: returns the same shape as GetClaimedSlotsSnapshot.
function RegionService.Client:GetClaimedSlots(_player: Player)
	return RegionService:GetClaimedSlotsSnapshot()
end

local function _allSlotIds(): { string }
	local ids = {}
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		table.insert(ids, RegionConfig.formatSlotId(i))
	end
	return ids
end

local function _loadAllSlots()
	if _isStudio() or _store == nil then
		return
	end
	local store = _store :: DataStore
	for _, slotId in _allSlotIds() do
		task.spawn(function()
			local ok, value = pcall(function()
				return store:GetAsync(slotId)
			end)
			if not ok then
				warn(`[RegionService] GetAsync failed for {slotId}: {value}`)
				return
			end
			if type(value) == "table" and type(value.ownerUserId) == "number" then
				_setSlotCache(slotId, value :: SlotState)
				-- Resolve the display name in the background; broadcast once
				-- we have it so any clients already listening update.
				task.spawn(function()
					local name = _resolveName(value.ownerUserId)
					_publishOwnerChanged(slotId, value.ownerUserId, name)
				end)
			end
		end)
	end
end

local function _publishClaim(slotId: string, state: SlotState, ownerName: string?)
	if _isStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(MESSAGING_TOPIC, {
				slotId = slotId,
				ownerUserId = state.ownerUserId,
				ownerName = ownerName,
				claimedAt = state.claimedAt,
				version = state.version,
			})
		end)
		if not ok then
			warn(`[RegionService] PublishAsync failed: {err}`)
		end
	end)
end

local function _subscribeMessaging()
	if _isStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(MESSAGING_TOPIC, function(message)
				local payload = message and message.Data
				if type(payload) ~= "table" then
					return
				end
				local slotId = payload.slotId
				if type(slotId) ~= "string" then
					return
				end
				if RegionConfig.parseSlotId(slotId) == nil then
					return
				end
				if type(payload.ownerUserId) ~= "number" then
					return
				end
				local existing = _slots[slotId]
				if existing and existing.claimedAt >= (payload.claimedAt or 0) then
					return
				end
				_setSlotCache(slotId, {
					ownerUserId = payload.ownerUserId,
					claimedAt = payload.claimedAt or os.time(),
					lastSeenAt = payload.claimedAt or os.time(),
					version = payload.version or 1,
				})
				-- Cross-shard claims may include the owner name; fall back
				-- to a name lookup when the publisher predates the field.
				local ownerName: string? = nil
				if type(payload.ownerName) == "string" and payload.ownerName ~= "" then
					ownerName = payload.ownerName
					_userNames[payload.ownerUserId] = payload.ownerName
				else
					ownerName = _resolveName(payload.ownerUserId)
				end
				_publishOwnerChanged(slotId, payload.ownerUserId, ownerName)
			end)
		end)
		if not ok then
			warn(`[RegionService] SubscribeAsync failed: {err}`)
		end
	end)
end

local function _buildCandidates(userId: number): { string }
	local owned = _ownerToSlot[userId]
	if owned then
		return { owned }
	end
	local candidates = {}
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		if _slots[slotId] == nil then
			table.insert(candidates, slotId)
		end
	end
	for i = #candidates, 2, -1 do
		local j = math.random(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	return candidates
end

local function _attemptClaim(slotId: string, userId: number, ownerName: string?): SlotState?
	local now = os.time()
	if _isStudio() then
		if _slots[slotId] then
			return nil
		end
		local state: SlotState = {
			ownerUserId = userId,
			claimedAt = now,
			lastSeenAt = now,
			version = 1,
		}
		_setSlotCache(slotId, state)
		if ownerName then
			_userNames[userId] = ownerName
		end
		_publishOwnerChanged(slotId, userId, ownerName or _resolveName(userId))
		return state
	end
	local store = _store
	if store == nil then
		return nil
	end
	local claimed: SlotState? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(slotId, function(existing)
			if existing ~= nil then
				if type(existing) == "table" and existing.ownerUserId == userId then
					existing.lastSeenAt = now
					claimed = existing :: SlotState
					return existing
				end
				return nil
			end
			local state: SlotState = {
				ownerUserId = userId,
				claimedAt = now,
				lastSeenAt = now,
				version = 1,
			}
			claimed = state
			return state
		end)
	end)
	if not ok then
		warn(`[RegionService] UpdateAsync({slotId}) failed: {err}`)
		return nil
	end
	if claimed then
		_setSlotCache(slotId, claimed)
		if ownerName then
			_userNames[userId] = ownerName
		end
		local resolved = ownerName or _resolveName(userId)
		_publishClaim(slotId, claimed, resolved)
		_publishOwnerChanged(slotId, userId, resolved)
	end
	return claimed
end

function RegionService:ClaimFreeSlotForPlayer(player: Player): string?
	local userId = player.UserId
	local ownerName = player.Name
	-- Prime the cache so other call sites (TouchSlot, snapshot) can read the
	-- name without hitting the API even if the player disconnects mid-flow.
	_userNames[userId] = ownerName
	for _ = 1, CLAIM_RETRY_BUDGET do
		local candidates = _buildCandidates(userId)
		if #candidates == 0 then
			return nil
		end
		for _, slotId in candidates do
			local state = _attemptClaim(slotId, userId, ownerName)
			if state then
				return slotId
			end
			if not player.Parent then
				return nil
			end
		end
		_loadAllSlots()
		task.wait(0.25)
	end
	return nil
end

function RegionService:TouchSlot(slotId: string)
	if RegionConfig.parseSlotId(slotId) == nil then
		return
	end
	local now = os.time()
	local state = _slots[slotId]
	if state then
		state.lastSeenAt = now
	end
	if _isStudio() or _store == nil then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			(_store :: DataStore):UpdateAsync(slotId, function(existing)
				if type(existing) == "table" then
					existing.lastSeenAt = now
					return existing
				end
				return nil
			end)
		end)
		if not ok then
			warn(`[RegionService] TouchSlot({slotId}) failed: {err}`)
		end
	end)
end

function RegionService:KnitInit() end

function RegionService:KnitStart()
	if not _isStudio() then
		_store = DataStoreService:GetDataStore(DATASTORE_NAME)
	end
	_loadAllSlots()
	_subscribeMessaging()

	Players.PlayerRemoving:Connect(function(player)
		local slotId = _ownerToSlot[player.UserId]
		if slotId then
			RegionService:TouchSlot(slotId)
		end
	end)
end

return RegionService
