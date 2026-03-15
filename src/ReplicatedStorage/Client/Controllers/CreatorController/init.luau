local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

-- Platform detection
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()

-- Responsive sizing helpers
local FONT_SM = if IS_CONSOLE then 16 elseif IS_MOBILE then 13 else 11
local FONT_MD = if IS_CONSOLE then 20 elseif IS_MOBILE then 16 else 14
local FONT_LG = if IS_CONSOLE then 24 elseif IS_MOBILE then 18 else 16
local BTN_HEIGHT = if IS_CONSOLE then 44 elseif IS_MOBILE then 36 else 28
local ROW_HEIGHT = if IS_CONSOLE then 48 elseif IS_MOBILE then 44 else 40
local SIDEBAR_SIZE = if IS_CONSOLE then 52 elseif IS_MOBILE then 44 else 34

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local GameMode = require(ReplicatedStorage.Shared.GameMode)

local Player = Players.LocalPlayer

-- Sound effects (built-in engine sounds — no asset ownership needed)
local _successSound = Instance.new("Sound")
_successSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
_successSound.Volume = 0.5
_successSound.Parent = SoundService

local _failSound = Instance.new("Sound")
_failSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
_failSound.Volume = 0.4
_failSound.Parent = SoundService

local CreatorController = Knit.CreateController({
	Name = "CreatorController",
})

local _trove = Trove.new()
local _selectedCategory = "creature"
local _selectedStyle = "origami"
local _selectedModel = "haiku"
local _gui: ScreenGui
local _inputBox: TextBox
local _statusLabel: TextLabel
local _createButton: TextButton
local _clearButton: TextButton
local _categoryButtons: { [string]: TextButton } = {}
local _styleButtons: { [string]: TextButton } = {}
local _modelButtons: { [string]: TextButton } = {}
local _queueFrame: Frame
local _queueEntries: { { frame: Frame, label: TextLabel, dot: TextLabel } } = {}
local _nextQueueId = 0
local _uiMinimized = false

-- Track all spawned creations for Clear
local _spawnedModels: { Model } = {}
local _equippedTool: Tool? = nil
local _equippedAccessory: BasePart? = nil

-- Attachment slot config: body part name, offset function (from body part size), max accessory size
local ATTACH_CONFIG = {
	head = { bodyPart = "Head", offset = function(s) return CFrame.new(0, s.Y / 2, 0) end, maxSize = 3 },
	face = { bodyPart = "Head", offset = function(s) return CFrame.new(0, 0, -s.Z / 2) end, maxSize = 2.5 },
	neck = { bodyPart = "UpperTorso", offset = function(s) return CFrame.new(0, s.Y / 2, 0) end, maxSize = 3 },
	back = { bodyPart = "UpperTorso", offset = function(s) return CFrame.new(0, 0, s.Z / 2) end, maxSize = 5 },
	chest = { bodyPart = "UpperTorso", offset = function(s) return CFrame.new(0, 0, -s.Z / 2) end, maxSize = 3 },
	waist = { bodyPart = "LowerTorso", offset = function(s) return CFrame.new(0, 0, 0) end, maxSize = 4 },
	shoulders = { bodyPart = "UpperTorso", offset = function(s) return CFrame.new(0, s.Y / 2, 0) end, maxSize = 4 },
}
local _activeVehicle: Model? = nil
local _vehicleSeat: VehicleSeat? = nil
local _avatarApplied = false

-- Currency state
local _foldsCount = 0
local _craneCount = 0
local _foldsLabel: TextLabel
local _craneLabel: TextLabel

-- Catalog browser state
local _browseButton: TextButton
local _catalogPanel: Frame
local _catalogScroll: ScrollingFrame
local _catalogSearchBox: TextBox
local _catalogCache: { any }? = nil
local _catalogOpen = false

-- Colors
local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(100, 180, 255),
	accentDim = Color3.fromRGB(60, 100, 160),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	disabled = Color3.fromRGB(80, 80, 90),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	danger = Color3.fromRGB(200, 60, 60),
	folds = Color3.fromRGB(255, 200, 50),
	crane = Color3.fromRGB(100, 160, 255),
}

local function createUI()
	-- Main ScreenGui
	_gui = Instance.new("ScreenGui")
	_gui.Name = "OrigamiCreator"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 5
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Currency bar (top center) — hidden until economy is live
	local currencyBar = Instance.new("Frame")
	currencyBar.Name = "CurrencyBar"
	currencyBar.Size = UDim2.new(0, 200, 0, 32)
	currencyBar.Position = UDim2.new(0.5, -100, 0, 8)
	currencyBar.BackgroundColor3 = COLORS.bg
	currencyBar.BackgroundTransparency = 0.2
	currencyBar.BorderSizePixel = 0
	currencyBar.Visible = false
	currencyBar.Parent = _gui

	local currBarCorner = Instance.new("UICorner")
	currBarCorner.CornerRadius = UDim.new(0, 8)
	currBarCorner.Parent = currencyBar

	-- Folds display (left half)
	local foldsIcon = Instance.new("TextLabel")
	foldsIcon.Name = "FoldsIcon"
	foldsIcon.Size = UDim2.new(0, 24, 1, 0)
	foldsIcon.Position = UDim2.new(0, 8, 0, 0)
	foldsIcon.BackgroundTransparency = 1
	foldsIcon.Text = "F"
	foldsIcon.TextColor3 = COLORS.folds
	foldsIcon.TextSize = 16
	foldsIcon.Font = Enum.Font.GothamBold
	foldsIcon.Parent = currencyBar

	_foldsLabel = Instance.new("TextLabel")
	_foldsLabel.Name = "FoldsCount"
	_foldsLabel.Size = UDim2.new(0, 60, 1, 0)
	_foldsLabel.Position = UDim2.new(0, 30, 0, 0)
	_foldsLabel.BackgroundTransparency = 1
	_foldsLabel.Text = "0"
	_foldsLabel.TextColor3 = COLORS.folds
	_foldsLabel.TextSize = 14
	_foldsLabel.Font = Enum.Font.GothamBold
	_foldsLabel.TextXAlignment = Enum.TextXAlignment.Left
	_foldsLabel.Parent = currencyBar

	-- Cranes display (right half)
	local craneIcon = Instance.new("TextLabel")
	craneIcon.Name = "CraneIcon"
	craneIcon.Size = UDim2.new(0, 24, 1, 0)
	craneIcon.Position = UDim2.new(0, 108, 0, 0)
	craneIcon.BackgroundTransparency = 1
	craneIcon.Text = ">"
	craneIcon.TextColor3 = COLORS.crane
	craneIcon.TextSize = 14
	craneIcon.Font = Enum.Font.GothamBold
	craneIcon.Parent = currencyBar

	_craneLabel = Instance.new("TextLabel")
	_craneLabel.Name = "CraneCount"
	_craneLabel.Size = UDim2.new(0, 60, 1, 0)
	_craneLabel.Position = UDim2.new(0, 136, 0, 0)
	_craneLabel.BackgroundTransparency = 1
	_craneLabel.Text = "0"
	_craneLabel.TextColor3 = COLORS.crane
	_craneLabel.TextSize = 14
	_craneLabel.Font = Enum.Font.GothamBold
	_craneLabel.TextXAlignment = Enum.TextXAlignment.Left
	_craneLabel.Parent = currencyBar

	-- Container at bottom of screen (responsive)
	local containerWidth = if IS_MOBILE then 0.92 elseif IS_CONSOLE then 0.7 else 0.6
	local containerX = (1 - containerWidth) / 2
	local containerH = BTN_HEIGHT * 3 + ROW_HEIGHT + 40 -- 3 button rows + input row + padding
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(containerWidth, 0, 0, containerH)
	container.Position = UDim2.new(containerX, 0, 1, -(containerH + 64))
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	-- Minimize button (top-right of container) — hides panel, shows sidebar "Create" button
	local minBtnSize = if IS_MOBILE then 36 else 28
	local minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Name = "MinimizeBtn"
	minimizeBtn.Size = UDim2.new(0, minBtnSize, 0, minBtnSize)
	minimizeBtn.Position = UDim2.new(1, -(minBtnSize + 6), 0, 4)
	minimizeBtn.BackgroundColor3 = COLORS.danger
	minimizeBtn.BorderSizePixel = 0
	minimizeBtn.Text = "X"
	minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	minimizeBtn.TextSize = if IS_MOBILE then FONT_LG else FONT_MD
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.AutoButtonColor = true
	minimizeBtn.Parent = container

	local minBtnCorner = Instance.new("UICorner")
	minBtnCorner.CornerRadius = UDim.new(0, 6)
	minBtnCorner.Parent = minimizeBtn

	-- Minimize: hides the entire container, shows a sidebar "Create" button instead
	-- _sidebarCreateBtn is created later in the sidebar section; forward-declared here
	local _sidebarCreateBtn: TextButton?

	local function toggleMinimize()
		_uiMinimized = not _uiMinimized
		container.Visible = not _uiMinimized
		if _sidebarCreateBtn then
			_sidebarCreateBtn.Visible = _uiMinimized
		end
	end

	minimizeBtn.Activated:Connect(toggleMinimize)

	-- Style buttons row (scrollable)
	local styleClip = Instance.new("Frame")
	styleClip.Name = "StyleClip"
	styleClip.Size = UDim2.new(1, -20, 0, BTN_HEIGHT)
	styleClip.Position = UDim2.new(0, 10, 0, 8)
	styleClip.BackgroundTransparency = 1
	styleClip.ClipsDescendants = true
	styleClip.Parent = container

	local styleRow = Instance.new("ScrollingFrame")
	styleRow.Name = "StyleRow"
	styleRow.Size = UDim2.new(1, 0, 1, 0)
	styleRow.BackgroundTransparency = 1
	styleRow.BorderSizePixel = 0
	styleRow.ScrollBarThickness = 2
	styleRow.ScrollBarImageColor3 = COLORS.accentDim
	styleRow.ScrollingDirection = Enum.ScrollingDirection.X
	styleRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	styleRow.CanvasSize = UDim2.new(0, 0, 0, BTN_HEIGHT)
	styleRow.Parent = styleClip

	local styleLayout = Instance.new("UIListLayout")
	styleLayout.FillDirection = Enum.FillDirection.Horizontal
	styleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	styleLayout.Padding = UDim.new(0, 4)
	styleLayout.Parent = styleRow

	for _, sty in ipairs(OrigamiConfig.STYLES) do
		local btn = Instance.new("TextButton")
		btn.Name = "Style_" .. sty.key
		btn.Size = UDim2.new(0, if IS_CONSOLE then 100 elseif IS_MOBILE then 80 else 68, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = sty.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = FONT_SM
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = styleRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_styleButtons[sty.key] = btn

		btn.Activated:Connect(function()
			_selectedStyle = sty.key
			updateStyleHighlights()
		end)
	end

	-- Model selector row (scrollable)
	local modelClip = Instance.new("Frame")
	modelClip.Name = "ModelClip"
	modelClip.Size = UDim2.new(1, -20, 0, BTN_HEIGHT)
	modelClip.Position = UDim2.new(0, 10, 0, BTN_HEIGHT + 12)
	modelClip.BackgroundTransparency = 1
	modelClip.ClipsDescendants = true
	modelClip.Parent = container

	local modelRow = Instance.new("ScrollingFrame")
	modelRow.Name = "ModelRow"
	modelRow.Size = UDim2.new(1, 0, 1, 0)
	modelRow.BackgroundTransparency = 1
	modelRow.BorderSizePixel = 0
	modelRow.ScrollBarThickness = 2
	modelRow.ScrollBarImageColor3 = COLORS.accentDim
	modelRow.ScrollingDirection = Enum.ScrollingDirection.X
	modelRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	modelRow.CanvasSize = UDim2.new(0, 0, 0, BTN_HEIGHT)
	modelRow.Parent = modelClip

	local modelLayout = Instance.new("UIListLayout")
	modelLayout.FillDirection = Enum.FillDirection.Horizontal
	modelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	modelLayout.Padding = UDim.new(0, 4)
	modelLayout.Parent = modelRow

	-- "Model:" label
	local modelLabel = Instance.new("TextLabel")
	modelLabel.Name = "ModelLabel"
	modelLabel.Size = UDim2.new(0, if IS_CONSOLE then 60 else 44, 1, 0)
	modelLabel.BackgroundTransparency = 1
	modelLabel.Text = "Model:"
	modelLabel.TextColor3 = COLORS.textDim
	modelLabel.TextSize = FONT_SM
	modelLabel.Font = Enum.Font.GothamBold
	modelLabel.TextXAlignment = Enum.TextXAlignment.Left
	modelLabel.Parent = modelRow

	for _, mdl in ipairs(OrigamiConfig.MODELS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Model_" .. mdl.key
		btn.Size = UDim2.new(0, if IS_CONSOLE then 90 elseif IS_MOBILE then 72 else 60, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = mdl.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = FONT_SM
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = modelRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_modelButtons[mdl.key] = btn

		btn.Activated:Connect(function()
			_selectedModel = mdl.key
			updateModelHighlights()
		end)
	end

	-- Category buttons row
	local categoryRow = Instance.new("Frame")
	categoryRow.Name = "CategoryRow"
	categoryRow.Size = UDim2.new(1, -20, 0, BTN_HEIGHT + 4)
	categoryRow.Position = UDim2.new(0, 10, 0, (BTN_HEIGHT + 12) * 2)
	categoryRow.BackgroundTransparency = 1
	categoryRow.Parent = container

	local categoryLayout = Instance.new("UIListLayout")
	categoryLayout.FillDirection = Enum.FillDirection.Horizontal
	categoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	categoryLayout.Padding = UDim.new(0, 6)
	categoryLayout.Parent = categoryRow

	for _, cat in ipairs(OrigamiConfig.CATEGORIES) do
		-- Animation category is handled by AnimatorController
		if cat.key == "animation" then
			continue
		end

		local btn = Instance.new("TextButton")
		btn.Name = "Cat_" .. cat.key
		btn.Size = UDim2.new(0, if IS_CONSOLE then 100 elseif IS_MOBILE then 80 else 72, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = cat.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = FONT_SM + 1
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = categoryRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_categoryButtons[cat.key] = btn

		btn.Activated:Connect(function()
			_selectedCategory = cat.key
			updateCategoryHighlights()
		end)
	end

	-- Input row
	inputRow = Instance.new("Frame")
	inputRow.Name = "InputRow"
	inputRow.Size = UDim2.new(1, -20, 0, ROW_HEIGHT)
	inputRow.Position = UDim2.new(0, 10, 0, (BTN_HEIGHT + 12) * 2 + BTN_HEIGHT + 12)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = container

	-- Text input box
	_inputBox = Instance.new("TextBox")
	_inputBox.Name = "PromptInput"
	_inputBox.Size = UDim2.new(1, if IS_MOBILE then -140 else -180, 1, 0)
	_inputBox.Position = UDim2.new(0, 0, 0, 0)
	_inputBox.BackgroundColor3 = COLORS.bgLight
	_inputBox.BorderSizePixel = 0
	_inputBox.PlaceholderText = "Type anything..."
	_inputBox.PlaceholderColor3 = COLORS.textDim
	_inputBox.Text = ""
	_inputBox.TextColor3 = COLORS.text
	_inputBox.TextSize = FONT_LG
	_inputBox.Font = Enum.Font.Gotham
	_inputBox.ClearTextOnFocus = false
	_inputBox.Parent = inputRow

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = _inputBox

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 12)
	inputPadding.PaddingRight = UDim.new(0, 12)
	inputPadding.Parent = _inputBox

	-- Create button
	_createButton = Instance.new("TextButton")
	_createButton.Name = "CreateButton"
	local createW = if IS_MOBILE then 68 else 88
	local clearW = if IS_MOBILE then 60 else 72
	_createButton.Size = UDim2.new(0, createW, 1, 0)
	_createButton.Position = UDim2.new(1, -(createW + clearW + 8), 0, 0)
	_createButton.BackgroundColor3 = COLORS.accent
	_createButton.BorderSizePixel = 0
	_createButton.Text = "Create"
	_createButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_createButton.TextSize = FONT_LG
	_createButton.Font = Enum.Font.GothamBold
	_createButton.AutoButtonColor = true
	_createButton.Parent = inputRow

	local createCorner = Instance.new("UICorner")
	createCorner.CornerRadius = UDim.new(0, 8)
	createCorner.Parent = _createButton

	-- Clear button
	_clearButton = Instance.new("TextButton")
	_clearButton.Name = "ClearButton"
	_clearButton.Size = UDim2.new(0, clearW, 1, 0)
	_clearButton.Position = UDim2.new(1, -clearW, 0, 0)
	_clearButton.BackgroundColor3 = COLORS.danger
	_clearButton.BorderSizePixel = 0
	_clearButton.Text = "Clear"
	_clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_clearButton.TextSize = FONT_LG
	_clearButton.Font = Enum.Font.GothamBold
	_clearButton.AutoButtonColor = true
	_clearButton.Parent = inputRow

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 8)
	clearCorner.Parent = _clearButton

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "StatusLabel"
	_statusLabel.Size = UDim2.new(1, -20, 0, 20)
	_statusLabel.Position = UDim2.new(0, 10, 1, -24)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.TextSize = FONT_SM + 1
	_statusLabel.Font = Enum.Font.Gotham
	_statusLabel.Parent = container

	-- Start minimized on mobile
	if IS_MOBILE then
		toggleMinimize()
	end

	-- Wire up submit
	_createButton.Activated:Connect(function()
		submitPrompt()
	end)

	_inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitPrompt()
		end
	end)

	-- Wire up clear
	_clearButton.Activated:Connect(function()
		clearAllCreations()
	end)

	-- Queue panel (right side of screen)
	_queueFrame = Instance.new("Frame")
	_queueFrame.Name = "QueuePanel"
	local queueW = if IS_MOBILE then 180 elseif IS_CONSOLE then 280 else 240
	_queueFrame.Size = UDim2.new(0, queueW, 0, 300)
	_queueFrame.Position = UDim2.new(1, -(queueW + 10), 0.5, -150)
	_queueFrame.AnchorPoint = Vector2.new(0, 0)
	_queueFrame.BackgroundColor3 = COLORS.bg
	_queueFrame.BackgroundTransparency = 0.15
	_queueFrame.BorderSizePixel = 0
	_queueFrame.Visible = false
	_queueFrame.AutomaticSize = Enum.AutomaticSize.Y
	_queueFrame.Parent = _gui

	local queueCorner = Instance.new("UICorner")
	queueCorner.CornerRadius = UDim.new(0, 10)
	queueCorner.Parent = _queueFrame

	local queueLayout = Instance.new("UIListLayout")
	queueLayout.FillDirection = Enum.FillDirection.Vertical
	queueLayout.Padding = UDim.new(0, 4)
	queueLayout.SortOrder = Enum.SortOrder.LayoutOrder
	queueLayout.Parent = _queueFrame

	local queuePadding = Instance.new("UIPadding")
	queuePadding.PaddingTop = UDim.new(0, 8)
	queuePadding.PaddingBottom = UDim.new(0, 8)
	queuePadding.PaddingLeft = UDim.new(0, 8)
	queuePadding.PaddingRight = UDim.new(0, 8)
	queuePadding.Parent = _queueFrame

	-- Left sidebar with toggle buttons (own ScreenGui so it stays visible in all modes)
	local sidebarGui = Instance.new("ScreenGui")
	sidebarGui.Name = "SidebarGui"
	sidebarGui.ResetOnSpawn = false
	sidebarGui.DisplayOrder = 10
	sidebarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sidebarGui.Parent = Player.PlayerGui

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, SIDEBAR_SIZE + 8, 0, 0)
	sidebar.Position = UDim2.new(0, 10, 0.5, 0)
	sidebar.AnchorPoint = Vector2.new(0, 0.5)
	sidebar.AutomaticSize = Enum.AutomaticSize.Y
	sidebar.BackgroundColor3 = COLORS.bg
	sidebar.BackgroundTransparency = 0.1
	sidebar.BorderSizePixel = 0
	sidebar.Parent = sidebarGui

	local sidebarCorner = Instance.new("UICorner")
	sidebarCorner.CornerRadius = UDim.new(0, 10)
	sidebarCorner.Parent = sidebar

	local sidebarPadding = Instance.new("UIPadding")
	sidebarPadding.PaddingTop = UDim.new(0, 4)
	sidebarPadding.PaddingBottom = UDim.new(0, 4)
	sidebarPadding.PaddingLeft = UDim.new(0, 4)
	sidebarPadding.PaddingRight = UDim.new(0, 4)
	sidebarPadding.Parent = sidebar

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.FillDirection = Enum.FillDirection.Vertical
	sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sidebarLayout.Padding = UDim.new(0, 4)
	sidebarLayout.Parent = sidebar

	-- Helper to make sidebar icon buttons
	local function makeSidebarButton(name: string, label: string, color: Color3, order: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(0, SIDEBAR_SIZE, 0, SIDEBAR_SIZE)
		btn.BackgroundColor3 = color
		btn.BorderSizePixel = 0
		btn.Text = label
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.TextSize = if IS_CONSOLE then 14 elseif IS_MOBILE then 11 else 9
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.LayoutOrder = order
		btn.Parent = sidebar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = btn

		return btn
	end

	local modesBtn = makeSidebarButton("ModesBtn", "Mode", COLORS.accentDim, 1)
	local animBtn = makeSidebarButton("AnimBtn", "Anim", Color3.fromRGB(60, 140, 120), 2)

	-- "Create" sidebar button — visible only when creator UI is minimized
	_sidebarCreateBtn = makeSidebarButton("CreateBtn", "Create", COLORS.accent, 3)
	_sidebarCreateBtn.Visible = _uiMinimized
	_sidebarCreateBtn.Activated:Connect(function()
		toggleMinimize()
	end)

	modesBtn.Activated:Connect(function()
		local GameModeController = Knit.GetController("GameModeController")
		if GameModeController then
			GameModeController:Toggle()
		end
	end)

	animBtn.Activated:Connect(function()
		local AnimatorController = Knit.GetController("AnimatorController")
		if AnimatorController then
			AnimatorController:Toggle()
		end
	end)

	-- Browse button
	_browseButton = Instance.new("TextButton")
	_browseButton.Name = "BrowseToggle"
	_browseButton.Size = UDim2.new(0, if IS_CONSOLE then 140 else 100, 0, if IS_MOBILE then 40 else 32)
	_browseButton.Position = UDim2.new(0, 10, 0, 48)
	_browseButton.BackgroundColor3 = COLORS.folds
	_browseButton.BorderSizePixel = 0
	_browseButton.Text = "Browse"
	_browseButton.TextColor3 = Color3.fromRGB(30, 30, 30)
	_browseButton.TextSize = 14
	_browseButton.Font = Enum.Font.GothamBold
	_browseButton.AutoButtonColor = true
	_browseButton.Parent = _gui

	local browseCorner = Instance.new("UICorner")
	browseCorner.CornerRadius = UDim.new(0, 8)
	browseCorner.Parent = _browseButton

	-- Catalog panel (left side)
	_catalogPanel = Instance.new("Frame")
	_catalogPanel.Name = "CatalogPanel"
	_catalogPanel.Size = if IS_MOBILE then UDim2.new(0.85, 0, 0, 350) elseif IS_CONSOLE then UDim2.new(0, 320, 0, 450) else UDim2.new(0, 260, 0, 400)
	_catalogPanel.Position = UDim2.new(0, 10, 0, 86)
	_catalogPanel.BackgroundColor3 = COLORS.bg
	_catalogPanel.BackgroundTransparency = 0.1
	_catalogPanel.BorderSizePixel = 0
	_catalogPanel.Visible = false
	_catalogPanel.Parent = _gui

	local catPanelCorner = Instance.new("UICorner")
	catPanelCorner.CornerRadius = UDim.new(0, 10)
	catPanelCorner.Parent = _catalogPanel

	-- Search box
	_catalogSearchBox = Instance.new("TextBox")
	_catalogSearchBox.Name = "CatalogSearch"
	_catalogSearchBox.Size = UDim2.new(1, -16, 0, 28)
	_catalogSearchBox.Position = UDim2.new(0, 8, 0, 8)
	_catalogSearchBox.BackgroundColor3 = COLORS.bgLight
	_catalogSearchBox.BorderSizePixel = 0
	_catalogSearchBox.PlaceholderText = "Search items..."
	_catalogSearchBox.PlaceholderColor3 = COLORS.textDim
	_catalogSearchBox.Text = ""
	_catalogSearchBox.TextColor3 = COLORS.text
	_catalogSearchBox.TextSize = 13
	_catalogSearchBox.Font = Enum.Font.Gotham
	_catalogSearchBox.ClearTextOnFocus = false
	_catalogSearchBox.Parent = _catalogPanel

	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 6)
	searchCorner.Parent = _catalogSearchBox

	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 8)
	searchPad.PaddingRight = UDim.new(0, 8)
	searchPad.Parent = _catalogSearchBox

	-- Scrolling frame for items
	_catalogScroll = Instance.new("ScrollingFrame")
	_catalogScroll.Name = "CatalogScroll"
	_catalogScroll.Size = UDim2.new(1, -16, 1, -48)
	_catalogScroll.Position = UDim2.new(0, 8, 0, 42)
	_catalogScroll.BackgroundTransparency = 1
	_catalogScroll.BorderSizePixel = 0
	_catalogScroll.ScrollBarThickness = 4
	_catalogScroll.ScrollBarImageColor3 = COLORS.accentDim
	_catalogScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	_catalogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	_catalogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	_catalogScroll.Parent = _catalogPanel

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.Padding = UDim.new(0, 4)
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Parent = _catalogScroll

	-- Browse button toggle
	_browseButton.Activated:Connect(function()
		_catalogOpen = not _catalogOpen
		_catalogPanel.Visible = _catalogOpen
		if _catalogOpen then
			loadCatalog()
		end
	end)

	-- Search filtering
	_catalogSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		if _catalogCache then
			filterCatalog(_catalogSearchBox.Text)
		end
	end)

	_gui.Parent = Player.PlayerGui

	updateStyleHighlights()
	updateModelHighlights()
	updateCategoryHighlights()
end

function updateModelHighlights()
	for key, btn in pairs(_modelButtons) do
		if key == _selectedModel then
			btn.BackgroundColor3 = COLORS.accentDim
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
end

function updateStyleHighlights()
	for key, btn in pairs(_styleButtons) do
		if key == _selectedStyle then
			btn.BackgroundColor3 = COLORS.accentDim
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
end

function updateCategoryHighlights()
	for key, btn in pairs(_categoryButtons) do
		if key == _selectedCategory then
			btn.BackgroundColor3 = COLORS.accent
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
end

function clearAllCreations()
	-- Remove all spawned models from workspace
	for _, model in ipairs(_spawnedModels) do
		if model and model.Parent then
			model:Destroy()
		end
	end
	_spawnedModels = {}

	-- Remove equipped tool
	if _equippedTool then
		_equippedTool:Destroy()
		_equippedTool = nil
	end

	-- Remove equipped accessory parts
	_equippedAccessory = nil

	-- Remove active vehicle visual model + server-side seats
	_activeVehicle = nil
	_vehicleSeat = nil
	local OrigamiService = Knit.GetService("OrigamiService")
	OrigamiService:DestroyVehicleSeats():catch(function(err)
		warn("[Clear] Failed to destroy server vehicle seats:", err)
	end)

	-- Reset avatar
	if _avatarApplied then
		OrigamiService:ResetAvatar():await()
		_avatarApplied = false
	end

	-- Also remove any leftover origami tools from backpack/character
	local character = Player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("OrigamiTool") then
				child:Destroy()
			end
			if child:GetAttribute("OrigamiHat") then
				child:Destroy()
			end
		end
	end

	local backpack = Player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("OrigamiTool") then
				child:Destroy()
			end
		end
	end

	setStatus("All creations cleared!", COLORS.textDim)
end

function addQueueEntry(prompt: string, category: string): number
	_nextQueueId += 1
	local id = _nextQueueId

	local entry = Instance.new("Frame")
	entry.Name = "QueueEntry_" .. id
	entry.Size = UDim2.new(1, 0, 0, 28)
	entry.BackgroundColor3 = COLORS.bgLight
	entry.BackgroundTransparency = 0.3
	entry.BorderSizePixel = 0
	entry.LayoutOrder = id
	entry.Parent = _queueFrame

	local entryCorner = Instance.new("UICorner")
	entryCorner.CornerRadius = UDim.new(0, 6)
	entryCorner.Parent = entry

	-- Status dot
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.Position = UDim2.new(0, 6, 0.5, -4)
	dot.BackgroundColor3 = COLORS.accent
	dot.BorderSizePixel = 0
	dot.Parent = entry

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	-- Label
	local shortPrompt = prompt:sub(1, 22) .. (if #prompt > 22 then "..." else "")
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 20, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = shortPrompt .. "  Folding..."
	label.TextColor3 = COLORS.text
	label.TextSize = 11
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = entry

	_queueEntries[id] = { frame = entry, label = label, dot = dot, prompt = prompt }
	_queueFrame.Visible = true

	return id
end

function updateQueueEntry(id: number, status: string, color: Color3)
	local entry = _queueEntries[id]
	if not entry then
		return
	end

	local shortPrompt = entry.prompt:sub(1, 22) .. (if #entry.prompt > 22 then "..." else "")
	entry.label.Text = shortPrompt .. "  " .. status
	entry.dot.BackgroundColor3 = color
end

function removeQueueEntry(id: number)
	local entry = _queueEntries[id]
	if not entry then
		return
	end

	task.delay(5, function()
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
		_queueEntries[id] = nil

		-- Hide queue panel if empty
		local hasEntries = false
		for _ in pairs(_queueEntries) do
			hasEntries = true
			break
		end
		if not hasEntries then
			_queueFrame.Visible = false
		end
	end)
end

function updateCurrencyDisplay()
	if _foldsLabel then
		_foldsLabel.Text = tostring(_foldsCount)
	end
	if _craneLabel then
		_craneLabel.Text = tostring(_craneCount)
	end
end


local TEST_MODELS = { "haiku", "flash_lite", "gpt4o_mini" }
local TEST_DISPLAY = { haiku = "Haiku", flash_lite = "Flash", gpt4o_mini = "GPT4o" }
local TEST_SPACING = 8 -- studs between each test model

function submitSingleRequest(prompt: string, category: string, style: string, model: string, placementOffset: Vector3?, labelOverride: string?)
	-- Deduct cranes before sending request (skip in Studio)
	if not RunService:IsStudio() then
		local craneCost = OrigamiConfig.CRANE_COSTS[model] or 1
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local deductOk, deductResult = PlayerDataService:DeductCurrency("Cranes", craneCost):await()
		if not deductOk or not deductResult or not deductResult.success then
			setStatus("Not enough Cranes!", COLORS.error)
			return
		end
		_craneCount = deductResult.remaining
		updateCurrencyDisplay()
	end

	local queueId = addQueueEntry(prompt .. (if labelOverride then " [" .. labelOverride .. "]" else ""), category)

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, category, style, model):await()

		if ok and result and result.success and result.model then
			local modelData = result.model
			-- Use the user's selected category for routing — LLM category only as fallback for "raw"
			local cat = if category == "raw" then (modelData.category or "prop") else category

			local buildOk, buildErr = pcall(function()
				local builtModel = OrigamiBuilder.BuildModel(modelData)

				if placementOffset then
					-- Test mode: place at offset position with model label
					local character = Player.Character
					local rootPart = character and character:FindFirstChild("HumanoidRootPart")
					if rootPart then
						local basePos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
						local placePos = basePos + placementOffset
						builtModel.Parent = workspace

						local cf, size = builtModel:GetBoundingBox()
						local pivot = builtModel:GetPivot()
						local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
						builtModel:PivotTo(CFrame.new(placePos.X, rootPart.Position.Y + pivotAboveBottom, placePos.Z))
					else
						builtModel.Parent = workspace
					end

					-- Label with model name instead of creation name
					addNameLabel(builtModel, labelOverride or model)
					table.insert(_spawnedModels, builtModel)

					local animType = modelData.animation or "idle_bob"
					OrigamiBuilder.ApplyAnimation(builtModel, animType)
				else
					-- Normal mode: use category-specific placement
					if cat == "tool" then
						equipAsTool(builtModel, modelData)
					elseif cat == "accessory" or cat == "hat" then
						equipAsAccessory(builtModel, modelData)
					elseif cat == "vehicle" then
						spawnVehicle(builtModel, modelData)
					elseif cat == "avatar" then
						applyAvatar(builtModel, modelData)
					elseif cat == "building" then
						placeBuilding(builtModel, modelData)
					elseif cat == "creature" then
						spawnCreature(builtModel, modelData)
					else
						placeModel(builtModel, modelData)
					end

					if cat ~= "tool" and cat ~= "accessory" and cat ~= "hat" and cat ~= "vehicle" and cat ~= "avatar" and cat ~= "creature" then
						local animType = modelData.animation or "idle_bob"
						OrigamiBuilder.ApplyAnimation(builtModel, animType)
					end
				end
			end)

			if buildOk then
				local modelName = modelData.name or "Creation"
				updateQueueEntry(queueId, modelName, COLORS.success)
				_successSound:Play()
			else
				warn("[OrigamiCreator] Build/place error:", buildErr)
				updateQueueEntry(queueId, "Build error", COLORS.error)
				_failSound:Play()
			end
		else
			local errMsg = (ok and result and result.error) or (not ok and tostring(result)) or "Unknown error"
			warn("[OrigamiCreator] Request failed:", errMsg)
			updateQueueEntry(queueId, "Failed: " .. errMsg:sub(1, 30), COLORS.error)
			_failSound:Play()
		end

		removeQueueEntry(queueId)
	end)
end

function submitPrompt()
	local prompt = _inputBox.Text
	if not prompt or prompt:match("^%s*$") then
		setStatus("Type something first!", COLORS.error)
		return
	end

	local category = _selectedCategory
	local style = _selectedStyle
	local model = _selectedModel
	_inputBox.Text = ""

	if model == "test" then
		-- Test All mode: fire all test models in parallel, placed in a line
		local totalWidth = (#TEST_MODELS - 1) * TEST_SPACING
		local character = Player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local rightVector = if rootPart then rootPart.CFrame.RightVector else Vector3.new(1, 0, 0)

		for i, testModel in ipairs(TEST_MODELS) do
			local offsetDist = -totalWidth / 2 + (i - 1) * TEST_SPACING
			local offset = rightVector * offsetDist
			submitSingleRequest(prompt, category, style, testModel, offset, TEST_DISPLAY[testModel])
		end
	else
		-- Normal single-model mode
		submitSingleRequest(prompt, category, style, model)
	end
end

local function executeHitActions(actions, startIndex, hitResult, character, params, ray)
	for i = startIndex, #actions do
		local act = actions[i]
		local action = act.action

		-- Auto-raycast if no hit target yet
		if not hitResult and action ~= "spawn" and action ~= "raycast" then
			hitResult = workspace:Raycast(ray.Origin, ray.Direction * 20, params)
		end

		if action == "raycast" then
			local range = act.range or 20
			hitResult = workspace:Raycast(ray.Origin, ray.Direction * range, params)

		elseif action == "destroy" then
			if hitResult and hitResult.Instance then
				local radius = act.radius or 0
				if radius > 0 then
					for _, p in workspace:GetPartBoundsInRadius(hitResult.Position, radius) do
						if not p:IsDescendantOf(character) then p:Destroy() end
					end
				else
					hitResult.Instance:Destroy()
				end
			end

		elseif action == "force" then
			if hitResult and hitResult.Instance then
				local hit = hitResult.Instance
				if hit.Anchored then hit.Anchored = false end
				local mag = act.magnitude or 50
				local dirType = act.direction or "forward"
				local forceDir
				if dirType == "up" then
					forceDir = Vector3.new(0, 1, 0)
				elseif dirType == "away" then
					forceDir = (hit.Position - ray.Origin).Unit
				else
					forceDir = ray.Direction
				end
				hit.AssemblyLinearVelocity = forceDir * mag
			end

		elseif action == "recolor" then
			if hitResult and hitResult.Instance then
				local hit = hitResult.Instance
				if act.color then
					hit.Color = Color3.fromRGB(act.color[1], act.color[2], act.color[3])
				end
				if act.material then
					hit.Material = Enum.Material[act.material] or hit.Material
				end
			end

		elseif action == "anchor" then
			if hitResult and hitResult.Instance then
				hitResult.Instance.Anchored = (act.freeze ~= false)
			end

		elseif action == "resize" then
			if hitResult and hitResult.Instance then
				local scale = math.clamp(act.scale or 1, 0.3, 3)
				hitResult.Instance.Size = hitResult.Instance.Size * scale
			end
		end
	end
end

function equipAsTool(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		return
	end

	-- Remove previous origami tool (only one at a time)
	if _equippedTool then
		_equippedTool:Destroy()
		_equippedTool = nil
	end

	-- Also remove from backpack
	local backpack = Player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("OrigamiTool") then
				child:Destroy()
			end
		end
	end

	-- Create a Roblox Tool
	local tool = Instance.new("Tool")
	tool.Name = modelData.name or "Tool"
	tool:SetAttribute("OrigamiTool", true)
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	-- Create handle from the model parts
	-- Weld all parts to a single Handle part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Parent = tool

	-- Move model parts into the tool and weld to handle
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
			part.Parent = tool
		end
	end

	-- Set grip so it's held properly (handle at bottom)
	tool.GripPos = Vector3.new(0, -0.5, 0)

	model:Destroy() -- Parts moved out, clean up empty model

	-- Put in backpack (auto-equips if only tool)
	tool.Parent = backpack or character
	_equippedTool = tool

	-- Track for clear
	table.insert(_spawnedModels, tool)

	-- Auto-equip
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end

	-- Wire up click behavior from LLM attributes
	local attrs = modelData.attributes or {}
	local actions = attrs.OnClick
	if actions and #actions > 0 then
		local cooldown = attrs.Cooldown or 0.5
		local lastClick = 0

		tool.Activated:Connect(function()
			local now = tick()
			if now - lastClick < cooldown then return end
			lastClick = now

			local character = Player.Character
			if not character then return end

			local camera = workspace.CurrentCamera
			local mouse = Player:GetMouse()
			local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { character }

			-- Find first spawn action index (if any)
			local spawnIndex = nil
			for i, act in actions do
				if act.action == "spawn" then
					spawnIndex = i
					break
				end
			end

			if spawnIndex then
				-- Phase 1: execute pre-spawn actions (raycasts before spawn are ignored for now)
				-- Phase 2: spawn projectiles, defer post-spawn actions to on-hit
				local act = actions[spawnIndex]
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if not rootPart then return end

				local count = act.count or 1
				local spread = math.rad(act.spread or 0)
				local speed = act.speed or 100
				local lifetime = act.lifetime or 3
				local useGravity = if act.gravity == false then false else true
				local size = act.size or 0.5
				local shape = act.shape or "Ball"
				local color = act.color or { 255, 200, 50 }
				local material = act.material or "Neon"
				local transparency = act.transparency or 0

				for i = 1, count do
					local dir = ray.Direction
					if spread > 0 then
						local rx = (math.random() - 0.5) * 2 * spread
						local ry = (math.random() - 0.5) * 2 * spread
						dir = (CFrame.new(Vector3.zero, dir) * CFrame.Angles(rx, ry, 0)).LookVector
					end

					local proj = Instance.new("Part")
					proj.Shape = Enum.PartType[shape] or Enum.PartType.Ball
					proj.Size = Vector3.new(size, size, size)
					proj.Material = Enum.Material[material] or Enum.Material.Neon
					proj.Color = Color3.fromRGB(color[1] or 255, color[2] or 200, color[3] or 50)
					proj.Transparency = transparency
					proj.CFrame = CFrame.new(rootPart.Position + ray.Direction * 3)
					proj.Anchored = false
					proj.CanCollide = true
					proj.Parent = workspace
					proj.AssemblyLinearVelocity = dir * speed
					if not useGravity then
						proj.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
					end
					Debris:AddItem(proj, lifetime)

					-- On-hit: run post-spawn actions on the touched target
					if spawnIndex < #actions then
						proj.Touched:Connect(function(touchedPart)
							if touchedPart:IsDescendantOf(character) or touchedPart == proj then return end
							local hitResult = { Instance = touchedPart, Position = proj.Position }
							executeHitActions(actions, spawnIndex + 1, hitResult, character, params, ray)
							proj:Destroy()
						end)
					end
				end
			else
				-- No spawn: execute all actions sequentially (raycast + hit actions)
				executeHitActions(actions, 1, nil, character, params, ray)
			end
		end)
	end
end

-- Check if accessory parts still exist on the character
local function _accessoryExists(character)
	for _, child in character:GetChildren() do
		if child:GetAttribute("OrigamiAccessory") or child:GetAttribute("OrigamiHat") then
			return true
		end
	end
	return false
end

-- Check key down with gamepad fallback
local function _isEffectKeyDown(keyCode)
	local keyDown = UserInputService:IsKeyDown(keyCode)
	if not keyDown then
		local gpMap = { [Enum.KeyCode.Space] = Enum.KeyCode.ButtonA, [Enum.KeyCode.E] = Enum.KeyCode.ButtonX, [Enum.KeyCode.Q] = Enum.KeyCode.ButtonY }
		local gpKey = gpMap[keyCode]
		if gpKey then
			keyDown = pcall(function() return UserInputService:IsGamepadButtonPressed(Enum.UserInputType.Gamepad1, gpKey) end) and UserInputService:IsGamepadButtonPressed(Enum.UserInputType.Gamepad1, gpKey)
		end
	end
	return keyDown
end

-- Wire fly effect: upward force on key hold, optional spinning parts
local function _wireFlyEffect(character, attachPart, attrs, keyCode)
	local flyForce = attrs.FlyForce or 40
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(0, math.huge, 0)
	bodyVel.Velocity = Vector3.zero
	bodyVel.Parent = rootPart
	bodyVel:SetAttribute("OrigamiAccessoryEffect", true)

	-- Spinning propeller parts
	local spinPartsPrefix = attrs.SpinParts
	local spinSpeed = math.rad(attrs.SpinSpeed or 720)
	local spinWelds = {}
	if spinPartsPrefix then
		for _, child in character:GetChildren() do
			if (child:GetAttribute("OrigamiAccessory") or child:GetAttribute("OrigamiHat")) and child.Name:lower():find(spinPartsPrefix:lower()) then
				for _, w in child:GetChildren() do
					if w:IsA("WeldConstraint") then
						local motor = Instance.new("Motor6D")
						motor.Part0 = attachPart
						motor.Part1 = child
						motor.C0 = attachPart.CFrame:ToObjectSpace(child.CFrame)
						motor.C1 = CFrame.new()
						motor.Parent = child
						w:Destroy()
						table.insert(spinWelds, motor)
						break
					end
				end
			end
		end
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not _accessoryExists(character) or not rootPart.Parent then
			conn:Disconnect(); bodyVel:Destroy(); return
		end
		local keyDown = _isEffectKeyDown(keyCode)
		bodyVel.Velocity = if keyDown then Vector3.new(0, flyForce, 0) else Vector3.zero
		if keyDown then
			for _, motor in spinWelds do
				motor.C0 = motor.C0 * CFrame.Angles(0, spinSpeed * dt, 0)
			end
		end
	end)
end

-- Wire speed effect: boost walk speed while worn
local function _wireSpeedEffect(character, attrs)
	local boost = attrs.SpeedBoost or 1.5
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local origSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = origSpeed * boost

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not _accessoryExists(character) then
			humanoid.WalkSpeed = origSpeed
			conn:Disconnect()
		end
	end)
end

-- Wire glow effect: toggle Neon material on key press
local function _wireGlowEffect(character, keyCode)
	local glowing = false
	-- Store original materials so we can restore them
	local origMaterials = {}
	for _, child in character:GetChildren() do
		if child:GetAttribute("OrigamiAccessory") or child:GetAttribute("OrigamiHat") then
			origMaterials[child] = child.Material
		end
	end

	local inputConn
	local cleanupConn
	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode ~= keyCode then return end
		glowing = not glowing
		for part, origMat in origMaterials do
			if part.Parent then
				part.Material = if glowing then Enum.Material.Neon else origMat
			end
		end
	end)

	cleanupConn = RunService.Heartbeat:Connect(function()
		if not _accessoryExists(character) then
			inputConn:Disconnect()
			cleanupConn:Disconnect()
		end
	end)
end

function equipAsAccessory(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		return
	end

	-- Resolve attachment slot from attributes (backward compat: default to head)
	local attrs = modelData.attributes or {}
	local slot = attrs.AttachTo or "head"
	local config = ATTACH_CONFIG[slot] or ATTACH_CONFIG.head

	local attachPart = character:FindFirstChild(config.bodyPart)
	if not attachPart then
		-- Fallback: try Head for any slot
		attachPart = character:FindFirstChild("Head")
		if not attachPart then return end
	end

	-- Remove previous origami accessory parts
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrigamiAccessory") or child:GetAttribute("OrigamiHat") then
			child:Destroy()
		end
	end
	_equippedAccessory = nil

	-- Scale down if too large for slot
	local maxSize = config.maxSize
	local _, modelSize = model:GetBoundingBox()
	local maxDim = math.max(modelSize.X, modelSize.Y, modelSize.Z)
	local scale = if maxDim > maxSize then maxSize / maxDim else 1

	local modelCenter = Vector3.zero
	if model.PrimaryPart then
		modelCenter = model.PrimaryPart.Position
	end

	-- Compute anchor point: body part CFrame + dynamic offset based on part size
	local anchorCF = attachPart.CFrame * config.offset(attachPart.Size)

	-- Collect parts before reparenting
	local partsToMove = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(partsToMove, part)
		end
	end

	-- Weld each part to the attach body part
	for _, part in ipairs(partsToMove) do
		if scale < 1 then
			part.Size = part.Size * scale
		end

		local offset = (part.Position - modelCenter) * scale
		local partRotation = part.CFrame - part.CFrame.Position

		part.Anchored = true
		part.CanCollide = false
		part.Massless = true
		part:SetAttribute("OrigamiAccessory", true)
		part.CFrame = anchorCF * CFrame.new(offset) * partRotation
		part.Parent = character

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attachPart
		weld.Part1 = part
		weld.Parent = part
	end

	-- Unanchor so parts follow via welds
	for _, part in ipairs(partsToMove) do
		if part.Parent then
			part.Anchored = false
		end
	end

	model:Destroy()
	_equippedAccessory = attachPart

	-- Wire up effects (read AccessoryEffect, fall back to HatEffect for old catalog items)
	local effect = attrs.AccessoryEffect or attrs.HatEffect
	if effect then
		local keyName = attrs.EffectKey or "Space"
		local keyCode = Enum.KeyCode[keyName] or Enum.KeyCode.Space

		if effect == "fly" then
			_wireFlyEffect(character, attachPart, attrs, keyCode)
		elseif effect == "speed" then
			_wireSpeedEffect(character, attrs)
		elseif effect == "glow" then
			_wireGlowEffect(character, keyCode)
		end
	end
end

function spawnVehicle(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Place vehicle in front of player
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE

	local _, lookY, _ = rootPart.CFrame:ToEulerAnglesYXZ()
	local modelName = modelData.name or "Vehicle"

	-- Get model bounds for collision plate sizing
	model.Parent = workspace
	local _, modelSize = model:GetBoundingBox()

	-- Raycast to find ground level at placement position
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, model }
	local rayResult = workspace:Raycast(
		Vector3.new(placementPos.X, rootPart.Position.Y + 10, placementPos.Z),
		Vector3.new(0, -50, 0),
		rayParams
	)
	local groundY = if rayResult then rayResult.Position.Y else (rootPart.Position.Y - 3)

	-- Seat sits 1 stud above ground (inside lower portion of car)
	placementPos = Vector3.new(placementPos.X, groundY + 1, placementPos.Z)

	-- Read LLM-driven physics attributes
	local attrs = modelData.attributes or {}
	local speed = attrs.Speed or 50
	local torque = attrs.Torque or 40
	local turnSpeed = attrs.TurnSpeed or 8
	local canFly = attrs.CanFly
	local flySpeed = attrs.FlySpeed or 30

	-- Create server-side VehicleSeat (Sit() requires server authority)
	local OrigamiService = Knit.GetService("OrigamiService")
	print("[Vehicle] Requesting server seat at", placementPos)
	local ok, seat =
		OrigamiService
			:CreateVehicleSeat(placementPos, lookY, modelName, { X = modelSize.X, Y = modelSize.Y, Z = modelSize.Z }, { Speed = speed, Torque = torque, TurnSpeed = turnSpeed })
			:await()

	if not ok or not seat then
		warn("[Vehicle] Failed to create server seat:", seat)
		table.insert(_spawnedModels, model)
		return
	end

	print("[Vehicle] Server seat received:", seat, "Position:", seat.Position)

	-- Position visual model so seat is in the lower portion (where a driver sits)
	-- Offset model upward: seat is 1 stud above ground, model bottom should be at ground
	local modelRise = modelSize.Y / 2 - 1
	model:PivotTo(seat.CFrame * CFrame.new(0, modelRise, 0))

	-- Weld all visual parts to the server seat — massless so they don't tip it
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seat
			weld.Part1 = part
			weld.Parent = part
		end
	end

	-- Add name label
	addNameLabel(model, modelName)

	-- Tell server to unanchor now that visual parts are welded
	print("[Vehicle] Calling ReadyVehicle to unanchor seat")
	OrigamiService:ReadyVehicle(seat):await()
	print("[Vehicle] Vehicle ready, seat anchored:", seat.Anchored)

	-- Add flight capability if LLM specified CanFly
	if canFly and seat then
		local bodyVel = Instance.new("BodyVelocity")
		bodyVel.MaxForce = Vector3.new(0, math.huge, 0)
		bodyVel.Velocity = Vector3.zero
		bodyVel.Parent = seat

		local flyConn
		flyConn = RunService.Heartbeat:Connect(function()
			if not seat or not seat.Parent then
				flyConn:Disconnect()
				return
			end
			local jumpPressed = UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsGamepadButtonPressed(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
			if seat.Occupant and jumpPressed then
				bodyVel.Velocity = Vector3.new(0, flySpeed, 0)
			else
				bodyVel.Velocity = Vector3.new(0, math.max(-20, seat.AssemblyLinearVelocity.Y - 1), 0)
			end
		end)
	end

	_activeVehicle = model
	_vehicleSeat = seat

	-- Track for clear
	table.insert(_spawnedModels, model)
end

function applyAvatar(model: Model, modelData: { [string]: any })
	-- Send model data to server to apply as avatar skin
	local OrigamiService = Knit.GetService("OrigamiService")
	local ok, result = OrigamiService:ApplyAvatar(modelData):await()

	-- Destroy the built model — server applies directly to character
	model:Destroy()

	if ok and result and result.success then
		_avatarApplied = true
		local modelName = modelData.name or "Avatar"
		setStatus("Transformed into: " .. modelName, COLORS.success)
	else
		setStatus("Failed to apply avatar", COLORS.error)
	end
end

function setStatus(text: string, color: Color3?)
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim

	-- Auto-clear after 5 seconds
	task.delay(5, function()
		if _statusLabel.Text == text then
			_statusLabel.Text = ""
		end
	end)
end

function spawnCreature(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	-- Place in front of player, on ground
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	model.Parent = workspace

	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
	model:PivotTo(CFrame.new(placementPos.X, rootPart.Position.Y + pivotAboveBottom, placementPos.Z))

	-- Add name label
	local modelName = modelData.name or "Creature"
	addNameLabel(model, modelName)
	table.insert(_spawnedModels, model)

	-- Start creature AI (shared module handles locomotion + animation)
	CreatureAI.Start(model, modelData, model:GetPivot().Position, { model, character })
end

function placeBuilding(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	-- Place in front of player
	local forward = rootPart.CFrame.LookVector
	local targetPos = rootPart.Position + forward * OrigamiConfig.PLACEMENT_DISTANCE

	-- Raycast down to find the ground
	local rayOrigin = Vector3.new(targetPos.X, rootPart.Position.Y + 50, targetPos.Z)
	local rayDir = Vector3.new(0, -200, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, model }

	local result = workspace:Raycast(rayOrigin, rayDir, params)
	local groundY = if result then result.Position.Y else rootPart.Position.Y - 3

	-- Position building flush on the ground
	model.Parent = workspace
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	-- How far the pivot sits above the bounding box bottom
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
	model:PivotTo(CFrame.new(targetPos.X, groundY + pivotAboveBottom, targetPos.Z))

	-- Add name label
	local modelName = modelData.name or "Building"
	addNameLabel(model, modelName)

	table.insert(_spawnedModels, model)
end

function placeModel(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	-- Place model in front of player
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	placementPos = Vector3.new(placementPos.X, rootPart.Position.Y, placementPos.Z)

	-- Position the model in front of player, on the ground
	model.Parent = workspace
	if model.PrimaryPart then
		local _, size = model:GetBoundingBox()
		local halfHeight = size.Y / 2
		model:PivotTo(CFrame.new(placementPos.X, placementPos.Y + halfHeight, placementPos.Z))
	end

	-- Add BillboardGui with name
	local modelName = modelData.name or "Creation"
	addNameLabel(model, modelName)

	-- Track for clear
	table.insert(_spawnedModels, model)
end

function addNameLabel(model: Model, name: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameLabel"
	billboard.Size = UDim2.new(0, 200, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 50

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if target then
		billboard.Adornee = target
		billboard.Parent = target
	end
end

local CATEGORY_ICONS = {
	creature = "C",
	avatar = "A",
	vehicle = "V",
	building = "B",
	tool = "T",
	accessory = "A",
	hat = "A",
	prop = "P",
}

function loadCatalog()
	if _catalogCache then
		renderCatalogItems(_catalogCache)
		return
	end

	-- Show loading state
	for _, child in ipairs(_catalogScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:FetchCatalog():await()

		if ok and result and result.success and result.items then
			_catalogCache = result.items
			renderCatalogItems(_catalogCache)
		else
			setStatus("Failed to load catalog", COLORS.error)
		end
	end)
end

function filterCatalog(searchText: string)
	if not _catalogCache then
		return
	end

	if not searchText or searchText == "" then
		renderCatalogItems(_catalogCache)
		return
	end

	local lower = searchText:lower()
	local filtered = {}
	for _, item in ipairs(_catalogCache) do
		if item.name and item.name:lower():find(lower, 1, true) then
			table.insert(filtered, item)
		end
	end
	renderCatalogItems(filtered)
end

function renderCatalogItems(items: { any })
	-- Clear existing entries
	for _, child in ipairs(_catalogScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for i, item in ipairs(items) do
		local entry = Instance.new("Frame")
		entry.Name = "CatItem_" .. i
		entry.Size = UDim2.new(1, 0, 0, 32)
		entry.BackgroundColor3 = COLORS.bgLight
		entry.BackgroundTransparency = 0.3
		entry.BorderSizePixel = 0
		entry.LayoutOrder = i
		entry.Parent = _catalogScroll

		local entryCorner = Instance.new("UICorner")
		entryCorner.CornerRadius = UDim.new(0, 6)
		entryCorner.Parent = entry

		-- Category icon
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 20, 1, 0)
		icon.Position = UDim2.new(0, 4, 0, 0)
		icon.BackgroundTransparency = 1
		icon.Text = CATEGORY_ICONS[item.category] or "?"
		icon.TextColor3 = COLORS.accent
		icon.TextSize = 12
		icon.Font = Enum.Font.GothamBold
		icon.Parent = entry

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "ItemName"
		nameLabel.Size = UDim2.new(1, -90, 1, 0)
		nameLabel.Position = UDim2.new(0, 26, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = item.name or "Unknown"
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextSize = 12
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = entry

		-- Spawn button with coin cost
		local spawnBtn = Instance.new("TextButton")
		spawnBtn.Name = "SpawnBtn"
		spawnBtn.Size = UDim2.new(0, 56, 0, 24)
		spawnBtn.Position = UDim2.new(1, -60, 0.5, -12)
		spawnBtn.BackgroundColor3 = COLORS.folds
		spawnBtn.BorderSizePixel = 0
		spawnBtn.Text = tostring(OrigamiConfig.CACHED_ITEM_COST) .. " F"
		spawnBtn.TextColor3 = Color3.fromRGB(30, 30, 30)
		spawnBtn.TextSize = 11
		spawnBtn.Font = Enum.Font.GothamBold
		spawnBtn.AutoButtonColor = true
		spawnBtn.Parent = entry

		local spawnCorner = Instance.new("UICorner")
		spawnCorner.CornerRadius = UDim.new(0, 6)
		spawnCorner.Parent = spawnBtn

		spawnBtn.Activated:Connect(function()
			spawnCatalogItem(item)
		end)
	end
end

function spawnCatalogItem(item: { [string]: any })
	-- Deduct coins (skip in Studio)
	if not RunService:IsStudio() then
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local ok, result = PlayerDataService:DeductCurrency("Folds", OrigamiConfig.CACHED_ITEM_COST):await()
		if not ok or not result or not result.success then
			setStatus("Not enough Folds!", COLORS.error)
			return
		end
		_foldsCount = result.remaining
		updateCurrencyDisplay()
	end

	-- Fetch full model data from server
	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:FetchCatalogItem(item.id):await()

		if not ok or not result or not result.success or not result.item then
			setStatus("Failed to load item", COLORS.error)
			return
		end

		local modelData = result.item.result
		if not modelData then
			setStatus("Item data missing", COLORS.error)
			return
		end

		local cat = modelData.category or item.category or "prop"

		local buildOk, buildErr = pcall(function()
			local builtModel = OrigamiBuilder.BuildModel(modelData)

			if cat == "tool" then
				equipAsTool(builtModel, modelData)
			elseif cat == "accessory" or cat == "hat" then
				equipAsAccessory(builtModel, modelData)
			elseif cat == "vehicle" then
				spawnVehicle(builtModel, modelData)
			elseif cat == "avatar" then
				applyAvatar(builtModel, modelData)
			elseif cat == "building" then
				placeBuilding(builtModel, modelData)
			elseif cat == "creature" then
				spawnCreature(builtModel, modelData)
			else
				placeModel(builtModel, modelData)
			end

			if cat ~= "tool" and cat ~= "accessory" and cat ~= "hat" and cat ~= "vehicle" and cat ~= "avatar" and cat ~= "creature" then
				local animType = modelData.animation or "idle_bob"
				OrigamiBuilder.ApplyAnimation(builtModel, animType)
			end
		end)

		if buildOk then
			setStatus("Spawned: " .. (modelData.name or "Item"), COLORS.success)
			_successSound:Play()
		else
			warn("[CatalogSpawn] Build error:", buildErr)
			setStatus("Build error", COLORS.error)
			_failSound:Play()
		end
	end)
end

function CreatorController:KnitInit() end

function CreatorController:KnitStart()
	createUI()

	-- Fetch initial currency balances
	task.spawn(function()
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local ok, balances = PlayerDataService:GetCurrency():await()
		if ok and balances then
			_foldsCount = balances.Folds or 0
			_craneCount = balances.Cranes or 0
			updateCurrencyDisplay()
		end
	end)

	local OrigamiService = Knit.GetService("OrigamiService")
	OrigamiService.ModelGenerated:Connect(function(modelData) end)

	-- Hide creator UI when switching away from sandbox, show + clear when returning
	GameMode.Changed:Connect(function(newMode, oldMode)
		if newMode == "sandbox" then
			_gui.Enabled = true
			clearAllCreations()
		else
			clearAllCreations()
			_gui.Enabled = false
		end
	end)
end

return CreatorController
