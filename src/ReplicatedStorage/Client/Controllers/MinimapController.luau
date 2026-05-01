--!strict
--[[
	MinimapController — top-right minimap showing the player at center, the
	Hearth at world origin, and the 12 Region slots arranged in a ring at
	R=4000. North-up orientation; the player marker rotates to indicate
	their look direction.

	Each Region renders as a square outline (the slot's actual 2000x2000-stud
	footprint) with the owner's name overlaid. Owner names are resolved from
	RegionService:GetClaimedSlots and kept fresh via SlotOwnerChanged.

	Color coding:
		Hearth     → warm gold
		Your slot  → green
		Other slot → yellow (claimed) / dim grey (unclaimed)
		Player     → white (rotates)

	Off-map outlines clip to the viewport via ClipsDescendants. Updates every
	Heartbeat from the player's HumanoidRootPart position.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local LocalPlayer = Players.LocalPlayer

local MinimapController = Knit.CreateController({
	Name = "MinimapController",
})

local MAP_SIZE_PX = 250
local MAP_RADIUS_PX = MAP_SIZE_PX / 2
local STUDS_PER_PIXEL = 50 -- 50 studs/pixel → 6250 studs visible diameter
local PLAYER_MARKER_SIZE = 16
local HEARTH_DOT_SIZE = 10
local SLOT_OUTLINE_PX = (RegionConfig.SLOT_HALF_EDGE * 2) / STUDS_PER_PIXEL -- 40 px

local COLOR_HEARTH = Color3.fromRGB(255, 220, 130)
local COLOR_OWNED = Color3.fromRGB(120, 230, 130)
local COLOR_CLAIMED = Color3.fromRGB(240, 200, 80) -- yellow: claimed by another player
local COLOR_UNCLAIMED = Color3.fromRGB(150, 150, 150) -- dim grey: free to claim
local COLOR_PLAYER = Color3.fromRGB(255, 255, 255)
local COLOR_BG = Color3.fromRGB(20, 20, 30)
local COLOR_BORDER = Color3.fromRGB(120, 120, 140)

type SlotOutline = {
	frame: Frame,
	stroke: UIStroke,
	label: TextLabel,
}

local _ownedSlotId: string = ""
local _gui: ScreenGui? = nil
local _viewport: Frame? = nil
local _hearthDot: Frame? = nil
local _slotOutlines: { [string]: SlotOutline } = {}
local _ownerNames: { [string]: string } = {} -- slotId → display name (claimed only)
local _playerMarker: TextLabel? = nil
local _connection: RBXScriptConnection? = nil

local function _createDot(parent: Instance, name: string, color: Color3, size: number): Frame
	local dot = Instance.new("Frame")
	dot.Name = name
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 2
	dot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Thickness = 1
	stroke.Parent = dot

	return dot
end

-- A single slot outline: a transparent square with a coloured stroke (so we
-- can see through to the player marker / Hearth dot when a slot envelops the
-- center of the map) and a small text label centered inside.
local function _createSlotOutline(parent: Instance, name: string): SlotOutline
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromOffset(SLOT_OUTLINE_PX, SLOT_OUTLINE_PX)
	frame.BackgroundTransparency = 0.85
	frame.BackgroundColor3 = COLOR_UNCLAIMED
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 2
	frame.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_UNCLAIMED
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextWrapped = true
	label.Text = ""
	label.ZIndex = 3
	label.Parent = frame

	return { frame = frame, stroke = stroke, label = label }
end

local function _createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "Minimap"
	_gui.ResetOnSpawn = false
	_gui.IgnoreGuiInset = true
	_gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromOffset(MAP_SIZE_PX, MAP_SIZE_PX)
	container.Position = UDim2.new(1, -MAP_SIZE_PX - 12, 0, 50)
	container.BackgroundColor3 = COLOR_BG
	container.BackgroundTransparency = 0.2
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 8)
	containerCorner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_BORDER
	stroke.Thickness = 1
	stroke.Parent = container

	-- Viewport: clips children so off-map markers don't escape the box.
	_viewport = Instance.new("Frame")
	_viewport.Name = "Viewport"
	_viewport.Size = UDim2.fromScale(1, 1)
	_viewport.BackgroundTransparency = 1
	_viewport.ClipsDescendants = true
	_viewport.ZIndex = 1
	_viewport.Parent = container

	-- N indicator at top edge.
	local nLabel = Instance.new("TextLabel")
	nLabel.Name = "NorthIndicator"
	nLabel.Size = UDim2.fromOffset(20, 20)
	nLabel.Position = UDim2.new(0.5, -10, 0, 4)
	nLabel.BackgroundTransparency = 1
	nLabel.Text = "N"
	nLabel.Font = Enum.Font.GothamBold
	nLabel.TextColor3 = COLOR_BORDER
	nLabel.TextSize = 12
	nLabel.ZIndex = 3
	nLabel.Parent = container

	-- Hearth dot (always present, world origin).
	_hearthDot = _createDot(_viewport, "HearthDot", COLOR_HEARTH, HEARTH_DOT_SIZE)

	-- Slot outlines (12 ring positions; positions never change, only colors
	-- and labels do).
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		_slotOutlines[slotId] = _createSlotOutline(_viewport, "Slot_" .. slotId)
	end

	-- Player marker (triangle that rotates with look direction). TextLabel
	-- is the simplest "rotatable shape" — UIScale + ▲ glyph.
	_playerMarker = Instance.new("TextLabel")
	if _playerMarker then
		_playerMarker.Name = "PlayerMarker"
		_playerMarker.Size = UDim2.fromOffset(PLAYER_MARKER_SIZE, PLAYER_MARKER_SIZE)
		_playerMarker.Position = UDim2.new(0.5, 0, 0.5, 0)
		_playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
		_playerMarker.BackgroundTransparency = 1
		_playerMarker.Text = "▲"
		_playerMarker.TextColor3 = COLOR_PLAYER
		_playerMarker.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
		_playerMarker.TextStrokeTransparency = 0
		_playerMarker.TextSize = PLAYER_MARKER_SIZE
		_playerMarker.Font = Enum.Font.GothamBold
		_playerMarker.ZIndex = 4
		_playerMarker.Parent = _viewport
	end
end

-- Place a small marker (Hearth dot) at the world (worldX, worldZ) relative to
-- the player at (playerX, playerZ). Hides the marker if it falls outside the
-- circular viewport.
local function _placeDot(dot: Frame, worldX: number, worldZ: number, playerX: number, playerZ: number)
	local offsetX = (worldX - playerX) / STUDS_PER_PIXEL
	local offsetZ = (worldZ - playerZ) / STUDS_PER_PIXEL
	-- Hide once the dot is comfortably outside the viewport. We use a slight
	-- pad past MAP_RADIUS_PX so dots don't pop right at the edge.
	if math.abs(offsetX) > MAP_RADIUS_PX + 4 or math.abs(offsetZ) > MAP_RADIUS_PX + 4 then
		dot.Visible = false
		return
	end
	dot.Visible = true
	-- Roblox UI Y axis points down; world Z axis points "south" so flip Y.
	dot.Position = UDim2.new(0.5, offsetX, 0.5, offsetZ)
end

-- Place a slot outline. Outlines have non-zero size, so we hide based on
-- whether *any* part of the square overlaps the viewport rather than just
-- the center. ClipsDescendants on the viewport handles the rest.
local function _placeSlotOutline(
	outline: SlotOutline,
	worldX: number,
	worldZ: number,
	playerX: number,
	playerZ: number,
	color: Color3,
	label: string
)
	local offsetX = (worldX - playerX) / STUDS_PER_PIXEL
	local offsetZ = (worldZ - playerZ) / STUDS_PER_PIXEL
	local half = SLOT_OUTLINE_PX / 2
	local visible = math.abs(offsetX) - half < MAP_RADIUS_PX and math.abs(offsetZ) - half < MAP_RADIUS_PX
	outline.frame.Visible = visible
	if not visible then
		return
	end
	outline.frame.Position = UDim2.new(0.5, offsetX, 0.5, offsetZ)
	outline.stroke.Color = color
	outline.frame.BackgroundColor3 = color
	-- Match the label color to the stroke for consistent reading.
	outline.label.TextColor3 =
		Color3.new(math.min(1, color.R + 0.4), math.min(1, color.G + 0.4), math.min(1, color.B + 0.4))
	outline.label.Text = label
end

local function _onUpdate()
	if not _viewport then
		return
	end
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local pos = hrp.Position
	local px, pz = pos.X, pos.Z

	if _hearthDot then
		_placeDot(_hearthDot, RegionConfig.HEARTH_CX, RegionConfig.HEARTH_CZ, px, pz)
	end

	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		local outline = _slotOutlines[slotId]
		if outline then
			local center = RegionConfig.SLOT_CENTERS[i + 1]
			local ownerName = _ownerNames[slotId]
			local color: Color3
			local labelText: string
			if slotId == _ownedSlotId then
				color = COLOR_OWNED
				labelText = ownerName ~= nil and ownerName or "You"
			elseif ownerName then
				color = COLOR_CLAIMED
				labelText = ownerName
			else
				color = COLOR_UNCLAIMED
				labelText = "Unclaimed"
			end
			_placeSlotOutline(outline, center.x, center.z, px, pz, color, labelText)
		end
	end

	-- Rotate the player marker to point in their look direction.
	-- LookVector.X/Z gives heading; UI rotation is 0 = up, 90 = right.
	-- North = -Z in world; we rotate atan2(LookX, -LookZ) → degrees.
	if _playerMarker then
		local look = hrp.CFrame.LookVector
		local angleRad = math.atan2(look.X, -look.Z)
		_playerMarker.Rotation = math.deg(angleRad)
	end
end

local function _ingestOwnersSnapshot(snapshot: { [string]: { ownerUserId: number, ownerName: string } })
	for slotId, entry in snapshot do
		if type(entry) == "table" and type(entry.ownerName) == "string" and entry.ownerName ~= "" then
			_ownerNames[slotId] = entry.ownerName
		end
	end
end

function MinimapController:KnitInit() end

function MinimapController:KnitStart()
	_createUI()

	-- Read owned region from profile (returning players have one stored).
	task.spawn(function()
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local ok, data = PlayerDataService:Read():await()
		if ok and type(data) == "table" then
			local owned = data.OwnedRegionId
			if type(owned) == "string" and owned ~= "" then
				_ownedSlotId = owned
			end
		end
	end)

	-- Listen for first-claim assignment.
	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if SpawnService and SpawnService.RegionAssigned then
			SpawnService.RegionAssigned:Connect(function(slotId: string)
				if type(slotId) == "string" then
					_ownedSlotId = slotId
				end
			end)
		end
	end)

	-- Pull the current owner table once at startup, then keep it live via
	-- the SlotOwnerChanged signal. Both run in spawned tasks so a slow
	-- RPC doesn't gate the heartbeat update.
	task.spawn(function()
		local RegionService = Knit.GetService("RegionService")
		if not RegionService then
			return
		end
		local ok, snapshot = RegionService:GetClaimedSlots():await()
		if ok and type(snapshot) == "table" then
			_ingestOwnersSnapshot(snapshot)
		end
		if RegionService.SlotOwnerChanged then
			RegionService.SlotOwnerChanged:Connect(function(slotId: string, _userId: number, ownerName: string)
				if type(slotId) ~= "string" then
					return
				end
				if type(ownerName) ~= "string" or ownerName == "" then
					return
				end
				_ownerNames[slotId] = ownerName
			end)
		end
	end)

	_connection = RunService.Heartbeat:Connect(_onUpdate)
end

return MinimapController
