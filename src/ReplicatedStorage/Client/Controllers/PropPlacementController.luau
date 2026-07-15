--!strict
--[[
	PropPlacementController — the client side of placing a crafted "prop" in
	your Region.

	WorkshopTab calls BeginPlacement(craftedItem). We build a translucent ghost
	of the model that follows the cursor's ground raycast; it turns green inside
	your own leased slot and red elsewhere. Left-click / tap places it (fires
	PropPlacementService:PlaceProp, which re-validates authoritatively). R
	rotates 45°; Escape / right-click cancels.

	Removal is handled entirely server-side (an owner-only "Remove" hold-prompt
	on each placed model), so there's nothing to do here for that.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local ZoneRegistry = require(ReplicatedStorage.Shared.ZoneRegistry)

local LocalPlayer = Players.LocalPlayer

local PropPlacementController = Knit.CreateController({
	Name = "PropPlacementController",
})

local RAY_LENGTH = 600
local ROTATE_STEP = math.rad(45)
local MAX_PLACE_DISTANCE = 60 -- mirrors PropPlacementService so the tint matches
local COLOR_VALID = Color3.fromRGB(90, 220, 120)
local COLOR_INVALID = Color3.fromRGB(220, 90, 90)

local _mySlotId: string = ""
local _active = false
local _item: { [string]: any }? = nil
local _ghost: Model? = nil
local _highlight: Highlight? = nil
local _rotationY = 0
local _validNow = false
local _renderConn: RBXScriptConnection? = nil

local function _cleanup()
	_active = false
	_item = nil
	_rotationY = 0
	_validNow = false
	if _renderConn then
		_renderConn:Disconnect()
		_renderConn = nil
	end
	if _ghost then
		_ghost:Destroy()
		_ghost = nil
	end
	_highlight = nil
end

-- Cursor → ground raycast, ignoring the ghost, our character, and other
-- placed props (we want the terrain under the cursor).
local function _groundHit(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if _ghost then
		table.insert(exclude, _ghost)
	end
	if LocalPlayer.Character then
		table.insert(exclude, LocalPlayer.Character)
	end
	local placed = workspace:FindFirstChild("PlacedProps")
	if placed then
		table.insert(exclude, placed)
	end
	params.FilterDescendantsInstances = exclude

	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	return result and result.Position or nil
end

-- Position the ghost so its base sits on `groundPos`, apply rotation, and
-- return the final pivot position (what we send to the server as the anchor).
local function _positionGhost(groundPos: Vector3): Vector3
	local ghost = _ghost :: Model
	ghost:PivotTo(CFrame.new(groundPos) * CFrame.Angles(0, _rotationY, 0))
	-- Lift so the model's lowest point rests on the ground.
	local cf, size = ghost:GetBoundingBox()
	local minY = cf.Position.Y - size.Y * 0.5
	local lift = groundPos.Y - minY
	ghost:PivotTo(ghost:GetPivot() + Vector3.new(0, lift, 0))
	return ghost:GetPivot().Position
end

local _pendingPlacePos: Vector3? = nil

local function _onRender()
	if not _active or not _ghost then
		return
	end
	local hit = _groundHit()
	if hit == nil then
		_validNow = false
		_pendingPlacePos = nil
		if _highlight then
			_highlight.FillColor = COLOR_INVALID
		end
		return
	end
	local pivotPos = _positionGhost(hit)
	_pendingPlacePos = pivotPos
	-- Valid only inside our own leased slot AND within the server's reach — so
	-- the green tint doesn't promise a placement the server will reject.
	local inRegion = _mySlotId ~= "" and ZoneRegistry.getRegionAt(hit.X, hit.Z) == _mySlotId
	local inReach = true
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		inReach = (hrp.Position - pivotPos).Magnitude <= MAX_PLACE_DISTANCE
	end
	_validNow = inRegion and inReach
	if _highlight then
		_highlight.FillColor = if _validNow then COLOR_VALID else COLOR_INVALID
		_highlight.OutlineColor = if _validNow then COLOR_VALID else COLOR_INVALID
	end
end

local function _commitPlacement()
	if not _active or not _validNow or _pendingPlacePos == nil or _item == nil then
		return
	end
	local pos = _pendingPlacePos
	local item = _item
	local ry = _rotationY
	_cleanup()

	task.spawn(function()
		local PropPlacementService = Knit.GetService("PropPlacementService")
		if not PropPlacementService then
			return
		end
		local ok, result = PropPlacementService:PlaceProp(item.id, pos.X, pos.Y, pos.Z, ry):await()
		-- On server rejection, re-enter placement so the ghost isn't silently
		-- lost — the player can reposition and try again.
		if not ok or type(result) ~= "table" or result.success ~= true then
			PropPlacementController:BeginPlacement(item)
		end
	end)
end

-- Public: enter placement mode for a crafted prop { id, name, modelData }.
function PropPlacementController:BeginPlacement(craftedItem: { [string]: any })
	if type(craftedItem) ~= "table" or craftedItem.modelData == nil then
		return
	end
	_cleanup()

	local ok, ghost = pcall(OrigamiBuilder.BuildModel, craftedItem.modelData)
	if not ok or ghost == nil then
		return
	end
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = math.max(part.Transparency, 0.4)
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = COLOR_INVALID
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = ghost

	ghost.Parent = workspace

	_ghost = ghost
	_highlight = highlight
	_item = craftedItem
	_rotationY = 0
	_active = true
	_renderConn = RunService.RenderStepped:Connect(_onRender)
end

function PropPlacementController:KnitStart()
	-- Track our leased slot for the valid/invalid tint.
	task.spawn(function()
		local RegionService = Knit.GetService("RegionService")
		if RegionService then
			local okSlot, slot = RegionService:GetMySlot():await()
			if okSlot and type(slot) == "string" then
				_mySlotId = slot
			end
		end
	end)
	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if SpawnService and SpawnService.RegionAssigned then
			SpawnService.RegionAssigned:Connect(function(slotId: string)
				if type(slotId) == "string" then
					_mySlotId = slotId
				end
			end)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not _active then
			return
		end
		-- Cancel keys work even over UI.
		if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
			_cleanup()
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			_rotationY = (_rotationY + ROTATE_STEP) % (math.pi * 2)
			return
		end
		-- Placement click — ignore if the input was consumed by the UI.
		if gameProcessed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			_commitPlacement()
		end
	end)
end

function PropPlacementController:KnitInit() end

return PropPlacementController
