--!strict
--[[
	WorldMapController — full-screen overview map (the GDD's "world map", as
	distinct from the always-on minimap).

	Centered on the island origin (NOT the player) so it reads as a fixed
	overview: the Hearth at the middle, all 12 Region slots as labelled
	squares in their true ring positions, the island boundary, and the
	player's live position + heading.

	Toggle: M key, or the small "Map" button under the minimap. Click the
	dimmed backdrop or the X to close.

	North-up. All marker placement is resolution-independent — positions are
	UDim2 scale fractions derived from world coords, so the map looks right at
	any screen size.

	Owner names come from RegionService:GetClaimedSlots (seeded once) and stay
	live via SlotOwnerChanged — same source the minimap + HUD use.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local LocalPlayer = Players.LocalPlayer

local WorldMapController = Knit.CreateController({
	Name = "WorldMapController",
})

-- The map shows a square window of the world centered on origin. Half-width
-- in studs — sized to comfortably contain the island (radius ~5600) plus the
-- outermost region edges (ring 4000 + half-edge 1000 = 5000).
local WORLD_VIEW_HALF = 6000
local WORLD_VIEW_SPAN = WORLD_VIEW_HALF * 2 -- studs across the full map width

-- Region square footprint as a fraction of the viewport.
local SLOT_FRAC = (RegionConfig.SLOT_HALF_EDGE * 2) / WORLD_VIEW_SPAN

local COLOR_HEARTH = Color3.fromRGB(255, 220, 130)
local COLOR_OWNED = Color3.fromRGB(120, 230, 130)
local COLOR_CLAIMED = Color3.fromRGB(240, 200, 80)
local COLOR_UNCLAIMED = Color3.fromRGB(150, 150, 150)
local COLOR_PLAYER = Color3.fromRGB(255, 255, 255)
local COLOR_BG = Color3.fromRGB(18, 18, 26)
local COLOR_PANEL = Color3.fromRGB(28, 28, 40)
local COLOR_BORDER = Color3.fromRGB(120, 120, 140)
local COLOR_ISLAND = Color3.fromRGB(70, 90, 80)

type SlotOutline = {
	frame: Frame,
	stroke: UIStroke,
	label: TextLabel,
}

local _ownedSlotId: string = ""
local _ownerNames: { [string]: string } = {}

local _gui: ScreenGui? = nil
local _viewport: Frame? = nil
local _slotOutlines: { [string]: SlotOutline } = {}
local _playerMarker: TextLabel? = nil
local _isOpen = false
local _renderConn: RBXScriptConnection? = nil

-- Convert a world (x, z) to a viewport scale fraction (0..1, 0.5 = center).
-- North-up: world -Z maps to smaller Y (up). Mirrors the minimap convention.
local function _worldToFrac(worldX: number, worldZ: number): (number, number)
	local fx = 0.5 + worldX / WORLD_VIEW_SPAN
	local fz = 0.5 + worldZ / WORLD_VIEW_SPAN
	return fx, fz
end

local function _createSlotOutline(parent: Instance, name: string): SlotOutline
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(SLOT_FRAC, SLOT_FRAC)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = COLOR_UNCLAIMED
	frame.BackgroundTransparency = 0.82
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	frame.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_UNCLAIMED
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextStrokeColor3 = Color3.fromRGB(15, 15, 22)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextWrapped = true
	label.Text = ""
	label.ZIndex = 4
	label.Parent = frame

	return { frame = frame, stroke = stroke, label = label }
end

local function _createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "WorldMap"
	_gui.ResetOnSpawn = false
	_gui.IgnoreGuiInset = true
	_gui.DisplayOrder = 10
	_gui.Enabled = false
	_gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Dimmed backdrop; clicking it closes the map.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = 1
	backdrop.Parent = _gui
	backdrop.Activated:Connect(function()
		WorldMapController:Close()
	end)

	-- Square map panel centered on screen.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.72, 0.72)
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = _gui

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = COLOR_BORDER
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	-- Title.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 30)
	title.Position = UDim2.new(0, 16, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "World Map"
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 5
	title.Parent = panel

	-- Close button.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(28, 28)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 9)
	close.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
	close.Text = "X"
	close.Font = Enum.Font.GothamBold
	close.TextColor3 = Color3.fromRGB(240, 240, 240)
	close.TextSize = 16
	close.ZIndex = 6
	close.Parent = panel
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = close
	close.Activated:Connect(function()
		WorldMapController:Close()
	end)

	-- Viewport: square area below the title that holds the markers.
	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.AnchorPoint = Vector2.new(0.5, 1)
	viewport.Position = UDim2.new(0.5, 0, 1, -12)
	viewport.Size = UDim2.new(1, -24, 1, -52)
	viewport.BackgroundColor3 = COLOR_BG
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.ZIndex = 3
	viewport.Parent = panel
	_viewport = viewport

	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 8)
	vpCorner.Parent = viewport

	-- Island boundary circle (decorative). Island radius ~5600 of the 6000
	-- half-view, so it nearly fills the viewport.
	local islandDiamFrac = (5600 * 2) / WORLD_VIEW_SPAN
	local island = Instance.new("Frame")
	island.Name = "Island"
	island.AnchorPoint = Vector2.new(0.5, 0.5)
	island.Position = UDim2.fromScale(0.5, 0.5)
	island.Size = UDim2.fromScale(islandDiamFrac, islandDiamFrac)
	island.BackgroundColor3 = COLOR_ISLAND
	island.BackgroundTransparency = 0.85
	island.BorderSizePixel = 0
	island.ZIndex = 3
	island.Parent = viewport
	local islandCorner = Instance.new("UICorner")
	islandCorner.CornerRadius = UDim.new(0.5, 0)
	islandCorner.Parent = island
	local islandStroke = Instance.new("UIStroke")
	islandStroke.Color = COLOR_ISLAND
	islandStroke.Thickness = 1.5
	islandStroke.Transparency = 0.3
	islandStroke.Parent = island

	-- Hearth dot at world origin (viewport center).
	local hearth = Instance.new("Frame")
	hearth.Name = "Hearth"
	hearth.AnchorPoint = Vector2.new(0.5, 0.5)
	hearth.Position = UDim2.fromScale(0.5, 0.5)
	hearth.Size = UDim2.fromOffset(12, 12)
	hearth.BackgroundColor3 = COLOR_HEARTH
	hearth.BorderSizePixel = 0
	hearth.ZIndex = 5
	hearth.Parent = viewport
	local hearthCorner = Instance.new("UICorner")
	hearthCorner.CornerRadius = UDim.new(0.5, 0)
	hearthCorner.Parent = hearth
	local hearthLabel = Instance.new("TextLabel")
	hearthLabel.Size = UDim2.fromOffset(80, 16)
	hearthLabel.AnchorPoint = Vector2.new(0.5, 0)
	hearthLabel.Position = UDim2.new(0.5, 0, 1, 2)
	hearthLabel.BackgroundTransparency = 1
	hearthLabel.Text = "Hearth"
	hearthLabel.Font = Enum.Font.GothamBold
	hearthLabel.TextColor3 = COLOR_HEARTH
	hearthLabel.TextStrokeColor3 = Color3.fromRGB(15, 15, 22)
	hearthLabel.TextStrokeTransparency = 0.2
	hearthLabel.TextSize = 12
	hearthLabel.ZIndex = 5
	hearthLabel.Parent = hearth

	-- Region squares, positioned by their fixed world centers.
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		local outline = _createSlotOutline(viewport, "Slot_" .. slotId)
		local center = RegionConfig.SLOT_CENTERS[i + 1]
		local fx, fz = _worldToFrac(center.x, center.z)
		outline.frame.Position = UDim2.fromScale(fx, fz)
		_slotOutlines[slotId] = outline
	end

	-- Player marker (rotating triangle).
	_playerMarker = Instance.new("TextLabel")
	if _playerMarker then
		_playerMarker.Name = "PlayerMarker"
		_playerMarker.Size = UDim2.fromOffset(18, 18)
		_playerMarker.AnchorPoint = Vector2.new(0.5, 0.5)
		_playerMarker.BackgroundTransparency = 1
		_playerMarker.Text = "▲"
		_playerMarker.TextColor3 = COLOR_PLAYER
		_playerMarker.TextStrokeColor3 = Color3.fromRGB(15, 15, 22)
		_playerMarker.TextStrokeTransparency = 0
		_playerMarker.TextSize = 18
		_playerMarker.Font = Enum.Font.GothamBold
		_playerMarker.ZIndex = 6
		_playerMarker.Parent = viewport
	end
end

local function _refreshSlots()
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		local outline = _slotOutlines[slotId]
		if outline then
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
			outline.stroke.Color = color
			outline.frame.BackgroundColor3 = color
			outline.label.TextColor3 =
				Color3.new(math.min(1, color.R + 0.4), math.min(1, color.G + 0.4), math.min(1, color.B + 0.4))
			outline.label.Text = labelText
		end
	end
end

local function _onRender()
	if not _isOpen or not _viewport or not _playerMarker then
		return
	end
	local character = LocalPlayer.Character
	if not character then
		_playerMarker.Visible = false
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		_playerMarker.Visible = false
		return
	end

	local pos = hrp.Position
	local fx, fz = _worldToFrac(pos.X, pos.Z)
	-- Clamp the marker to the viewport edge so an off-island player still
	-- shows on the boundary rather than being clipped away.
	fx = math.clamp(fx, 0.02, 0.98)
	fz = math.clamp(fz, 0.02, 0.98)
	_playerMarker.Visible = true
	_playerMarker.Position = UDim2.fromScale(fx, fz)

	local look = hrp.CFrame.LookVector
	_playerMarker.Rotation = math.deg(math.atan2(look.X, -look.Z))
end

function WorldMapController:Open()
	if _isOpen then
		return
	end
	_isOpen = true
	if _gui then
		_gui.Enabled = true
	end
	_refreshSlots()
	if not _renderConn then
		_renderConn = RunService.RenderStepped:Connect(_onRender)
	end
end

function WorldMapController:Close()
	if not _isOpen then
		return
	end
	_isOpen = false
	if _gui then
		_gui.Enabled = false
	end
	if _renderConn then
		_renderConn:Disconnect()
		_renderConn = nil
	end
end

function WorldMapController:Toggle()
	if _isOpen then
		self:Close()
	else
		self:Open()
	end
end

local function _createOpenButton()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldMapButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Sits directly under the 250px minimap (top-right, y 50..300).
	local button = Instance.new("TextButton")
	button.Name = "OpenMap"
	button.Size = UDim2.fromOffset(250, 30)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, 308)
	button.BackgroundColor3 = COLOR_PANEL
	button.BackgroundTransparency = 0.1
	button.Text = "🗺  World Map  (M)"
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(235, 235, 240)
	button.TextSize = 14
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_BORDER
	stroke.Thickness = 1
	stroke.Parent = button

	button.Activated:Connect(function()
		WorldMapController:Toggle()
	end)
end

function WorldMapController:KnitInit() end

function WorldMapController:KnitStart()
	_createUI()
	_createOpenButton()

	-- M-key toggle. Ignore when the keystroke was consumed by a text box.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			self:Toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and _isOpen then
			self:Close()
		end
	end)

	-- Track our ephemeral lease slot this session. Query once + stay live.
	task.spawn(function()
		local RegionService = Knit.GetService("RegionService")
		if RegionService then
			local ok, slot = RegionService:GetMySlot():await()
			if ok and type(slot) == "string" and slot ~= "" then
				_ownedSlotId = slot
				_refreshSlots()
			end
		end
	end)

	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if SpawnService and SpawnService.RegionAssigned then
			SpawnService.RegionAssigned:Connect(function(slotId: string)
				if type(slotId) == "string" then
					_ownedSlotId = slotId
					_refreshSlots()
				end
			end)
		end
	end)

	-- Owner-name table: seed once, stay live.
	task.spawn(function()
		local RegionService = Knit.GetService("RegionService")
		if not RegionService then
			return
		end
		local ok, snapshot = RegionService:GetClaimedSlots():await()
		if ok and type(snapshot) == "table" then
			for slotId, entry in snapshot do
				if type(entry) == "table" and type(entry.ownerName) == "string" then
					_ownerNames[slotId] = entry.ownerName
				end
			end
			_refreshSlots()
		end
		if RegionService.SlotOwnerChanged then
			RegionService.SlotOwnerChanged:Connect(function(slotId: string, _userId: number, ownerName: string)
				if type(slotId) ~= "string" or type(ownerName) ~= "string" or ownerName == "" then
					return
				end
				_ownerNames[slotId] = ownerName
				if _isOpen then
					_refreshSlots()
				end
			end)
		end
	end)
end

return WorldMapController
