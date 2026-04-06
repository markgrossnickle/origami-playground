--[[
	HotbarController — 9-slot toolbar for block holding and placement.
	Number keys 1-9 select slots, scroll wheel cycles, right-click / tap places.
	Shows ghost preview at target position and held block near character hand.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local MAX_RAYCAST_DISTANCE = 25
local GHOST_TRANSPARENCY = 0.5
local HOTBAR_SLOTS = 9

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()

local FONT_SM = if IS_CONSOLE then 16 elseif IS_MOBILE then 13 else 11
local FONT_MD = if IS_CONSOLE then 20 elseif IS_MOBILE then 16 else 14
local SLOT_SIZE = if IS_CONSOLE then 60 elseif IS_MOBILE then 48 else 44
local SLOT_GAP = if IS_CONSOLE then 6 elseif IS_MOBILE then 4 else 3

local COLORS = {
	bg = Color3.fromRGB(25, 25, 35),
	slot = Color3.fromRGB(40, 40, 55),
	slotSelected = Color3.fromRGB(80, 140, 220),
	slotHover = Color3.fromRGB(55, 55, 75),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	count = Color3.fromRGB(255, 255, 255),
	countBg = Color3.fromRGB(0, 0, 0),
}

local HotbarController = Knit.CreateController({
	Name = "HotbarController",
})

-- State
local _selectedSlot: number = 1
local _hotbarItems: { [number]: string? } = {} -- slot → itemId or nil
local _inventory: { [string]: number } = {} -- cached inventory counts
local _screenGui: ScreenGui? = nil
local _slotFrames: { [number]: Frame } = {}
local _ghostPart: Part? = nil
local _handPart: Part? = nil
local _heartbeatConn: RBXScriptConnection? = nil
local _enabled: boolean = true

-- Services (set in KnitStart)
local MiningService
local BlockPlacementService
local ChunkRenderController

-- Forward declarations
local _renderSlots: () -> ()

-- Raycast setup
local _raycastParams: RaycastParams = RaycastParams.new()
_raycastParams.FilterType = Enum.RaycastFilterType.Include
local _cachedChunkFolder: Instance? = nil

-- Helpers

local function _getItemColor(itemId: string): Color3
	local cfg = PlotConfig.PLACEABLE_BLOCKS[itemId]
	if cfg then
		return Color3.fromRGB(cfg.color[1], cfg.color[2], cfg.color[3])
	end
	return Color3.fromRGB(200, 200, 200)
end

local function _getItemMaterial(itemId: string): Enum.Material
	local cfg = PlotConfig.PLACEABLE_BLOCKS[itemId]
	if cfg and cfg.material then
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[cfg.material]
		end)
		if ok and mat then
			return mat
		end
	end
	return Enum.Material.SmoothPlastic
end

local function _getItemName(itemId: string): string
	local cfg = PlotConfig.PLACEABLE_BLOCKS[itemId]
	if cfg then
		return cfg.name
	end
	return itemId:gsub("_", " "):gsub("(%a)([%w_]*)", function(a, b)
		return string.upper(a) .. b
	end)
end

local function _getItemCount(itemId: string): number
	return _inventory[itemId] or 0
end

local function _getSelectedItem(): string?
	return _hotbarItems[_selectedSlot]
end

local function createCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 6)
	corner.Parent = parent
	return corner
end

-- Ghost preview block (semi-transparent block at placement target)

local function _createGhostPart()
	if _ghostPart then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = GHOST_TRANSPARENCY
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.Name = "HotbarGhost"
	part.CastShadow = false
	part.Parent = workspace
	_ghostPart = part
end

local function _updateGhost(position: Vector3?, itemId: string?)
	if not _ghostPart then
		_createGhostPart()
	end
	local ghost = _ghostPart :: Part

	if not position or not itemId then
		ghost.CFrame = CFrame.new(0, 1e8, 0)
		return
	end

	ghost.CFrame = CFrame.new(position)
	ghost.Color = _getItemColor(itemId)
	ghost.Material = _getItemMaterial(itemId)
	ghost.Transparency = GHOST_TRANSPARENCY
end

-- Hand preview block (small block attached to character)

local function _createHandPart()
	if _handPart then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 0.2
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Name = "HotbarHandBlock"
	part.CastShadow = false
	part.Parent = workspace
	_handPart = part
end

local function _updateHandBlock(itemId: string?)
	if not _handPart then
		_createHandPart()
	end
	local hand = _handPart :: Part

	if not itemId or not _enabled then
		hand.CFrame = CFrame.new(0, 1e8, 0)
		return
	end

	local character = LocalPlayer.Character
	if not character then
		hand.CFrame = CFrame.new(0, 1e8, 0)
		return
	end

	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if rightHand and rightHand:IsA("BasePart") then
		hand.CFrame = rightHand.CFrame * CFrame.new(0, -1.2, 0)
	else
		hand.CFrame = CFrame.new(0, 1e8, 0)
		return
	end

	hand.Color = _getItemColor(itemId)
	hand.Material = _getItemMaterial(itemId)
end

-- Raycasting for placement target

local function _getMouseRay(): Ray?
	local mouse = LocalPlayer:GetMouse()
	if not mouse then
		return nil
	end
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	return Ray.new(unitRay.Origin, unitRay.Direction * MAX_RAYCAST_DISTANCE)
end

local function _raycastForPlacement(): (string?, number?, Vector3?)
	local ray = _getMouseRay()
	if not ray then
		return nil, nil, nil
	end

	if not _cachedChunkFolder or not _cachedChunkFolder.Parent then
		_cachedChunkFolder = workspace:FindFirstChild("ChunkRender")
	end
	if not _cachedChunkFolder then
		return nil, nil, nil
	end
	_raycastParams.FilterDescendantsInstances = { _cachedChunkFolder }

	local result = workspace:Raycast(ray.Origin, ray.Direction, _raycastParams)
	if not result or not result.Instance then
		return nil, nil, nil
	end

	-- Target position: offset along normal to find the adjacent air block
	local placePos = result.Position + result.Normal * (BLOCK_SIZE * 0.4)
	local cx, cy, cz = ChunkUtil.worldToChunk(placePos.X, placePos.Y, placePos.Z)
	local lx, ly, lz = ChunkUtil.worldToLocalBlock(placePos.X, placePos.Y, placePos.Z)
	local chunkKey = ChunkUtil.chunkKey(cx, cy, cz)
	local flatIndex = ChunkUtil.flatIndex(lx, ly, lz)

	-- Verify target is actually air
	local blockAt = ChunkRenderController:GetBlockAt(chunkKey, flatIndex)
	if blockAt ~= BlockType.Air then
		return nil, nil, nil
	end

	-- Compute block center for ghost display
	local blockCenter = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)

	return chunkKey, flatIndex, blockCenter
end

-- Placement request

local function _tryPlaceBlock()
	local itemId = _getSelectedItem()
	if not itemId then
		return
	end
	if _getItemCount(itemId) < 1 then
		return
	end

	local chunkKey, flatIndex, _ = _raycastForPlacement()
	if not chunkKey or not flatIndex then
		return
	end

	-- Fire placement request to server
	task.spawn(function()
		local result = BlockPlacementService:PlaceBlock(chunkKey, flatIndex, itemId):await()
		if result and result.success then
			-- Optimistically deduct locally for immediate UI feedback
			_inventory[itemId] = (_inventory[itemId] or 1) - 1
			if _inventory[itemId] < 0 then
				_inventory[itemId] = 0
			end
			_renderSlots()
		end
	end)
end

-- UI Building

_renderSlots = function()
	for i = 1, HOTBAR_SLOTS do
		local frame = _slotFrames[i]
		if not frame then
			continue
		end

		local isSelected = (i == _selectedSlot)
		frame.BackgroundColor3 = if isSelected then COLORS.slotSelected else COLORS.slot

		-- Find or create sub-elements
		local colorBlock = frame:FindFirstChild("ColorBlock") :: Frame?
		local countLabel = frame:FindFirstChild("CountLabel") :: TextLabel?
		local keyLabel = frame:FindFirstChild("KeyLabel") :: TextLabel?

		local itemId = _hotbarItems[i]
		if itemId and _getItemCount(itemId) > 0 then
			if colorBlock then
				colorBlock.BackgroundColor3 = _getItemColor(itemId)
				colorBlock.Visible = true
			end
			if countLabel then
				local count = _getItemCount(itemId)
				countLabel.Text = if count > 999 then "999+" else tostring(count)
				countLabel.Visible = true
			end
		else
			if colorBlock then
				colorBlock.Visible = false
			end
			if countLabel then
				countLabel.Visible = false
			end
		end

		if keyLabel then
			keyLabel.TextColor3 = if isSelected then COLORS.count else COLORS.textDim
		end
	end
end

local function _buildUI()
	if _screenGui then
		_screenGui:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "HotbarGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.IgnoreGuiInset = true
	gui.Parent = LocalPlayer.PlayerGui
	_screenGui = gui

	-- Container at bottom center
	local totalWidth = HOTBAR_SLOTS * SLOT_SIZE + (HOTBAR_SLOTS - 1) * SLOT_GAP + 12
	local container = Instance.new("Frame")
	container.Name = "HotbarContainer"
	container.Size = UDim2.new(0, totalWidth, 0, SLOT_SIZE + 8)
	container.Position = UDim2.new(0.5, -totalWidth / 2, 1, -(SLOT_SIZE + 16))
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.3
	container.BorderSizePixel = 0
	container.Parent = gui
	createCorner(container, 8)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = container

	for i = 1, HOTBAR_SLOTS do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.BackgroundColor3 = COLORS.slot
		slot.BorderSizePixel = 0
		slot.LayoutOrder = i
		slot.Parent = container
		createCorner(slot, 6)

		-- Color block (shows item color)
		local colorBlock = Instance.new("Frame")
		colorBlock.Name = "ColorBlock"
		colorBlock.Size = UDim2.new(1, -10, 1, -16)
		colorBlock.Position = UDim2.new(0, 5, 0, 4)
		colorBlock.BackgroundColor3 = Color3.new(1, 1, 1)
		colorBlock.BorderSizePixel = 0
		colorBlock.Visible = false
		colorBlock.Parent = slot
		createCorner(colorBlock, 4)

		-- Count label (bottom-right corner)
		local countLabel = Instance.new("TextLabel")
		countLabel.Name = "CountLabel"
		countLabel.Size = UDim2.new(0, SLOT_SIZE - 4, 0, FONT_SM + 2)
		countLabel.Position = UDim2.new(0, 2, 1, -(FONT_SM + 4))
		countLabel.BackgroundTransparency = 1
		countLabel.TextColor3 = COLORS.count
		countLabel.TextStrokeColor3 = COLORS.countBg
		countLabel.TextStrokeTransparency = 0.3
		countLabel.Font = Enum.Font.GothamBold
		countLabel.TextSize = FONT_SM
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.Text = "0"
		countLabel.Visible = false
		countLabel.Parent = slot

		-- Key number label (top-left)
		if not IS_MOBILE then
			local keyLabel = Instance.new("TextLabel")
			keyLabel.Name = "KeyLabel"
			keyLabel.Size = UDim2.new(0, 14, 0, 14)
			keyLabel.Position = UDim2.new(0, 2, 0, 1)
			keyLabel.BackgroundTransparency = 1
			keyLabel.TextColor3 = COLORS.textDim
			keyLabel.Font = Enum.Font.GothamBold
			keyLabel.TextSize = FONT_SM
			keyLabel.Text = tostring(i)
			keyLabel.Parent = slot
		end

		-- Click/tap handler for slot selection
		local btn = Instance.new("TextButton")
		btn.Name = "SlotButton"
		btn.Size = UDim2.fromScale(1, 1)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Parent = slot
		btn.Activated:Connect(function()
			_selectedSlot = i
			_renderSlots()
		end)

		_slotFrames[i] = slot
	end

	-- Mobile place button
	if IS_MOBILE then
		local placeBtn = Instance.new("TextButton")
		placeBtn.Name = "PlaceButton"
		placeBtn.Size = UDim2.new(0, 56, 0, 56)
		placeBtn.Position = UDim2.new(1, -70, 1, -(SLOT_SIZE + 80))
		placeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		placeBtn.BackgroundColor3 = COLORS.slotSelected
		placeBtn.BackgroundTransparency = 0.2
		placeBtn.Font = Enum.Font.GothamBold
		placeBtn.TextSize = FONT_MD
		placeBtn.TextColor3 = COLORS.text
		placeBtn.Text = "Place"
		placeBtn.BorderSizePixel = 0
		placeBtn.Parent = gui
		createCorner(placeBtn, 28)
		placeBtn.Activated:Connect(function()
			_tryPlaceBlock()
		end)
	end

	_renderSlots()
end

-- Input handling

local function _onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if not _enabled then
		return
	end

	-- Number keys 1-9
	local keyMap: { [Enum.KeyCode]: number } = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
		[Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7,
		[Enum.KeyCode.Eight] = 8,
		[Enum.KeyCode.Nine] = 9,
	}

	local slot = keyMap[input.KeyCode]
	if slot then
		_selectedSlot = slot
		_renderSlots()
		return
	end

	-- Right-click to place (desktop)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		_tryPlaceBlock()
		return
	end

	-- Gamepad: D-pad left/right to cycle, ButtonR1 to place
	if input.KeyCode == Enum.KeyCode.DPadRight then
		_selectedSlot = if _selectedSlot >= HOTBAR_SLOTS then 1 else _selectedSlot + 1
		_renderSlots()
	elseif input.KeyCode == Enum.KeyCode.DPadLeft then
		_selectedSlot = if _selectedSlot <= 1 then HOTBAR_SLOTS else _selectedSlot - 1
		_renderSlots()
	elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
		_tryPlaceBlock()
	end
end

local function _onScroll(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if not _enabled then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if input.Position.Z > 0 then
			_selectedSlot = if _selectedSlot <= 1 then HOTBAR_SLOTS else _selectedSlot - 1
		else
			_selectedSlot = if _selectedSlot >= HOTBAR_SLOTS then 1 else _selectedSlot + 1
		end
		_renderSlots()
	end
end

-- Heartbeat: update ghost and hand block

local function _onHeartbeat()
	if not _enabled then
		_updateGhost(nil, nil)
		_updateHandBlock(nil)
		return
	end

	local itemId = _getSelectedItem()
	_updateHandBlock(itemId)

	if not itemId or _getItemCount(itemId) < 1 then
		_updateGhost(nil, nil)
		return
	end

	local _, _, blockCenter = _raycastForPlacement()
	_updateGhost(blockCenter, itemId)
end

-- Public API (called by BackpackController)

function HotbarController:EquipToSlot(itemId: string, slot: number?)
	local targetSlot = slot

	-- If no slot specified, find first empty or use selected
	if not targetSlot then
		-- Check if item already in hotbar
		for i = 1, HOTBAR_SLOTS do
			if _hotbarItems[i] == itemId then
				_selectedSlot = i
				_renderSlots()
				return
			end
		end
		-- Find first empty slot
		for i = 1, HOTBAR_SLOTS do
			if not _hotbarItems[i] then
				targetSlot = i
				break
			end
		end
		-- Fall back to selected slot
		if not targetSlot then
			targetSlot = _selectedSlot
		end
	end

	if targetSlot < 1 or targetSlot > HOTBAR_SLOTS then
		return
	end

	_hotbarItems[targetSlot] = itemId
	_selectedSlot = targetSlot
	_renderSlots()
end

function HotbarController:UnequipSlot(slot: number)
	if slot < 1 or slot > HOTBAR_SLOTS then
		return
	end
	_hotbarItems[slot] = nil
	_renderSlots()
end

function HotbarController:GetSelectedItem(): string?
	return _getSelectedItem()
end

function HotbarController:GetSelectedSlot(): number
	return _selectedSlot
end

function HotbarController:SetEnabled(enabled: boolean)
	_enabled = enabled
	if not enabled then
		_updateGhost(nil, nil)
		_updateHandBlock(nil)
	end
end

function HotbarController:RefreshInventory(inv: { [string]: number })
	_inventory = inv
	_renderSlots()
end

-- Lifecycle

function HotbarController:KnitInit() end

function HotbarController:KnitStart()
	MiningService = Knit.GetService("MiningService")
	BlockPlacementService = Knit.GetService("BlockPlacementService")
	ChunkRenderController = Knit.GetController("ChunkRenderController")

	-- Load inventory
	task.spawn(function()
		local ok, inv = MiningService:GetMiningInventory():await()
		if ok and type(inv) == "table" then
			_inventory = inv

			-- Auto-populate hotbar with first materials the player has
			local slot = 1
			for itemId, count in inv do
				if count > 0 and PlotConfig.PLACEABLE_BLOCKS[itemId] and slot <= HOTBAR_SLOTS then
					_hotbarItems[slot] = itemId
					slot += 1
				end
			end

			_renderSlots()
		end
	end)

	-- Listen for inventory changes
	MiningService.MiningResult:Connect(function(success: boolean, itemId: string, count: number)
		if success and itemId then
			_inventory[itemId] = (_inventory[itemId] or 0) + count
			_renderSlots()
		end
	end)

	-- Build UI
	task.delay(1, function()
		_buildUI()

		-- Input
		UserInputService.InputBegan:Connect(_onInputBegan)
		UserInputService.InputChanged:Connect(_onScroll)

		-- Heartbeat for ghost/hand preview (throttled to ~20Hz)
		local accum = 0
		_heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
			accum += dt
			if accum < 0.05 then
				return
			end
			accum = 0
			_onHeartbeat()
		end)
	end)
end

return HotbarController
