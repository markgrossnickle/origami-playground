--[[
	CreatureController — creature collection UI.
	Grid of creature cards with ViewportFrame thumbnails, detail panel,
	rename, spawn in world, release.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local EggCraftingConfig = require(ReplicatedStorage.Shared.EggCraftingConfig)
local VFXUtil = require(ReplicatedStorage.Shared.VFXUtil)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local COLORS = {
	bg = Color3.fromRGB(25, 25, 35),
	panel = Color3.fromRGB(35, 35, 50),
	card = Color3.fromRGB(45, 45, 65),
	cardSelected = Color3.fromRGB(60, 60, 90),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	accent = Color3.fromRGB(100, 180, 255),
	danger = Color3.fromRGB(200, 60, 60),
}

-- State
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _detailFrame: Frame? = nil
local _visible = false
local _creatures = {}
local _selectedId: string? = nil
local _activeCreatureModel: Model? = nil
local _activeCreatureCleanup: (() -> ())? = nil

local function createCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function createViewportThumbnail(modelData: { [string]: any }, parent: GuiObject): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.LightColor = Color3.fromRGB(200, 200, 220)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Ambient = Color3.fromRGB(120, 120, 140)
	viewport.Parent = parent

	task.spawn(function()
		local model = OrigamiBuilder.BuildModel(modelData)
		if model then
			model.Parent = viewport

			-- Fit model in viewport
			local cf, size = model:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z)
			local camDist = maxDim * 1.8

			local camera = Instance.new("Camera")
			camera.CFrame = CFrame.new(cf.Position + Vector3.new(camDist * 0.6, camDist * 0.4, camDist * 0.6), cf.Position)
			camera.Parent = viewport
			viewport.CurrentCamera = camera
		end
	end)

	return viewport
end

local function formatCooldown(seconds: number): string
	if seconds <= 0 then
		return "Ready"
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

local function despawnActiveCreature()
	if _activeCreatureCleanup then
		_activeCreatureCleanup()
		_activeCreatureCleanup = nil
	end
	if _activeCreatureModel and _activeCreatureModel.Parent then
		_activeCreatureModel:Destroy()
	end
	_activeCreatureModel = nil
end

local function spawnCreatureInWorld(creature: { [string]: any })
	despawnActiveCreature()

	local character = Player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not creature.modelData then
		return
	end

	local model = OrigamiBuilder.BuildModel(creature.modelData)
	if not model then
		return
	end

	model.Name = creature.name or "Creature"
	model:SetAttribute("OwnerUserId", Player.UserId)
	model:SetAttribute("CreatureId", creature.id)
	model.Parent = workspace

	local spawnPos = rootPart.Position + rootPart.CFrame.LookVector * 8
	model:PivotTo(CFrame.new(spawnPos.X, rootPart.Position.Y, spawnPos.Z))

	_activeCreatureModel = model
	_activeCreatureCleanup = CreatureAI.Start(model, creature.modelData, spawnPos, { model, character })

	local rarityColor = EggCraftingConfig.RARITY_COLORS[creature.rarity] or COLORS.success
	VFXUtil.sparkle(spawnPos + Vector3.new(0, 2, 0), rarityColor, 15, 1.5)
end

local function getSelectedCreature(): { [string]: any }?
	if not _selectedId then
		return nil
	end
	for _, c in ipairs(_creatures) do
		if c.id == _selectedId then
			return c
		end
	end
	return nil
end

local function updateDetailPanel()
	if not _detailFrame then
		return
	end

	local creature = getSelectedCreature()
	if not creature then
		_detailFrame.Visible = false
		return
	end

	_detailFrame.Visible = true
	local rarityColor = EggCraftingConfig.RARITY_COLORS[creature.rarity] or COLORS.text

	-- Update labels
	local nameLabel = _detailFrame:FindFirstChild("NameLabel")
	if nameLabel then
		nameLabel.Text = creature.name or "Creature"
		nameLabel.TextColor3 = rarityColor
	end

	local rarityLabel = _detailFrame:FindFirstChild("RarityLabel")
	if rarityLabel then
		rarityLabel.Text = creature.rarity or "Common"
		rarityLabel.TextColor3 = rarityColor
	end

	local sourceLabel = _detailFrame:FindFirstChild("SourceLabel")
	if sourceLabel then
		sourceLabel.Text = "Source: " .. (creature.source or "unknown")
	end

	local stats = creature.stats or { hp = 0, atk = 0, def = 0, spd = 0 }
	local statsLabel = _detailFrame:FindFirstChild("StatsLabel")
	if statsLabel then
		statsLabel.Text = string.format("HP: %d  ATK: %d  DEF: %d  SPD: %d", stats.hp, stats.atk, stats.def, stats.spd)
	end

	-- Cooldown
	local cooldownLabel = _detailFrame:FindFirstChild("CooldownLabel")
	if cooldownLabel then
		local cdUntil = creature.breedCooldownUntil or 0
		local remaining = math.max(0, cdUntil - os.time())
		cooldownLabel.Text = "Breed: " .. formatCooldown(remaining)
		cooldownLabel.TextColor3 = if remaining > 0 then COLORS.error else COLORS.success
	end

	-- Viewport thumbnail
	local vpContainer = _detailFrame:FindFirstChild("ViewportContainer")
	if vpContainer then
		for _, child in ipairs(vpContainer:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end
		if creature.modelData then
			createViewportThumbnail(creature.modelData, vpContainer)
		end
	end
end

local function buildUI()
	if _screenGui then
		_screenGui:Destroy()
	end

	_screenGui = Instance.new("ScreenGui")
	_screenGui.Name = "CreatureCollectionUI"
	_screenGui.ResetOnSpawn = false
	_screenGui.DisplayOrder = 9
	_screenGui.Parent = PlayerGui

	-- Toggle button
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "CreatureToggle"
	toggleBtn.Size = UDim2.fromOffset(44, 44)
	toggleBtn.Position = UDim2.new(0, 10, 0.5, -20)
	toggleBtn.BackgroundColor3 = COLORS.panel
	toggleBtn.Text = "🐾"
	toggleBtn.TextSize = 22
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextColor3 = COLORS.text
	toggleBtn.Parent = _screenGui
	createCorner(toggleBtn, 10)

	-- Main panel
	_mainFrame = Instance.new("Frame")
	_mainFrame.Name = "CreaturePanel"
	_mainFrame.Size = UDim2.fromOffset(560, 400)
	_mainFrame.Position = UDim2.new(0.5, -280, 0.5, -200)
	_mainFrame.BackgroundColor3 = COLORS.bg
	_mainFrame.BorderSizePixel = 0
	_mainFrame.Visible = false
	_mainFrame.Parent = _screenGui
	createCorner(_mainFrame, 12)

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 36)
	titleBar.BackgroundColor3 = COLORS.panel
	titleBar.BorderSizePixel = 0
	titleBar.Parent = _mainFrame
	createCorner(titleBar, 12)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -40, 1, 0)
	titleLabel.Position = UDim2.fromOffset(12, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Creature Collection"
	titleLabel.TextColor3 = COLORS.text
	titleLabel.TextSize = 16
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 4)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.textDim
	closeBtn.TextSize = 14
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = titleBar

	-- Left side: creature grid
	local gridContainer = Instance.new("ScrollingFrame")
	gridContainer.Name = "CreatureGrid"
	gridContainer.Size = UDim2.new(0.55, -12, 1, -44)
	gridContainer.Position = UDim2.fromOffset(8, 40)
	gridContainer.BackgroundTransparency = 1
	gridContainer.ScrollBarThickness = 4
	gridContainer.ScrollBarImageColor3 = COLORS.textDim
	gridContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridContainer.Parent = _mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(90, 100)
	gridLayout.CellPadding = UDim2.fromOffset(6, 6)
	gridLayout.Parent = gridContainer

	-- Right side: detail panel
	_detailFrame = Instance.new("Frame")
	_detailFrame.Name = "DetailPanel"
	_detailFrame.Size = UDim2.new(0.45, -12, 1, -44)
	_detailFrame.Position = UDim2.new(0.55, 4, 0, 40)
	_detailFrame.BackgroundColor3 = COLORS.panel
	_detailFrame.BorderSizePixel = 0
	_detailFrame.Visible = false
	_detailFrame.Parent = _mainFrame
	createCorner(_detailFrame, 8)

	-- Detail: viewport container
	local vpContainer = Instance.new("Frame")
	vpContainer.Name = "ViewportContainer"
	vpContainer.Size = UDim2.new(1, -16, 0, 120)
	vpContainer.Position = UDim2.fromOffset(8, 8)
	vpContainer.BackgroundColor3 = COLORS.card
	vpContainer.BorderSizePixel = 0
	vpContainer.Parent = _detailFrame
	createCorner(vpContainer, 6)

	-- Detail: name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -16, 0, 22)
	nameLabel.Position = UDim2.fromOffset(8, 134)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = ""
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextSize = 15
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = _detailFrame

	-- Detail: rarity
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityLabel"
	rarityLabel.Size = UDim2.new(1, -16, 0, 16)
	rarityLabel.Position = UDim2.fromOffset(8, 156)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = ""
	rarityLabel.TextColor3 = COLORS.textDim
	rarityLabel.TextSize = 11
	rarityLabel.Font = Enum.Font.Gotham
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.Parent = _detailFrame

	-- Detail: source
	local sourceLabel = Instance.new("TextLabel")
	sourceLabel.Name = "SourceLabel"
	sourceLabel.Size = UDim2.new(1, -16, 0, 14)
	sourceLabel.Position = UDim2.fromOffset(8, 172)
	sourceLabel.BackgroundTransparency = 1
	sourceLabel.Text = ""
	sourceLabel.TextColor3 = COLORS.textDim
	sourceLabel.TextSize = 10
	sourceLabel.Font = Enum.Font.Gotham
	sourceLabel.TextXAlignment = Enum.TextXAlignment.Left
	sourceLabel.Parent = _detailFrame

	-- Detail: stats
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "StatsLabel"
	statsLabel.Size = UDim2.new(1, -16, 0, 16)
	statsLabel.Position = UDim2.fromOffset(8, 190)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = ""
	statsLabel.TextColor3 = COLORS.accent
	statsLabel.TextSize = 11
	statsLabel.Font = Enum.Font.GothamBold
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Parent = _detailFrame

	-- Detail: breed cooldown
	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "CooldownLabel"
	cooldownLabel.Size = UDim2.new(1, -16, 0, 14)
	cooldownLabel.Position = UDim2.fromOffset(8, 208)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Text = ""
	cooldownLabel.TextColor3 = COLORS.textDim
	cooldownLabel.TextSize = 10
	cooldownLabel.Font = Enum.Font.Gotham
	cooldownLabel.TextXAlignment = Enum.TextXAlignment.Left
	cooldownLabel.Parent = _detailFrame

	-- Action buttons
	local btnY = 230

	-- Rename button
	local renameBtn = Instance.new("TextButton")
	renameBtn.Name = "RenameBtn"
	renameBtn.Size = UDim2.new(1, -16, 0, 26)
	renameBtn.Position = UDim2.fromOffset(8, btnY)
	renameBtn.BackgroundColor3 = COLORS.accent
	renameBtn.Text = "Rename"
	renameBtn.TextColor3 = COLORS.text
	renameBtn.TextSize = 12
	renameBtn.Font = Enum.Font.GothamBold
	renameBtn.Parent = _detailFrame
	createCorner(renameBtn, 6)

	-- Spawn button
	local spawnBtn = Instance.new("TextButton")
	spawnBtn.Name = "SpawnBtn"
	spawnBtn.Size = UDim2.new(1, -16, 0, 26)
	spawnBtn.Position = UDim2.fromOffset(8, btnY + 32)
	spawnBtn.BackgroundColor3 = COLORS.success
	spawnBtn.Text = "Spawn in World"
	spawnBtn.TextColor3 = COLORS.bg
	spawnBtn.TextSize = 12
	spawnBtn.Font = Enum.Font.GothamBold
	spawnBtn.Parent = _detailFrame
	createCorner(spawnBtn, 6)

	-- Release button
	local releaseBtn = Instance.new("TextButton")
	releaseBtn.Name = "ReleaseBtn"
	releaseBtn.Size = UDim2.new(1, -16, 0, 26)
	releaseBtn.Position = UDim2.fromOffset(8, btnY + 64)
	releaseBtn.BackgroundColor3 = COLORS.danger
	releaseBtn.Text = "Release"
	releaseBtn.TextColor3 = COLORS.text
	releaseBtn.TextSize = 12
	releaseBtn.Font = Enum.Font.GothamBold
	releaseBtn.Parent = _detailFrame
	createCorner(releaseBtn, 6)

	-- Button handlers
	renameBtn.MouseButton1Click:Connect(function()
		local creature = getSelectedCreature()
		if not creature then
			return
		end
		-- Simple text input via chat-like rename (use a TextBox overlay)
		local renameBox = Instance.new("TextBox")
		renameBox.Size = UDim2.new(1, -16, 0, 26)
		renameBox.Position = UDim2.fromOffset(8, btnY)
		renameBox.BackgroundColor3 = COLORS.card
		renameBox.Text = creature.name or ""
		renameBox.TextColor3 = COLORS.text
		renameBox.TextSize = 12
		renameBox.Font = Enum.Font.GothamBold
		renameBox.ClearTextOnFocus = false
		renameBox.Parent = _detailFrame
		createCorner(renameBox, 6)

		renameBox:CaptureFocus()
		renameBox.FocusLost:Connect(function(enterPressed)
			if enterPressed and #renameBox.Text > 0 then
				task.spawn(function()
					local CreatureService = Knit.GetService("CreatureService")
					local result = CreatureService:RenameCreature(creature.id, renameBox.Text):await()
					if result and result.success then
						refreshCreatures()
					end
				end)
			end
			renameBox:Destroy()
		end)
	end)

	spawnBtn.MouseButton1Click:Connect(function()
		local creature = getSelectedCreature()
		if creature then
			spawnCreatureInWorld(creature)
		end
	end)

	releaseBtn.MouseButton1Click:Connect(function()
		local creature = getSelectedCreature()
		if not creature then
			return
		end
		-- Confirm release
		releaseBtn.Text = "Click again to confirm"
		releaseBtn.BackgroundColor3 = COLORS.error
		local confirmed = false
		local conn
		conn = releaseBtn.MouseButton1Click:Once(function()
			confirmed = true
			task.spawn(function()
				local CreatureService = Knit.GetService("CreatureService")
				local result = CreatureService:ReleaseCreature(creature.id):await()
				if result and result.success then
					-- If this creature is spawned, despawn it
					if _activeCreatureModel and _activeCreatureModel:GetAttribute("CreatureId") == creature.id then
						despawnActiveCreature()
					end
					_selectedId = nil
					refreshCreatures()
				end
			end)
		end)
		task.delay(3, function()
			if not confirmed then
				releaseBtn.Text = "Release"
				releaseBtn.BackgroundColor3 = COLORS.danger
			end
		end)
	end)

	-- Toggle logic
	toggleBtn.MouseButton1Click:Connect(function()
		_visible = not _visible
		_mainFrame.Visible = _visible
		if _visible then
			refreshCreatures()
		end
	end)

	closeBtn.MouseButton1Click:Connect(function()
		_visible = false
		_mainFrame.Visible = false
	end)
end

local function createCreatureCard(creature: { [string]: any }, parent: GuiObject)
	local rarityColor = EggCraftingConfig.RARITY_COLORS[creature.rarity] or COLORS.text
	local isSelected = creature.id == _selectedId

	local card = Instance.new("TextButton")
	card.Name = creature.id
	card.Size = UDim2.fromOffset(90, 100) -- managed by grid layout
	card.BackgroundColor3 = if isSelected then COLORS.cardSelected else COLORS.card
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = true
	card.Parent = parent
	createCorner(card, 6)

	-- Rarity bar at top
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -8, 0, 3)
	bar.Position = UDim2.fromOffset(4, 4)
	bar.BackgroundColor3 = rarityColor
	bar.BorderSizePixel = 0
	bar.Parent = card
	createCorner(bar, 2)

	-- Viewport thumbnail
	local vpFrame = Instance.new("Frame")
	vpFrame.Size = UDim2.new(1, -12, 0, 58)
	vpFrame.Position = UDim2.fromOffset(6, 10)
	vpFrame.BackgroundTransparency = 1
	vpFrame.Parent = card

	if creature.modelData then
		createViewportThumbnail(creature.modelData, vpFrame)
	end

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -8, 0, 14)
	nameLabel.Position = UDim2.fromOffset(4, 70)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = creature.name or "?"
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextSize = 10
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	-- Rarity text
	local rarityText = Instance.new("TextLabel")
	rarityText.Size = UDim2.new(1, -8, 0, 12)
	rarityText.Position = UDim2.fromOffset(4, 84)
	rarityText.BackgroundTransparency = 1
	rarityText.Text = creature.rarity or "Common"
	rarityText.TextColor3 = rarityColor
	rarityText.TextSize = 9
	rarityText.Font = Enum.Font.Gotham
	rarityText.Parent = card

	card.MouseButton1Click:Connect(function()
		_selectedId = creature.id
		updateDetailPanel()
		-- Update selection visuals
		refreshCreatures()
	end)
end

function refreshCreatures()
	if not _mainFrame then
		return
	end

	task.spawn(function()
		local CreatureService = Knit.GetService("CreatureService")
		local success, creatures = CreatureService:GetCreatures():await()

		if not success or type(creatures) ~= "table" then
			return
		end
		_creatures = creatures

		local grid = _mainFrame:FindFirstChild("CreatureGrid")
		if not grid then
			return
		end

		-- Clear existing cards
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		-- Create creature cards
		for _, creature in ipairs(creatures) do
			createCreatureCard(creature, grid)
		end

		updateDetailPanel()
	end)
end

---------- Lifecycle ----------

local CreatureController = Knit.CreateController({ Name = "CreatureController" })

function CreatureController:KnitInit() end

function CreatureController:KnitStart()
	task.delay(2, function()
		buildUI()
	end)

	-- Listen for new creatures added (from hatching)
	task.spawn(function()
		local CreatureService = Knit.GetService("CreatureService")
		CreatureService.CreatureAdded:Connect(function()
			if _visible then
				refreshCreatures()
			end
		end)
		CreatureService.CreatureRemoved:Connect(function()
			if _visible then
				refreshCreatures()
			end
		end)
	end)
end

function CreatureController:DespawnActiveCreature()
	despawnActiveCreature()
end

return CreatureController
