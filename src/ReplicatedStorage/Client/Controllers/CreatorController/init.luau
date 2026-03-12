local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local Player = Players.LocalPlayer

local CreatorController = Knit.CreateController({
	Name = "CreatorController",
})

local _trove = Trove.new()
local _selectedCategory = "creature"
local _cooldownActive = false
local _gui: ScreenGui
local _inputBox: TextBox
local _statusLabel: TextLabel
local _createButton: TextButton
local _categoryButtons: { [string]: TextButton } = {}

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
}

local function createUI()
	-- Main ScreenGui
	_gui = Instance.new("ScreenGui")
	_gui.Name = "OrigamiCreator"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 5
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Container at bottom of screen
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0.6, 0, 0, 120)
	container.Position = UDim2.new(0.2, 0, 1, -130)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	-- Category buttons row
	local categoryRow = Instance.new("Frame")
	categoryRow.Name = "CategoryRow"
	categoryRow.Size = UDim2.new(1, -20, 0, 32)
	categoryRow.Position = UDim2.new(0, 10, 0, 10)
	categoryRow.BackgroundTransparency = 1
	categoryRow.Parent = container

	local categoryLayout = Instance.new("UIListLayout")
	categoryLayout.FillDirection = Enum.FillDirection.Horizontal
	categoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	categoryLayout.Padding = UDim.new(0, 6)
	categoryLayout.Parent = categoryRow

	for _, cat in ipairs(OrigamiConfig.CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Name = "Cat_" .. cat.key
		btn.Size = UDim2.new(0, 80, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = cat.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 13
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = categoryRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_categoryButtons[cat.key] = btn

		btn.MouseButton1Click:Connect(function()
			_selectedCategory = cat.key
			updateCategoryHighlights()
		end)
	end

	-- Input row
	local inputRow = Instance.new("Frame")
	inputRow.Name = "InputRow"
	inputRow.Size = UDim2.new(1, -20, 0, 40)
	inputRow.Position = UDim2.new(0, 10, 0, 52)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = container

	-- Text input box
	_inputBox = Instance.new("TextBox")
	_inputBox.Name = "PromptInput"
	_inputBox.Size = UDim2.new(1, -100, 1, 0)
	_inputBox.Position = UDim2.new(0, 0, 0, 0)
	_inputBox.BackgroundColor3 = COLORS.bgLight
	_inputBox.BorderSizePixel = 0
	_inputBox.PlaceholderText = "Type anything..."
	_inputBox.PlaceholderColor3 = COLORS.textDim
	_inputBox.Text = ""
	_inputBox.TextColor3 = COLORS.text
	_inputBox.TextSize = 16
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
	_createButton.Size = UDim2.new(0, 88, 1, 0)
	_createButton.Position = UDim2.new(1, -88, 0, 0)
	_createButton.BackgroundColor3 = COLORS.accent
	_createButton.BorderSizePixel = 0
	_createButton.Text = "Create"
	_createButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_createButton.TextSize = 16
	_createButton.Font = Enum.Font.GothamBold
	_createButton.AutoButtonColor = true
	_createButton.Parent = inputRow

	local createCorner = Instance.new("UICorner")
	createCorner.CornerRadius = UDim.new(0, 8)
	createCorner.Parent = _createButton

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "StatusLabel"
	_statusLabel.Size = UDim2.new(1, -20, 0, 20)
	_statusLabel.Position = UDim2.new(0, 10, 0, 96)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.TextSize = 12
	_statusLabel.Font = Enum.Font.Gotham
	_statusLabel.Parent = container

	-- Wire up submit
	_createButton.MouseButton1Click:Connect(function()
		submitPrompt()
	end)

	_inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitPrompt()
		end
	end)

	_gui.Parent = Player.PlayerGui

	updateCategoryHighlights()
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

function submitPrompt()
	if _cooldownActive then
		return
	end

	local prompt = _inputBox.Text
	if not prompt or prompt:match("^%s*$") then
		setStatus("Type something first!", COLORS.error)
		return
	end

	-- Start cooldown and show folding status
	_cooldownActive = true
	_createButton.BackgroundColor3 = COLORS.disabled
	_createButton.Text = "..."
	_inputBox.TextEditable = false
	setStatus("Folding...", COLORS.accent)

	-- Call server
	local OrigamiService = Knit.GetService("OrigamiService")
	local result = OrigamiService:RequestModel(prompt, _selectedCategory):await()

	if result and result.success and result.model then
		-- Build and place model
		local modelData = result.model
		local model = OrigamiBuilder.BuildModel(modelData)
		placeModel(model, modelData)

		-- Show success
		local modelName = modelData.name or "Creation"
		local description = modelData.description or ""
		setStatus(modelName .. (description ~= "" and (" - " .. description) or ""), COLORS.success)

		-- Apply animation if specified
		local animType = modelData.animation or "idle_bob"
		OrigamiBuilder.ApplyAnimation(model, animType)

		-- Clear input
		_inputBox.Text = ""
	else
		local errMsg = result and result.error or "Unknown error"
		if errMsg == "cooldown" then
			local cd = result.cooldown or OrigamiConfig.COOLDOWN_SECONDS
			setStatus("Wait " .. cd .. "s before creating again", COLORS.error)
		elseif errMsg == "api_not_configured" then
			setStatus("API not configured yet", COLORS.error)
		else
			setStatus("Failed: " .. errMsg, COLORS.error)
		end
	end

	-- Cooldown timer
	startCooldown()
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

function startCooldown()
	local remaining = OrigamiConfig.COOLDOWN_SECONDS
	_createButton.Text = tostring(remaining)

	task.spawn(function()
		while remaining > 0 do
			task.wait(1)
			remaining -= 1
			if remaining > 0 then
				_createButton.Text = tostring(remaining)
			end
		end
		_cooldownActive = false
		_createButton.BackgroundColor3 = COLORS.accent
		_createButton.Text = "Create"
		_inputBox.TextEditable = true
	end)
end

function placeModel(model: Model, modelData: { [string]: any })
	-- Get player character position and look direction
	local character = Player.Character
	if not character then
		model.Parent = workspace
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		return
	end

	-- Place model in front of player
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	-- Ensure it's above ground
	placementPos = Vector3.new(placementPos.X, rootPart.Position.Y, placementPos.Z)

	-- Create a small pedestal
	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Size = Vector3.new(6, 0.5, 6)
	pedestal.Position = placementPos - Vector3.new(0, 0.25, 0)
	pedestal.Anchored = true
	pedestal.CanCollide = true
	pedestal.Material = Enum.Material.SmoothPlastic
	pedestal.Color = Color3.fromRGB(60, 60, 70)
	pedestal.Parent = model

	local pedestalCorner = Instance.new("UICorner")
	-- Can't use UICorner on Part, skip

	-- Position the model on the pedestal
	model.Parent = workspace
	if model.PrimaryPart then
		model:PivotTo(CFrame.new(placementPos + Vector3.new(0, 2, 0)))
	end

	-- Add BillboardGui with name
	local modelName = modelData.name or "Creation"
	addNameLabel(model, modelName)
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

	-- Parent to primary part or first part
	local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if target then
		billboard.Adornee = target
		billboard.Parent = target
	end
end

function CreatorController:KnitInit()
	-- Nothing needed in init
end

function CreatorController:KnitStart()
	createUI()

	-- Listen for server-pushed model events
	local OrigamiService = Knit.GetService("OrigamiService")
	OrigamiService.ModelGenerated:Connect(function(modelData)
		-- Handle models generated by other triggers if needed
	end)
end

return CreatorController
