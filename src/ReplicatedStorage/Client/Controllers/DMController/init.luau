local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local Player = Players.LocalPlayer

-- Sound effects (reuse built-in engine sounds)
local _successSound = Instance.new("Sound")
_successSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
_successSound.Volume = 0.5
_successSound.Parent = SoundService

local _failSound = Instance.new("Sound")
_failSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
_failSound.Volume = 0.4
_failSound.Parent = SoundService

local DMController = Knit.CreateController({
	Name = "DMController",
})

local _trove = Trove.new()
local _gui: ScreenGui
local _visible = false

-- Scene builder
local _sceneInput: TextBox
local _sceneButton: TextButton
local _clearSceneButton: TextButton

-- Individual item builder
local _itemInput: TextBox
local _itemCategoryButtons: { [string]: TextButton } = {}
local _selectedItemCategory = "creature"
local _addItemButton: TextButton

-- Style + model selectors
local _styleButtons: { [string]: TextButton } = {}
local _modelButtons: { [string]: TextButton } = {}
local _selectedStyle = "origami"
local _selectedModel = "sonnet"

-- Item list
local _itemListFrame: ScrollingFrame
local _itemEntries: { [number]: Frame } = {}

-- Progress
local _progressLabel: TextLabel

-- Status
local _statusLabel: TextLabel

-- Colors (same palette as CreatorController)
local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(180, 100, 255), -- purple accent for DM mode
	accentDim = Color3.fromRGB(120, 60, 180),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	disabled = Color3.fromRGB(80, 80, 90),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	danger = Color3.fromRGB(200, 60, 60),
	enemy = Color3.fromRGB(255, 80, 80),
}

-- DM-relevant categories (subset of all categories)
local DM_CATEGORIES = {
	{ key = "creature", display = "Creature" },
	{ key = "building", display = "Building" },
	{ key = "prop", display = "Prop" },
	{ key = "vehicle", display = "Vehicle" },
}

-----------------------------------------------------------
-- UI helpers
-----------------------------------------------------------

local function setStatus(text: string, color: Color3?)
	if not _statusLabel then
		return
	end
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim

	task.delay(5, function()
		if _statusLabel and _statusLabel.Text == text then
			_statusLabel.Text = ""
		end
	end)
end

local function setProgress(text: string)
	if _progressLabel then
		_progressLabel.Text = text
	end
end

local function getPlacementPosition(): Vector3
	local character = Player.Character
	if not character then
		return Vector3.new(0, 5, 0)
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return Vector3.new(0, 5, 0)
	end

	-- Place in front of player
	local forward = rootPart.CFrame.LookVector
	local pos = rootPart.Position + forward * OrigamiConfig.PLACEMENT_DISTANCE
	return Vector3.new(pos.X, rootPart.Position.Y, pos.Z)
end

-----------------------------------------------------------
-- Actions
-----------------------------------------------------------

local function refreshItemList()
	-- Clear existing entries
	for id, frame in pairs(_itemEntries) do
		frame:Destroy()
		_itemEntries[id] = nil
	end

	local DMService = Knit.GetService("DMService")
	task.spawn(function()
		local ok, result = DMService:GetSceneItems():await()
		if not ok or not result or not result.success then
			return
		end

		for _, item in ipairs(result.items) do
			local entry = Instance.new("Frame")
			entry.Name = "Item_" .. item.id
			entry.Size = UDim2.new(1, 0, 0, 28)
			entry.BackgroundColor3 = COLORS.bgLight
			entry.BackgroundTransparency = 0.3
			entry.BorderSizePixel = 0
			entry.LayoutOrder = item.id
			entry.Parent = _itemListFrame

			local entryCorner = Instance.new("UICorner")
			entryCorner.CornerRadius = UDim.new(0, 4)
			entryCorner.Parent = entry

			-- Remove button
			local removeBtn = Instance.new("TextButton")
			removeBtn.Name = "RemoveBtn"
			removeBtn.Size = UDim2.new(0, 22, 0, 22)
			removeBtn.Position = UDim2.new(0, 3, 0.5, -11)
			removeBtn.BackgroundColor3 = COLORS.danger
			removeBtn.BorderSizePixel = 0
			removeBtn.Text = "X"
			removeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			removeBtn.TextSize = 10
			removeBtn.Font = Enum.Font.GothamBold
			removeBtn.AutoButtonColor = true
			removeBtn.Parent = entry

			local removeBtnCorner = Instance.new("UICorner")
			removeBtnCorner.CornerRadius = UDim.new(0, 4)
			removeBtnCorner.Parent = removeBtn

			-- Item label
			local displayName = (item.name or "Unknown"):sub(1, 20)
			local categoryTag = item.category or "?"
			local enemyTag = if item.enemy then " [Enemy]" else ""

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.new(1, -32, 1, 0)
			label.Position = UDim2.new(0, 30, 0, 0)
			label.BackgroundTransparency = 1
			label.Text = displayName .. "  (" .. categoryTag .. ")" .. enemyTag
			label.TextColor3 = if item.enemy then COLORS.enemy else COLORS.text
			label.TextSize = 11
			label.Font = Enum.Font.Gotham
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Parent = entry

			-- Wire remove button
			local itemId = item.id
			removeBtn.Activated:Connect(function()
				task.spawn(function()
					local rmOk, rmResult = DMService:RemoveFromScene(itemId):await()
					if rmOk and rmResult and rmResult.success then
						setStatus("Removed: " .. displayName, COLORS.textDim)
						_successSound:Play()
					else
						setStatus("Failed to remove item", COLORS.error)
						_failSound:Play()
					end
					refreshItemList()
				end)
			end)

			_itemEntries[item.id] = entry
		end
	end)
end

local function addItem()
	local prompt = _itemInput.Text
	if not prompt or prompt:match("^%s*$") then
		setStatus("Type a description first!", COLORS.error)
		return
	end

	_itemInput.Text = ""
	local category = _selectedItemCategory
	local style = _selectedStyle
	local aiModel = _selectedModel
	local position = getPlacementPosition()

	setProgress("Generating " .. category .. "...")
	_addItemButton.BackgroundColor3 = COLORS.disabled

	task.spawn(function()
		local DMService = Knit.GetService("DMService")
		local ok, result = DMService:AddToScene(prompt, category, style, aiModel, position, 0):await()

		_addItemButton.BackgroundColor3 = COLORS.accent

		if ok and result and result.success then
			local itemName = result.name or "Item"
			setStatus("Added: " .. itemName, COLORS.success)
			setProgress("")
			_successSound:Play()
			refreshItemList()
		else
			local errMsg = (ok and result and result.error) or (not ok and tostring(result)) or "Unknown error"
			setStatus("Failed: " .. tostring(errMsg):sub(1, 40), COLORS.error)
			setProgress("")
			_failSound:Play()
		end
	end)
end

local function buildScene()
	local prompt = _sceneInput.Text
	if not prompt or prompt:match("^%s*$") then
		setStatus("Describe a scene first!", COLORS.error)
		return
	end

	_sceneInput.Text = ""
	local style = _selectedStyle
	local aiModel = _selectedModel
	local anchorPos = getPlacementPosition()

	setProgress("Planning scene...")
	_sceneButton.BackgroundColor3 = COLORS.disabled

	task.spawn(function()
		local DMService = Knit.GetService("DMService")
		local ok, result = DMService:RequestScene(prompt, style, aiModel, anchorPos):await()

		_sceneButton.BackgroundColor3 = COLORS.accent

		if ok and result and result.success then
			local builtInfo = (result.builtCount or 0) .. "/" .. (result.totalPlanned or 0)
			setStatus(
				"Scene built: " .. (result.sceneName or "Scene") .. " (" .. builtInfo .. " items)",
				COLORS.success
			)
			setProgress("")
			_successSound:Play()
			refreshItemList()
		else
			local errMsg = (ok and result and result.error) or (not ok and tostring(result)) or "Unknown error"
			setStatus("Scene failed: " .. tostring(errMsg):sub(1, 40), COLORS.error)
			setProgress("")
			_failSound:Play()
		end
	end)
end

local function clearScene()
	setProgress("Clearing scene...")

	task.spawn(function()
		local DMService = Knit.GetService("DMService")
		local ok, result = DMService:ClearScene():await()

		if ok and result and result.success then
			setStatus("Scene cleared", COLORS.textDim)
			setProgress("")
			_successSound:Play()
			refreshItemList()
		else
			setStatus("Failed to clear scene", COLORS.error)
			setProgress("")
		end
	end)
end

-----------------------------------------------------------
-- Style / Model / Category highlight helpers
-----------------------------------------------------------

local function updateStyleHighlights()
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

local function updateModelHighlights()
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

local function updateCategoryHighlights()
	for key, btn in pairs(_itemCategoryButtons) do
		if key == _selectedItemCategory then
			btn.BackgroundColor3 = COLORS.accent
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
end

-----------------------------------------------------------
-- UI construction
-----------------------------------------------------------

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "DMPanel"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 6
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Main container (left side panel)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 320, 0, 520)
	container.Position = UDim2.new(0, 10, 0.5, -260)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	local yPos = 8

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 24)
	title.Position = UDim2.new(0, 8, 0, yPos)
	title.BackgroundTransparency = 1
	title.Text = "DM Mode"
	title.TextColor3 = COLORS.accent
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = container

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 24, 0, 24)
	closeBtn.Position = UDim2.new(1, -32, 0, yPos)
	closeBtn.BackgroundColor3 = COLORS.bgLight
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.textDim
	closeBtn.TextSize = 12
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = container

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		DMController:Hide()
	end)
	yPos += 30

	-- Style selector row (scrollable)
	local styleClip = Instance.new("Frame")
	styleClip.Name = "StyleClip"
	styleClip.Size = UDim2.new(1, -16, 0, 24)
	styleClip.Position = UDim2.new(0, 8, 0, yPos)
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
	styleRow.CanvasSize = UDim2.new(0, 0, 0, 24)
	styleRow.Parent = styleClip

	local styleLayout = Instance.new("UIListLayout")
	styleLayout.FillDirection = Enum.FillDirection.Horizontal
	styleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	styleLayout.Padding = UDim.new(0, 3)
	styleLayout.Parent = styleRow

	for _, sty in ipairs(OrigamiConfig.STYLES) do
		local btn = Instance.new("TextButton")
		btn.Name = "Style_" .. sty.key
		btn.Size = UDim2.new(0, 60, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = sty.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 10
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = styleRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		_styleButtons[sty.key] = btn

		btn.Activated:Connect(function()
			_selectedStyle = sty.key
			updateStyleHighlights()
		end)
	end
	yPos += 28

	-- Model selector row
	local modelRow = Instance.new("Frame")
	modelRow.Name = "ModelRow"
	modelRow.Size = UDim2.new(1, -16, 0, 24)
	modelRow.Position = UDim2.new(0, 8, 0, yPos)
	modelRow.BackgroundTransparency = 1
	modelRow.Parent = container

	local modelLayout = Instance.new("UIListLayout")
	modelLayout.FillDirection = Enum.FillDirection.Horizontal
	modelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	modelLayout.Padding = UDim.new(0, 3)
	modelLayout.Parent = modelRow

	local modelLabel = Instance.new("TextLabel")
	modelLabel.Name = "ModelLabel"
	modelLabel.Size = UDim2.new(0, 40, 1, 0)
	modelLabel.BackgroundTransparency = 1
	modelLabel.Text = "Model:"
	modelLabel.TextColor3 = COLORS.textDim
	modelLabel.TextSize = 10
	modelLabel.Font = Enum.Font.GothamBold
	modelLabel.TextXAlignment = Enum.TextXAlignment.Left
	modelLabel.Parent = modelRow

	for _, mdl in ipairs(OrigamiConfig.MODELS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Model_" .. mdl.key
		btn.Size = UDim2.new(0, 54, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = mdl.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 10
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = modelRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		_modelButtons[mdl.key] = btn

		btn.Activated:Connect(function()
			_selectedModel = mdl.key
			updateModelHighlights()
		end)
	end
	yPos += 30

	-- Separator
	local sep1 = Instance.new("Frame")
	sep1.Name = "Sep1"
	sep1.Size = UDim2.new(1, -16, 0, 1)
	sep1.Position = UDim2.new(0, 8, 0, yPos)
	sep1.BackgroundColor3 = COLORS.bgLight
	sep1.BorderSizePixel = 0
	sep1.Parent = container
	yPos += 6

	-- === Scene Builder Section ===
	local sceneLabel = Instance.new("TextLabel")
	sceneLabel.Name = "SceneLabel"
	sceneLabel.Size = UDim2.new(1, -16, 0, 18)
	sceneLabel.Position = UDim2.new(0, 8, 0, yPos)
	sceneLabel.BackgroundTransparency = 1
	sceneLabel.Text = "Scene Description:"
	sceneLabel.TextColor3 = COLORS.textDim
	sceneLabel.TextSize = 11
	sceneLabel.Font = Enum.Font.GothamBold
	sceneLabel.TextXAlignment = Enum.TextXAlignment.Left
	sceneLabel.Parent = container
	yPos += 20

	_sceneInput = Instance.new("TextBox")
	_sceneInput.Name = "SceneInput"
	_sceneInput.Size = UDim2.new(1, -16, 0, 36)
	_sceneInput.Position = UDim2.new(0, 8, 0, yPos)
	_sceneInput.BackgroundColor3 = COLORS.bgLight
	_sceneInput.BorderSizePixel = 0
	_sceneInput.PlaceholderText = "A haunted forest with skeleton guards..."
	_sceneInput.PlaceholderColor3 = COLORS.textDim
	_sceneInput.Text = ""
	_sceneInput.TextColor3 = COLORS.text
	_sceneInput.TextSize = 12
	_sceneInput.Font = Enum.Font.Gotham
	_sceneInput.ClearTextOnFocus = false
	_sceneInput.TextWrapped = true
	_sceneInput.Parent = container

	local sceneInputCorner = Instance.new("UICorner")
	sceneInputCorner.CornerRadius = UDim.new(0, 6)
	sceneInputCorner.Parent = _sceneInput

	local sceneInputPadding = Instance.new("UIPadding")
	sceneInputPadding.PaddingLeft = UDim.new(0, 8)
	sceneInputPadding.PaddingRight = UDim.new(0, 8)
	sceneInputPadding.Parent = _sceneInput
	yPos += 40

	-- Scene buttons row
	local sceneButtonRow = Instance.new("Frame")
	sceneButtonRow.Name = "SceneButtonRow"
	sceneButtonRow.Size = UDim2.new(1, -16, 0, 28)
	sceneButtonRow.Position = UDim2.new(0, 8, 0, yPos)
	sceneButtonRow.BackgroundTransparency = 1
	sceneButtonRow.Parent = container

	_sceneButton = Instance.new("TextButton")
	_sceneButton.Name = "BuildSceneBtn"
	_sceneButton.Size = UDim2.new(0.5, -2, 1, 0)
	_sceneButton.Position = UDim2.new(0, 0, 0, 0)
	_sceneButton.BackgroundColor3 = COLORS.accent
	_sceneButton.BorderSizePixel = 0
	_sceneButton.Text = "Build Scene"
	_sceneButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_sceneButton.TextSize = 13
	_sceneButton.Font = Enum.Font.GothamBold
	_sceneButton.AutoButtonColor = true
	_sceneButton.Parent = sceneButtonRow

	local sceneBtnCorner = Instance.new("UICorner")
	sceneBtnCorner.CornerRadius = UDim.new(0, 6)
	sceneBtnCorner.Parent = _sceneButton

	_clearSceneButton = Instance.new("TextButton")
	_clearSceneButton.Name = "ClearSceneBtn"
	_clearSceneButton.Size = UDim2.new(0.5, -2, 1, 0)
	_clearSceneButton.Position = UDim2.new(0.5, 2, 0, 0)
	_clearSceneButton.BackgroundColor3 = COLORS.danger
	_clearSceneButton.BorderSizePixel = 0
	_clearSceneButton.Text = "Clear Scene"
	_clearSceneButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_clearSceneButton.TextSize = 13
	_clearSceneButton.Font = Enum.Font.GothamBold
	_clearSceneButton.AutoButtonColor = true
	_clearSceneButton.Parent = sceneButtonRow

	local clearBtnCorner = Instance.new("UICorner")
	clearBtnCorner.CornerRadius = UDim.new(0, 6)
	clearBtnCorner.Parent = _clearSceneButton
	yPos += 34

	-- Separator
	local sep2 = Instance.new("Frame")
	sep2.Name = "Sep2"
	sep2.Size = UDim2.new(1, -16, 0, 1)
	sep2.Position = UDim2.new(0, 8, 0, yPos)
	sep2.BackgroundColor3 = COLORS.bgLight
	sep2.BorderSizePixel = 0
	sep2.Parent = container
	yPos += 6

	-- === Add Item Section ===
	local addLabel = Instance.new("TextLabel")
	addLabel.Name = "AddItemLabel"
	addLabel.Size = UDim2.new(1, -16, 0, 18)
	addLabel.Position = UDim2.new(0, 8, 0, yPos)
	addLabel.BackgroundTransparency = 1
	addLabel.Text = "Add Item:"
	addLabel.TextColor3 = COLORS.textDim
	addLabel.TextSize = 11
	addLabel.Font = Enum.Font.GothamBold
	addLabel.TextXAlignment = Enum.TextXAlignment.Left
	addLabel.Parent = container
	yPos += 20

	-- Category buttons for item builder
	local itemCatRow = Instance.new("Frame")
	itemCatRow.Name = "ItemCategoryRow"
	itemCatRow.Size = UDim2.new(1, -16, 0, 24)
	itemCatRow.Position = UDim2.new(0, 8, 0, yPos)
	itemCatRow.BackgroundTransparency = 1
	itemCatRow.Parent = container

	local itemCatLayout = Instance.new("UIListLayout")
	itemCatLayout.FillDirection = Enum.FillDirection.Horizontal
	itemCatLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	itemCatLayout.Padding = UDim.new(0, 3)
	itemCatLayout.Parent = itemCatRow

	for _, cat in ipairs(DM_CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Name = "ItemCat_" .. cat.key
		btn.Size = UDim2.new(0, 68, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = cat.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 10
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = itemCatRow

		local catCorner = Instance.new("UICorner")
		catCorner.CornerRadius = UDim.new(0, 5)
		catCorner.Parent = btn

		_itemCategoryButtons[cat.key] = btn

		btn.Activated:Connect(function()
			_selectedItemCategory = cat.key
			updateCategoryHighlights()
		end)
	end
	yPos += 28

	-- Item input + add button row
	local itemInputRow = Instance.new("Frame")
	itemInputRow.Name = "ItemInputRow"
	itemInputRow.Size = UDim2.new(1, -16, 0, 30)
	itemInputRow.Position = UDim2.new(0, 8, 0, yPos)
	itemInputRow.BackgroundTransparency = 1
	itemInputRow.Parent = container

	_itemInput = Instance.new("TextBox")
	_itemInput.Name = "ItemInput"
	_itemInput.Size = UDim2.new(1, -70, 1, 0)
	_itemInput.Position = UDim2.new(0, 0, 0, 0)
	_itemInput.BackgroundColor3 = COLORS.bgLight
	_itemInput.BorderSizePixel = 0
	_itemInput.PlaceholderText = "A skeleton warrior..."
	_itemInput.PlaceholderColor3 = COLORS.textDim
	_itemInput.Text = ""
	_itemInput.TextColor3 = COLORS.text
	_itemInput.TextSize = 12
	_itemInput.Font = Enum.Font.Gotham
	_itemInput.ClearTextOnFocus = false
	_itemInput.Parent = itemInputRow

	local itemInputCorner = Instance.new("UICorner")
	itemInputCorner.CornerRadius = UDim.new(0, 6)
	itemInputCorner.Parent = _itemInput

	local itemInputPadding = Instance.new("UIPadding")
	itemInputPadding.PaddingLeft = UDim.new(0, 8)
	itemInputPadding.PaddingRight = UDim.new(0, 8)
	itemInputPadding.Parent = _itemInput

	_addItemButton = Instance.new("TextButton")
	_addItemButton.Name = "AddItemBtn"
	_addItemButton.Size = UDim2.new(0, 64, 1, 0)
	_addItemButton.Position = UDim2.new(1, -64, 0, 0)
	_addItemButton.BackgroundColor3 = COLORS.accent
	_addItemButton.BorderSizePixel = 0
	_addItemButton.Text = "Add"
	_addItemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_addItemButton.TextSize = 13
	_addItemButton.Font = Enum.Font.GothamBold
	_addItemButton.AutoButtonColor = true
	_addItemButton.Parent = itemInputRow

	local addBtnCorner = Instance.new("UICorner")
	addBtnCorner.CornerRadius = UDim.new(0, 6)
	addBtnCorner.Parent = _addItemButton
	yPos += 36

	-- Separator
	local sep3 = Instance.new("Frame")
	sep3.Name = "Sep3"
	sep3.Size = UDim2.new(1, -16, 0, 1)
	sep3.Position = UDim2.new(0, 8, 0, yPos)
	sep3.BackgroundColor3 = COLORS.bgLight
	sep3.BorderSizePixel = 0
	sep3.Parent = container
	yPos += 6

	-- === Scene Items List ===
	local itemsLabel = Instance.new("TextLabel")
	itemsLabel.Name = "ItemsLabel"
	itemsLabel.Size = UDim2.new(1, -16, 0, 18)
	itemsLabel.Position = UDim2.new(0, 8, 0, yPos)
	itemsLabel.BackgroundTransparency = 1
	itemsLabel.Text = "Scene Items:"
	itemsLabel.TextColor3 = COLORS.textDim
	itemsLabel.TextSize = 11
	itemsLabel.Font = Enum.Font.GothamBold
	itemsLabel.TextXAlignment = Enum.TextXAlignment.Left
	itemsLabel.Parent = container
	yPos += 20

	_itemListFrame = Instance.new("ScrollingFrame")
	_itemListFrame.Name = "ItemList"
	_itemListFrame.Size = UDim2.new(1, -16, 0, 120)
	_itemListFrame.Position = UDim2.new(0, 8, 0, yPos)
	_itemListFrame.BackgroundColor3 = COLORS.bgLight
	_itemListFrame.BackgroundTransparency = 0.5
	_itemListFrame.BorderSizePixel = 0
	_itemListFrame.ScrollBarThickness = 4
	_itemListFrame.ScrollBarImageColor3 = COLORS.accentDim
	_itemListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	_itemListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	_itemListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	_itemListFrame.Parent = container

	local itemListCorner = Instance.new("UICorner")
	itemListCorner.CornerRadius = UDim.new(0, 6)
	itemListCorner.Parent = _itemListFrame

	local itemListLayout = Instance.new("UIListLayout")
	itemListLayout.FillDirection = Enum.FillDirection.Vertical
	itemListLayout.Padding = UDim.new(0, 3)
	itemListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemListLayout.Parent = _itemListFrame

	local itemListPadding = Instance.new("UIPadding")
	itemListPadding.PaddingTop = UDim.new(0, 4)
	itemListPadding.PaddingBottom = UDim.new(0, 4)
	itemListPadding.PaddingLeft = UDim.new(0, 4)
	itemListPadding.PaddingRight = UDim.new(0, 4)
	itemListPadding.Parent = _itemListFrame
	yPos += 126

	-- Progress label
	_progressLabel = Instance.new("TextLabel")
	_progressLabel.Name = "ProgressLabel"
	_progressLabel.Size = UDim2.new(1, -16, 0, 16)
	_progressLabel.Position = UDim2.new(0, 8, 0, yPos)
	_progressLabel.BackgroundTransparency = 1
	_progressLabel.Text = ""
	_progressLabel.TextColor3 = COLORS.accent
	_progressLabel.TextSize = 11
	_progressLabel.Font = Enum.Font.GothamBold
	_progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	_progressLabel.Parent = container
	yPos += 18

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "StatusLabel"
	_statusLabel.Size = UDim2.new(1, -16, 0, 16)
	_statusLabel.Position = UDim2.new(0, 8, 0, yPos)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.TextSize = 11
	_statusLabel.Font = Enum.Font.Gotham
	_statusLabel.Parent = container

	-- Wire up events
	_sceneButton.Activated:Connect(buildScene)
	_clearSceneButton.Activated:Connect(clearScene)
	_addItemButton.Activated:Connect(addItem)

	_itemInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			addItem()
		end
	end)

	_sceneInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			buildScene()
		end
	end)

	-- Start hidden
	_gui.Enabled = false
	_gui.Parent = Player.PlayerGui

	updateStyleHighlights()
	updateModelHighlights()
	updateCategoryHighlights()
end

-----------------------------------------------------------
-- Public API (called by CreatorController toggle)
-----------------------------------------------------------

function DMController:Toggle()
	_visible = not _visible
	if _gui then
		_gui.Enabled = _visible
		if _visible then
			refreshItemList()
		end
	end
end

function DMController:IsVisible(): boolean
	return _visible
end

function DMController:Show()
	_visible = true
	if _gui then
		_gui.Enabled = true
		refreshItemList()
	end
end

function DMController:Hide()
	_visible = false
	if _gui then
		_gui.Enabled = false
	end
end

-----------------------------------------------------------
-- Lifecycle
-----------------------------------------------------------

function DMController:KnitInit() end

function DMController:KnitStart()
	createUI()

	-- Listen for scene progress signals
	local DMService = Knit.GetService("DMService")
	DMService.SceneProgress:Connect(function(step, total, itemName)
		setProgress("Building " .. (itemName or "item") .. " (" .. step .. "/" .. total .. ")...")
	end)
end

return DMController
