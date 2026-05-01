--!strict
--[[
	MinimapController — top-right minimap showing the player at center, the
	Hearth at world origin, and the 12 Region slots arranged in a ring at
	R=4000. North-up orientation; the player marker rotates to indicate
	their look direction.

	Color coding:
		Hearth     → warm gold
		Your slot  → green
		Other slot → yellow
		Player     → white (rotates)

	Off-map markers are hidden (out of viewport range). Updates every
	Heartbeat from the player's HumanoidRootPart position.

	Phase 6 will replace this with a richer world map. This is a
	deliberately minimal navigation HUD until then.
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
local SLOT_DOT_SIZE = 8
local EDGE_PADDING = 6 -- px of inset for clamping markers to viewport edge

local COLOR_HEARTH = Color3.fromRGB(255, 220, 130)
local COLOR_OWNED = Color3.fromRGB(120, 230, 130)
local COLOR_UNCLAIMED = Color3.fromRGB(240, 200, 80)
local COLOR_PLAYER = Color3.fromRGB(255, 255, 255)
local COLOR_BG = Color3.fromRGB(20, 20, 30)
local COLOR_BORDER = Color3.fromRGB(120, 120, 140)

local _ownedSlotId: string = ""
local _gui: ScreenGui? = nil
local _viewport: Frame? = nil
local _hearthDot: Frame? = nil
local _slotDots: { [string]: Frame } = {}
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

	-- Slot dots (12 ring positions; positions never change, only colors do).
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		_slotDots[slotId] = _createDot(_viewport, "Slot_" .. slotId, COLOR_UNCLAIMED, SLOT_DOT_SIZE)
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

-- Place a dot at the world (worldX, worldZ) relative to the player at
-- (playerX, playerZ). Hides the dot if it falls outside the viewport.
local function _placeDot(dot: Frame, worldX: number, worldZ: number, playerX: number, playerZ: number)
	local offsetX = (worldX - playerX) / STUDS_PER_PIXEL
	local offsetZ = (worldZ - playerZ) / STUDS_PER_PIXEL
	local maxR = MAP_RADIUS_PX - EDGE_PADDING
	local distSq = offsetX * offsetX + offsetZ * offsetZ
	if distSq > maxR * maxR then
		dot.Visible = false
		return
	end
	dot.Visible = true
	-- Roblox UI Y axis points down; world Z axis points "south" so flip Y.
	dot.Position = UDim2.new(0.5, offsetX, 0.5, offsetZ)
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
		local dot = _slotDots[slotId]
		if dot then
			local center = RegionConfig.SLOT_CENTERS[i + 1]
			_placeDot(dot, center.x, center.z, px, pz)
			if slotId == _ownedSlotId then
				dot.BackgroundColor3 = COLOR_OWNED
			else
				dot.BackgroundColor3 = COLOR_UNCLAIMED
			end
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

	_connection = RunService.Heartbeat:Connect(_onUpdate)
end

return MinimapController
