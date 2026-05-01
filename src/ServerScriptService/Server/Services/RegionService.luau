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
	Client = {},
})

local _slots: { [string]: SlotState } = {}
local _ownerToSlot: { [number]: string } = {}
local _store: DataStore? = nil

local function _isStudio(): boolean
	return RunService:IsStudio()
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
			end
		end)
	end
end

local function _publishClaim(slotId: string, state: SlotState)
	if _isStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(MESSAGING_TOPIC, {
				slotId = slotId,
				ownerUserId = state.ownerUserId,
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

local function _attemptClaim(slotId: string, userId: number): SlotState?
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
		_publishClaim(slotId, claimed)
	end
	return claimed
end

function RegionService:ClaimFreeSlotForPlayer(player: Player): string?
	local userId = player.UserId
	for _ = 1, CLAIM_RETRY_BUDGET do
		local candidates = _buildCandidates(userId)
		if #candidates == 0 then
			return nil
		end
		for _, slotId in candidates do
			local state = _attemptClaim(slotId, userId)
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
