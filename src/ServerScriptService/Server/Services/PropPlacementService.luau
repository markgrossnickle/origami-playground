--!strict
--[[
	PropPlacementService — placing crafted "prop" items (whole LLM models, not
	voxel blocks) into your Region.

	Props are portable like voxel region content: the placement is stored in
	slot-LOCAL coordinates in the player's region store (RegionContentService),
	so it rebuilds into whichever display slot they lease. The heavy model data
	is NOT duplicated into the store — the placement references the owner's
	CraftedItems by id, and the model is looked up + built at render time (the
	owner is always present when their slot renders).

	Server-authoritative: placement is zone-gated (must be inside your own
	leased slot), range-checked, and rate-limited. The instantiated models are
	anchored server instances under workspace/PlacedProps, so Roblox replicates
	them to everyone on the server (visitors included).

	Lifecycle:
	  * SlotAssigned (RegionService) → clear that slot's prop models, then
	    render the new occupant's props into it. Runs for fresh leases and for
	    steals (a full server reassigning a vacated slot).
	  * Place → persist + instantiate immediately.
	  * Remove → each placed model carries an owner-only "Remove" hold-prompt;
	    triggering it un-persists + destroys (the crafted item stays in
	    inventory).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)
local ZoneRegistry = require(ReplicatedStorage.Shared.ZoneRegistry)

local FOLDER_NAME = "PlacedProps"
local MAX_PLACE_DISTANCE = 60 -- studs from the player to the placement point
local PLACE_COOLDOWN = 0.25 -- seconds between placements per player

-- Mirror of RegionContentService.PropRecord (kept local to avoid requiring the
-- service just for its type).
type PropRecord = {
	id: string,
	itemId: string,
	lx: number,
	ly: number,
	lz: number,
	ry: number,
}

local PropPlacementService = Knit.CreateService({
	Name = "PropPlacementService",
	Client = {},
})

local RegionService
local RegionContentService
local PlayerDataService

local _folder: Folder
local _lastPlace: { [Player]: number } = {}

-- ── Coordinate mapping (stud-space, mirrors the voxel local↔world scheme) ──
-- A slot's min XZ corner in studs; local prop coords are relative to it.
local function _slotOrigin(slotId: string): (number?, number?)
	local center = RegionConfig.getSlotCenter(slotId)
	if center == nil then
		return nil, nil
	end
	return center.x - RegionConfig.SLOT_HALF_EDGE, center.z - RegionConfig.SLOT_HALF_EDGE
end

local function _worldToLocalXZ(slotId: string, wx: number, wz: number): (number?, number?)
	local ox, oz = _slotOrigin(slotId)
	if ox == nil or oz == nil then
		return nil, nil
	end
	return wx - ox, wz - oz
end

local function _localToWorldXZ(slotId: string, lx: number, lz: number): (number?, number?)
	local ox, oz = _slotOrigin(slotId)
	if ox == nil or oz == nil then
		return nil, nil
	end
	return ox + lx, oz + lz
end

-- ── Model helpers ────────────────────────────────────────────────────────────
local function _findCraftedModelData(userId: number, itemId: string): { [string]: any }?
	local player = Players:GetPlayerByUserId(userId)
	if player == nil or PlayerDataService == nil then
		return nil
	end
	local crafted = PlayerDataService:Read(player, { "CraftedItems" })
	if type(crafted) ~= "table" then
		return nil
	end
	for _, item in ipairs(crafted) do
		if item.id == itemId then
			if item.itemType ~= "prop" then
				return nil
			end
			return item.modelData
		end
	end
	return nil
end

-- Un-persist a placement and destroy its model. The crafted item stays in the
-- owner's inventory (this only removes the placed instance).
local function _doRemove(ownerUserId: number, placementId: string, model: Model?)
	if RegionContentService ~= nil then
		RegionContentService:RemoveProp(ownerUserId, placementId)
	end
	if model then
		model:Destroy()
	end
end

-- Build + place one prop model at its world transform, tagged for later
-- lookup + slot-clearing, with an owner-only "Remove" ProximityPrompt.
local function _spawnPropModel(
	record: PropRecord,
	modelData: { [string]: any },
	slotId: string,
	ownerUserId: number
): Model?
	local wx, wz = _localToWorldXZ(slotId, record.lx, record.lz)
	if wx == nil or wz == nil then
		return nil
	end
	local ok, model = pcall(OrigamiBuilder.BuildModel, modelData)
	if not ok or model == nil then
		return nil
	end
	model:PivotTo(CFrame.new(wx, record.ly, wz) * CFrame.Angles(0, record.ry, 0))
	model:SetAttribute("PlacementId", record.id)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("SlotId", slotId)
	model.Parent = _folder

	-- Owner-only removal via hold-prompt. OrigamiBuilder sets PrimaryPart.
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if anchor then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Remove"
		prompt.ObjectText = model.Name
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(triggerer: Player)
			-- Gate to the owner; non-owners see the prompt but it no-ops.
			if triggerer.UserId ~= ownerUserId then
				return
			end
			_doRemove(ownerUserId, record.id, model)
		end)
	end

	return model
end

-- Destroy every placed-prop model currently rendered in a slot.
local function _clearSlotProps(slotId: string)
	for _, child in ipairs(_folder:GetChildren()) do
		if child:GetAttribute("SlotId") == slotId then
			child:Destroy()
		end
	end
end

-- Render all of a present player's stored props into their leased slot.
local function _renderPropsForSlot(player: Player, slotId: string)
	if RegionContentService == nil then
		return
	end
	local props = RegionContentService:GetProps(player.UserId)
	for _, record in ipairs(props) do
		local modelData = _findCraftedModelData(player.UserId, record.itemId)
		if modelData then
			_spawnPropModel(record, modelData, slotId, player.UserId)
		end
	end
end

-- ── Client RPCs ──────────────────────────────────────────────────────────────

function PropPlacementService.Client:PlaceProp(
	player: Player,
	itemId: string,
	wx: number,
	wy: number,
	wz: number,
	ry: number
)
	if type(itemId) ~= "string" or type(wx) ~= "number" or type(wy) ~= "number" or type(wz) ~= "number" then
		return { success = false, error = "invalid_args" }
	end
	if type(ry) ~= "number" or ry ~= ry then -- reject NaN rotation
		ry = 0
	end

	-- Rate limit.
	local now = os.clock()
	local last = _lastPlace[player]
	if last and (now - last) < PLACE_COOLDOWN then
		return { success = false, error = "cooldown" }
	end

	-- Must be inside the player's OWN leased slot.
	local slotId = RegionService and RegionService:GetLeasedSlot(player.UserId)
	if type(slotId) ~= "string" then
		return { success = false, error = "no_region" }
	end
	if ZoneRegistry.getRegionAt(wx, wz) ~= slotId then
		return { success = false, error = "not_your_region" }
	end

	-- Range check against the placer's character.
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return { success = false, error = "no_character" }
	end
	if (rootPart.Position - Vector3.new(wx, wy, wz)).Magnitude > MAX_PLACE_DISTANCE then
		return { success = false, error = "too_far" }
	end

	-- The item must be a crafted prop the player owns.
	local modelData = _findCraftedModelData(player.UserId, itemId)
	if modelData == nil then
		return { success = false, error = "not_a_prop" }
	end

	local lx, lz = _worldToLocalXZ(slotId, wx, wz)
	if lx == nil or lz == nil then
		return { success = false, error = "bad_slot" }
	end

	local record = {
		id = HttpService:GenerateGUID(false),
		itemId = itemId,
		lx = lx,
		ly = wy,
		lz = lz,
		ry = ry,
	}
	if not RegionContentService:AddProp(player.UserId, record) then
		return { success = false, error = "limit_reached" }
	end

	_lastPlace[player] = now
	_spawnPropModel(record, modelData, slotId, player.UserId)

	return { success = true, placementId = record.id }
end

function PropPlacementService:KnitInit() end

function PropPlacementService:KnitStart()
	RegionService = Knit.GetService("RegionService")
	RegionContentService = Knit.GetService("RegionContentService")
	PlayerDataService = Knit.GetService("PlayerDataService")

	_folder = Instance.new("Folder")
	_folder.Name = FOLDER_NAME
	_folder.Parent = workspace

	-- Paint props whenever a slot is (re)assigned. Runs async so it can wait
	-- for the occupant's region session to load (props live there).
	RegionService.SlotAssigned:Connect(function(player: Player, slotId: string, _prevUserId: number?)
		task.spawn(function()
			_clearSlotProps(slotId)
			RegionContentService:Load(player.UserId) -- coalesced; ensures props are loaded
			if player.Parent then
				_renderPropsForSlot(player, slotId)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_lastPlace[player] = nil
	end)
end

return PropPlacementService
