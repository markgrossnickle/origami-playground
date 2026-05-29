--!strict
--[[
	RegionService — PER-SERVER ephemeral slot allocator for portable regions.

	A region's CONTENT is portable per-player data (RegionContentService); the
	12 ring slots are ephemeral DISPLAY targets rendered server-locally
	(WorldService ephemeral chunks). Because that rendering never persists to
	the shared world, each server assigns its own 12 slots independently — two
	servers can paint the same physical slot for different occupants with no
	collision. So leasing is purely in-memory per server; no DataStore /
	MemoryStore / MessagingService coordination is needed.

	(This diverges from the storage-review's MemoryStore recommendation, which
	assumed slot content still lived at fixed global-world positions. Phase 2's
	server-local ephemeral rendering removed that constraint, making per-server
	leasing correct and far simpler — and matching the "start a server, players
	grab spots" intent.)

	Allocation, when a player needs a slot:
	  1. Re-grab the player's own slot if they still hold one here (reconnect /
	     they never really left — their build is still rendered).
	  2. Otherwise take any truly-free slot.
	  3. Otherwise steal the OLDEST-vacated slot (a departed player's slot whose
	     build is still standing). Vacated slots are always filled LAST and
	     oldest-first, so a brief disconnect with free slots around keeps your
	     spot; a full server reassigns it.
	  4. If all 12 are held by PRESENT players, return nil (no slot this
	     session — the player stays in the Hearth/Wilds; their content is safe).

	On leave we KEEP the slot's occupant + rendered build (so it stands until
	reused, per design) and just mark it vacated so a newcomer can claim it.
	Server crash needs no recovery: in-memory leases vanish, a fresh server
	starts empty, and player content lives in the durable per-player store.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local RegionService = Knit.CreateService({
	Name = "RegionService",

	-- Server signals consumed by the spawn/render lifecycle (Phase 4).
	-- SlotAssigned(player, slotId, prevUserId?) — prevUserId is set when this
	--   assignment STOLE a vacated slot (the prior build must be cleared and
	--   anyone standing in it teleported to safety before repainting).
	SlotAssigned = Signal.new(),

	Client = {
		-- (slotId, ownerUserId, ownerName) — live per-server ownership for the
		-- minimap / HUD / toast / world map.
		SlotOwnerChanged = Knit.CreateSignal(),
	},
})

-- Per-server lease state.
local _slotOccupant: { [string]: number } = {} -- slotId -> userId currently shown there
local _userToSlot: { [number]: string } = {} -- userId -> slotId (present players only)
local _vacatedAt: { [string]: number } = {} -- slotId -> os.clock() when the occupant left
local _userNames: { [number]: string } = {} -- userId -> display name (UI labels)

local function _resolveName(userId: number): string
	local cached = _userNames[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		_userNames[userId] = online.Name
		return online.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		_userNames[userId] = name
		return name
	end
	return "Player"
end

local function _fireOwnerChanged(slotId: string, userId: number)
	RegionService.Client.SlotOwnerChanged:FireAll(slotId, userId, _resolveName(userId))
end

-- Commit an assignment of slotId to userId, stealing from prevUserId if set.
local function _assign(player: Player, slotId: string, userId: number, prevUserId: number?)
	if prevUserId ~= nil and prevUserId ~= userId then
		_userToSlot[prevUserId] = nil
	end
	_slotOccupant[slotId] = userId
	_userToSlot[userId] = slotId
	_vacatedAt[slotId] = nil
	_userNames[userId] = player.Name

	RegionService.SlotAssigned:Fire(player, slotId, prevUserId)
	_fireOwnerChanged(slotId, userId)
end

-- Lease a display slot for the player, applying the allocation policy above.
function RegionService:ClaimFreeSlotForPlayer(player: Player): string?
	local userId = player.UserId
	_userNames[userId] = player.Name

	-- Already holds a slot here (idempotent on repeated calls / respawns).
	local existing = _userToSlot[userId]
	if existing then
		return existing
	end

	-- 1) Re-grab the player's own still-standing slot (reconnect).
	for slotId, occ in _slotOccupant do
		if occ == userId then
			_assign(player, slotId, userId, nil)
			return slotId
		end
	end

	-- 2) Any truly-free slot.
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		if _slotOccupant[slotId] == nil then
			_assign(player, slotId, userId, nil)
			return slotId
		end
	end

	-- 3) Steal the oldest-vacated slot (departed player's build still up).
	local oldestSlot: string? = nil
	local oldestAt = math.huge
	for slotId, at in _vacatedAt do
		if at < oldestAt then
			oldestAt = at
			oldestSlot = slotId
		end
	end
	if oldestSlot ~= nil then
		_assign(player, oldestSlot, userId, _slotOccupant[oldestSlot])
		return oldestSlot
	end

	-- 4) All slots held by present players.
	warn(`[RegionService] No free region slot for {player.Name} — all {RegionConfig.SLOT_COUNT} occupied`)
	return nil
end

-- Owner currently shown in a slot (for zone-permission isOwner checks).
function RegionService:GetOwnerOf(slotId: string): number?
	return _slotOccupant[slotId]
end

function RegionService:GetLeasedSlot(userId: number): string?
	return _userToSlot[userId]
end

-- Player left: keep their build rendered (it stands until reused) but free
-- the player mapping and mark the slot vacated so a newcomer can take it.
function RegionService:ReleaseForPlayer(player: Player)
	local userId = player.UserId
	local slotId = _userToSlot[userId]
	if slotId == nil then
		return
	end
	_userToSlot[userId] = nil
	-- Keep _slotOccupant[slotId] = userId so a fast reconnect re-grabs it and
	-- the build keeps showing; just timestamp the vacancy for oldest-first
	-- reassignment.
	_vacatedAt[slotId] = os.clock()
end

function RegionService:GetClaimedSlotsSnapshot(): { [string]: { ownerUserId: number, ownerName: string } }
	local snapshot = {}
	for slotId, userId in _slotOccupant do
		snapshot[slotId] = {
			ownerUserId = userId,
			ownerName = _resolveName(userId),
		}
	end
	return snapshot
end

function RegionService.Client:GetClaimedSlots(_player: Player)
	return RegionService:GetClaimedSlotsSnapshot()
end

-- The caller's currently-leased slot this session ("" if none / server full).
-- Lets a controller that starts after RegionAssigned fired still learn its
-- slot without waiting for the next assignment.
function RegionService.Client:GetMySlot(player: Player): string
	return RegionService:GetLeasedSlot(player.UserId) or ""
end

function RegionService:KnitInit() end

function RegionService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		RegionService:ReleaseForPlayer(player)
	end)
end

return RegionService
