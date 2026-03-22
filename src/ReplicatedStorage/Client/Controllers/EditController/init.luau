--!strict
-- EditController: Select, move, rotate, and delete placed origami models.
-- Toggled from sidebar "Edit" button. Works on mouse, touch, and gamepad.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Platform detection
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()

-- Responsive sizing
local FONT_SM = if IS_CONSOLE then 16 elseif IS_MOBILE then 13 else 11
local FONT_MD = if IS_CONSOLE then 20 elseif IS_MOBILE then 16 else 14
local TOOLBAR_BTN = if IS_CONSOLE then 52 elseif IS_MOBILE then 44 else 36

local Knit = require(ReplicatedStorage.Packages.Knit)

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local COLORS = {
	bg = Color3.fromRGB(25, 25, 30),
	accent = Color3.fromRGB(220, 160, 60),
	accentDim = Color3.fromRGB(160, 120, 40),
	danger = Color3.fromRGB(200, 60, 60),
	success = Color3.fromRGB(60, 180, 80),
	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(180, 180, 180),
}

local GRID_SIZES = { 0, 1, 2, 4 }
local ROTATION_INCREMENT = 45

local EditController = Knit.CreateController({
	Name = "EditController",
})

-- ═══════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════

local _editMode = false
local _gui: ScreenGui? = nil
local _toolbar: Frame? = nil
local _nameLabel: TextLabel? = nil
local _statusLabel: TextLabel? = nil

-- Selection
local _selectedEntry: { model: Model, modelData: { [string]: any }?, stopAI: ((() -> ())?)?, category: string? }? = nil
local _selectionBox: SelectionBox? = nil
local _originalPivot: CFrame? = nil
local _currentYaw: number = 0

-- Drag
local _dragActive = false
local _dragOffset: Vector3 = Vector3.zero
local _dragPlaneY: number = 0

-- Grid
local _gridIndex = 3 -- default to GRID_SIZES[3] = 2 studs
local _gridSize: number = GRID_SIZES[3]

-- Input connections
local _inputBeganConn: RBXScriptConnection? = nil
local _inputChangedConn: RBXScriptConnection? = nil
local _inputEndedConn: RBXScriptConnection? = nil
local _heartbeatConn: RBXScriptConnection? = nil

-- ═══════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════

local function getCreatorController()
	return Knit.GetController("CreatorController")
end

local function screenToRay(screenPos: Vector2): (Vector3, Vector3)
	local ray = Camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	return ray.Origin, ray.Direction
end

local function rayPlaneIntersect(rayOrigin: Vector3, rayDir: Vector3, planeY: number): Vector3?
	if math.abs(rayDir.Y) < 0.001 then
		return nil
	end
	local t = (planeY - rayOrigin.Y) / rayDir.Y
	if t < 0 then
		return nil
	end
	return rayOrigin + rayDir * t
end

local function raycastGround(x: number, z: number, exclude: { Instance }?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	local result = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
	return if result then result.Position.Y else 0
end

local function snapToGrid(value: number, grid: number): number
	if grid <= 0 then
		return value
	end
	return math.round(value / grid) * grid
end

local function findModelFromHit(hitInstance: Instance): { model: Model, modelData: { [string]: any }? }?
	local cc = getCreatorController()
	if not cc then
		return nil
	end
	local spawnedModels = cc:GetSpawnedModels()

	-- Walk up parent chain to find a tracked model
	local current: Instance? = hitInstance
	while current and current ~= workspace do
		if current:IsA("Model") then
			for _, entry in ipairs(spawnedModels) do
				if entry.model == current then
					return entry
				end
			end
		end
		current = current.Parent
	end
	return nil
end

local function getModelGroundInfo(model: Model): (number, number)
	-- Returns (pivotAboveBottom, halfHeight)
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
	return pivotAboveBottom, size.Y / 2
end

local function setStatus(msg: string)
	if _statusLabel then
		_statusLabel.Text = msg
		task.delay(2, function()
			if _statusLabel and _statusLabel.Text == msg then
				_statusLabel.Text = ""
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Selection
-- ═══════════════════════════════════════════════════════════════════

local function deselect()
	if _selectionBox then
		_selectionBox:Destroy()
		_selectionBox = nil
	end

	-- Restart creature AI if we had a creature selected
	if _selectedEntry and _selectedEntry.category == "creature" then
		local cc = getCreatorController()
		if cc and _selectedEntry.model and _selectedEntry.model.Parent and _selectedEntry.modelData then
			cc:RestartCreatureAI(_selectedEntry.model, _selectedEntry.modelData)
		end
	end

	_selectedEntry = nil
	_originalPivot = nil
	_currentYaw = 0
	_dragActive = false

	-- Hide toolbar name
	if _nameLabel then
		_nameLabel.Text = ""
	end
	if _toolbar then
		_toolbar.Visible = false
	end
end

local function selectEntry(entry: { model: Model, modelData: { [string]: any }?, [string]: any })
	-- Deselect previous
	deselect()

	-- Skip vehicles (not editable in MVP)
	if entry.category == "vehicle" then
		setStatus("Vehicles can't be edited yet")
		return
	end

	_selectedEntry = entry :: any
	_originalPivot = entry.model:GetPivot()

	-- Extract current Y rotation
	local _, ry, _ = _originalPivot:ToEulerAnglesYXZ()
	_currentYaw = math.deg(ry)

	-- Stop creature AI while editing
	if entry.category == "creature" and entry.stopAI then
		(entry.stopAI :: () -> ())()
	end

	-- Show SelectionBox
	_selectionBox = Instance.new("SelectionBox")
	_selectionBox.Adornee = entry.model
	_selectionBox.Color3 = COLORS.accent
	_selectionBox.LineThickness = 0.04
	_selectionBox.SurfaceColor3 = COLORS.accent
	_selectionBox.SurfaceTransparency = 0.85
	_selectionBox.Parent = _gui

	-- Update toolbar
	if _nameLabel then
		local name = if entry.modelData then (entry.modelData :: any).name or "Model" else "Model"
		_nameLabel.Text = name
	end
	if _toolbar then
		_toolbar.Visible = true
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Move / Drag
-- ═══════════════════════════════════════════════════════════════════

local function moveModelTo(xzPos: Vector3)
	if not _selectedEntry or not _selectedEntry.model or not _selectedEntry.model.PrimaryPart then
		return
	end
	local model = _selectedEntry.model

	local x = snapToGrid(xzPos.X, _gridSize)
	local z = snapToGrid(xzPos.Z, _gridSize)

	local character = Player.Character
	local exclude = { model }
	if character then
		table.insert(exclude, character)
	end

	local groundY = raycastGround(x, z, exclude)
	local pivotAboveBottom, _ = getModelGroundInfo(model)

	-- During drag, raise slightly for visual feedback
	local liftOffset = if _dragActive then 0.5 else 0
	model:PivotTo(
		CFrame.new(x, groundY + pivotAboveBottom + liftOffset, z) * CFrame.Angles(0, math.rad(_currentYaw), 0)
	)
end

local function startDrag(screenPos: Vector2)
	if not _selectedEntry or not _selectedEntry.model then
		return
	end

	local model = _selectedEntry.model
	local modelPos = model:GetPivot().Position
	_dragPlaneY = modelPos.Y

	local origin, dir = screenToRay(screenPos)
	local hitPoint = rayPlaneIntersect(origin, dir, _dragPlaneY)
	if hitPoint then
		_dragOffset = modelPos - hitPoint
	else
		_dragOffset = Vector3.zero
	end

	_dragActive = true
end

local function updateDrag(screenPos: Vector2)
	if not _dragActive or not _selectedEntry then
		return
	end

	local origin, dir = screenToRay(screenPos)
	local hitPoint = rayPlaneIntersect(origin, dir, _dragPlaneY)
	if hitPoint then
		local targetPos = hitPoint + _dragOffset
		moveModelTo(targetPos)
	end
end

local function endDrag()
	if not _dragActive then
		return
	end
	_dragActive = false

	-- Settle model on ground (remove lift offset)
	if _selectedEntry and _selectedEntry.model then
		local pos = _selectedEntry.model:GetPivot().Position
		moveModelTo(Vector3.new(pos.X, 0, pos.Z))
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Rotation
-- ═══════════════════════════════════════════════════════════════════

local function rotate(degrees: number)
	if not _selectedEntry or not _selectedEntry.model then
		return
	end
	_currentYaw = _currentYaw + degrees
	local pos = _selectedEntry.model:GetPivot().Position
	moveModelTo(Vector3.new(pos.X, 0, pos.Z))
end

-- ═══════════════════════════════════════════════════════════════════
-- Delete
-- ═══════════════════════════════════════════════════════════════════

local _deleteConfirmPending = false

local function deleteSelected()
	if not _selectedEntry then
		return
	end

	if not _deleteConfirmPending then
		_deleteConfirmPending = true
		setStatus("Tap delete again to confirm")
		task.delay(2, function()
			_deleteConfirmPending = false
		end)
		return
	end

	_deleteConfirmPending = false
	local model = _selectedEntry.model
	local cc = getCreatorController()

	-- Clear selection first (before destroying)
	_selectionBox:Destroy()
	_selectionBox = nil
	_selectedEntry = nil
	_originalPivot = nil
	if _toolbar then
		_toolbar.Visible = false
	end

	if cc then
		cc:RemoveSpawnedModel(model)
	end
	setStatus("Deleted!")
end

-- ═══════════════════════════════════════════════════════════════════
-- Input Handling
-- ═══════════════════════════════════════════════════════════════════

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	-- Mouse click or touch tap
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local screenPos = Vector2.new(input.Position.X, input.Position.Y)
		local origin, dir = screenToRay(screenPos)

		local character = Player.Character
		local exclude = {}
		if character then
			table.insert(exclude, character)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclude

		local result = workspace:Raycast(origin, dir * 500, params)
		if result and result.Instance then
			local entry = findModelFromHit(result.Instance)
			if entry then
				if _selectedEntry and _selectedEntry.model == entry.model then
					-- Already selected — start drag
					startDrag(screenPos)
				else
					-- New selection
					selectEntry(entry)
					startDrag(screenPos)
				end
				return
			end
		end

		-- Clicked empty space — deselect
		deselect()
		return
	end

	-- Keyboard rotation
	if input.UserInputType == Enum.UserInputType.Keyboard and _selectedEntry then
		if input.KeyCode == Enum.KeyCode.Q then
			rotate(-ROTATION_INCREMENT)
		elseif input.KeyCode == Enum.KeyCode.E then
			rotate(ROTATION_INCREMENT)
		elseif input.KeyCode == Enum.KeyCode.X then
			deleteSelected()
		end
	end

	-- Gamepad rotation
	if input.UserInputType == Enum.UserInputType.Gamepad1 and _selectedEntry then
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			rotate(-ROTATION_INCREMENT)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			rotate(ROTATION_INCREMENT)
		elseif input.KeyCode == Enum.KeyCode.ButtonX then
			deleteSelected()
		end
	end
end

local function onInputChanged(input: InputObject, _gameProcessed: boolean)
	if not _dragActive then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local screenPos = Vector2.new(input.Position.X, input.Position.Y)
		updateDrag(screenPos)
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		endDrag()
	end
end

-- Gamepad: move selected model with left stick
local function onHeartbeat(_dt: number)
	if not _selectedEntry or _dragActive or not IS_CONSOLE then
		return
	end

	local gamepad = Enum.UserInputType.Gamepad1
	if not UserInputService:GetGamepadConnected(gamepad) then
		return
	end

	local thumbstick = UserInputService:GetGamepadState(gamepad)
	local lx, ly = 0, 0
	for _, inputObj in ipairs(thumbstick) do
		if inputObj.KeyCode == Enum.KeyCode.Thumbstick1 then
			lx = inputObj.Position.X
			ly = inputObj.Position.Y
			break
		end
	end

	local deadzone = 0.2
	if math.abs(lx) < deadzone and math.abs(ly) < deadzone then
		return
	end

	local model = _selectedEntry.model
	if not model or not model.PrimaryPart then
		return
	end

	local speed = 0.5 -- studs per frame at full deflection
	local pos = model:GetPivot().Position
	local newPos = Vector3.new(pos.X + lx * speed, 0, pos.Z - ly * speed)
	moveModelTo(newPos)
end

-- ═══════════════════════════════════════════════════════════════════
-- UI
-- ═══════════════════════════════════════════════════════════════════

local function makeToolbarButton(name: string, label: string, color: Color3, order: number, parent: Frame): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, TOOLBAR_BTN, 0, TOOLBAR_BTN)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Text = label
	btn.TextColor3 = COLORS.text
	btn.TextSize = if IS_CONSOLE then 18 elseif IS_MOBILE then 16 else 14
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	btn.LayoutOrder = order
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	return btn
end

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "EditGui"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 12
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	_gui.Enabled = false
	_gui.Parent = Player.PlayerGui

	-- Toolbar at bottom center
	_toolbar = Instance.new("Frame")
	_toolbar.Name = "EditToolbar"
	local toolbarWidth = if IS_MOBILE then UDim2.new(0.9, 0, 0, 0) else UDim2.new(0, 340, 0, 0)
	_toolbar.Size = toolbarWidth
	_toolbar.AutomaticSize = Enum.AutomaticSize.Y
	_toolbar.Position = UDim2.new(0.5, 0, 1, -10)
	_toolbar.AnchorPoint = Vector2.new(0.5, 1)
	_toolbar.BackgroundColor3 = COLORS.bg
	_toolbar.BackgroundTransparency = 0.1
	_toolbar.BorderSizePixel = 0
	_toolbar.Visible = false
	_toolbar.Parent = _gui

	local toolbarCorner = Instance.new("UICorner")
	toolbarCorner.CornerRadius = UDim.new(0, 12)
	toolbarCorner.Parent = _toolbar

	local toolbarPadding = Instance.new("UIPadding")
	toolbarPadding.PaddingTop = UDim.new(0, 8)
	toolbarPadding.PaddingBottom = UDim.new(0, 8)
	toolbarPadding.PaddingLeft = UDim.new(0, 10)
	toolbarPadding.PaddingRight = UDim.new(0, 10)
	toolbarPadding.Parent = _toolbar

	local toolbarLayout = Instance.new("UIListLayout")
	toolbarLayout.FillDirection = Enum.FillDirection.Vertical
	toolbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toolbarLayout.Padding = UDim.new(0, 6)
	toolbarLayout.Parent = _toolbar

	-- Model name label
	_nameLabel = Instance.new("TextLabel")
	_nameLabel.Name = "ModelName"
	_nameLabel.Size = UDim2.new(1, 0, 0, 24)
	_nameLabel.BackgroundTransparency = 1
	_nameLabel.Text = ""
	_nameLabel.TextColor3 = COLORS.accent
	_nameLabel.TextSize = FONT_MD
	_nameLabel.Font = Enum.Font.GothamBold
	_nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	_nameLabel.LayoutOrder = 1
	_nameLabel.Parent = _toolbar

	-- Button row
	local btnRow = Instance.new("Frame")
	btnRow.Name = "ButtonRow"
	btnRow.Size = UDim2.new(1, 0, 0, TOOLBAR_BTN)
	btnRow.BackgroundTransparency = 1
	btnRow.LayoutOrder = 2
	btnRow.Parent = _toolbar

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	btnLayout.Padding = UDim.new(0, 6)
	btnLayout.Parent = btnRow

	-- Rotate left
	local rotLeftBtn = makeToolbarButton("RotLeft", "<", COLORS.accentDim, 1, btnRow)
	rotLeftBtn.Activated:Connect(function()
		rotate(-ROTATION_INCREMENT)
	end)

	-- Rotate right
	local rotRightBtn = makeToolbarButton("RotRight", ">", COLORS.accentDim, 2, btnRow)
	rotRightBtn.Activated:Connect(function()
		rotate(ROTATION_INCREMENT)
	end)

	-- Grid toggle
	local gridBtn = makeToolbarButton("Grid", "Grid:" .. tostring(_gridSize), COLORS.accentDim, 3, btnRow)
	gridBtn.Activated:Connect(function()
		_gridIndex = (_gridIndex % #GRID_SIZES) + 1
		_gridSize = GRID_SIZES[_gridIndex]
		local display = if _gridSize == 0 then "Off" else tostring(_gridSize)
		gridBtn.Text = "Grid:" .. display
	end)

	-- Delete
	local deleteBtn = makeToolbarButton("Delete", "X", COLORS.danger, 4, btnRow)
	deleteBtn.Activated:Connect(function()
		deleteSelected()
	end)

	-- Done
	local doneBtn = makeToolbarButton("Done", "OK", COLORS.success, 5, btnRow)
	doneBtn.Size = UDim2.new(0, TOOLBAR_BTN + 12, 0, TOOLBAR_BTN)
	doneBtn.Activated:Connect(function()
		EditController:Hide()
	end)

	-- Status label (top center, brief messages)
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "EditStatus"
	_statusLabel.Size = UDim2.new(0, 300, 0, 30)
	_statusLabel.Position = UDim2.new(0.5, 0, 0, 80)
	_statusLabel.AnchorPoint = Vector2.new(0.5, 0)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.accent
	_statusLabel.TextSize = FONT_MD
	_statusLabel.Font = Enum.Font.GothamBold
	_statusLabel.Parent = _gui

	-- Hint label
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "EditHint"
	hintLabel.Size = UDim2.new(0, 400, 0, 20)
	hintLabel.Position = UDim2.new(0.5, 0, 0, 50)
	hintLabel.AnchorPoint = Vector2.new(0.5, 0)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextColor3 = COLORS.textDim
	hintLabel.TextSize = FONT_SM
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.Parent = _gui

	if IS_MOBILE then
		hintLabel.Text = "Tap to select, drag to move, use buttons to rotate"
	elseif IS_CONSOLE then
		hintLabel.Text = "A to select, stick to move, LB/RB rotate, X delete"
	else
		hintLabel.Text = "Click to select, drag to move, Q/E rotate, X delete"
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Public API
-- ═══════════════════════════════════════════════════════════════════

function EditController:Show()
	if _editMode then
		return
	end
	_editMode = true

	if _gui then
		_gui.Enabled = true
	end

	-- Connect input
	_inputBeganConn = UserInputService.InputBegan:Connect(onInputBegan)
	_inputChangedConn = UserInputService.InputChanged:Connect(onInputChanged)
	_inputEndedConn = UserInputService.InputEnded:Connect(onInputEnded)
	_heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)

	setStatus("Edit Mode — select a model")
end

function EditController:Hide()
	if not _editMode then
		return
	end
	_editMode = false

	deselect()

	if _gui then
		_gui.Enabled = false
	end

	-- Disconnect input
	if _inputBeganConn then
		_inputBeganConn:Disconnect()
		_inputBeganConn = nil
	end
	if _inputChangedConn then
		_inputChangedConn:Disconnect()
		_inputChangedConn = nil
	end
	if _inputEndedConn then
		_inputEndedConn:Disconnect()
		_inputEndedConn = nil
	end
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end
end

function EditController:Toggle()
	if _editMode then
		self:Hide()
	else
		self:Show()
	end
end

function EditController:IsActive(): boolean
	return _editMode
end

function EditController:KnitInit() end

function EditController:KnitStart()
	createUI()
end

return EditController
