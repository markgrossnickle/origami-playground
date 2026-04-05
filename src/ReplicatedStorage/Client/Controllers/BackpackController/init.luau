--[[
	BackpackController — unified inventory, tools, creatures, and eggs UI.
	One 📦 button → tabbed modal with Materials, Tools, Critters, Eggs tabs.
	Replaces EggCraftingController and CreatureController standalone UIs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ToolRegistry = require(ReplicatedStorage.Shared.ToolRegistry)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local EggCraftingConfig = require(ReplicatedStorage.Shared.EggCraftingConfig)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local MountConfig = require(ReplicatedStorage.Shared.MountConfig)
local VFXUtil = require(ReplicatedStorage.Shared.VFXUtil)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local COLORS = {
	bg = Color3.fromRGB(25, 25, 35),
	panel = Color3.fromRGB(35, 35, 50),
	card = Color3.fromRGB(45, 45, 65),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	accent = Color3.fromRGB(100, 180, 255),
	craftable = Color3.fromRGB(80, 200, 120),
	notCraftable = Color3.fromRGB(120, 120, 140),
	danger = Color3.fromRGB(200, 60, 60),
	equipped = Color3.fromRGB(70, 130, 90),
	tabActive = Color3.fromRGB(50, 50, 75),
	tabInactive = Color3.fromRGB(35, 35, 50),
}

-- Material depth ordering for sort (shallow → deep)
local MATERIAL_DEPTH_ORDER = {
	paper_scrap = 1,
	cardboard = 2,
	wood = 3,
	dried_pulp = 4,
	compressed_pulp = 5,
	clay_chunk = 6,
	folded_stone = 7,
	quartz_shard = 8,
	paper_crystal = 9,
	ink_stone = 10,
	origami_rock = 11,
	gem_fragment = 12,
	foil_ore = 13,
	ruby_paper = 14,
	crystal_shard = 15,
	foil_sheet = 16,
	metal_origami = 17,
	sapphire_crystal = 18,
	void_stone = 19,
	dark_paper = 20,
	shadow_fold = 21,
	void_crystal = 22,
	prismatic_shard = 23,
	core_fragment = 24,
	rainbow_paper = 25,
}

-- Auto-positioning for creature plot assignment
local PLOT_CREATURE_POSITIONS = { { 4, 4 }, { 12, 4 }, { 20, 4 }, { 4, 12 }, { 12, 12 } }

local TABS = { "Mats", "Tools", "Critters", "Eggs" }
local isMobile = UserInputService.TouchEnabled

-- State
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _contentFrame: ScrollingFrame? = nil
local _tabButtons: { [string]: TextButton } = {}
local _activeTab = "Mats"
local _visible = false
local _crafting = false

-- Cached data
local _inventory: { [string]: number } = {}
local _equippedTool = "paper_hands"
local _creatures: { { [string]: any } } = {}
local _pendingEggs: { { [string]: any } } = {}
local _recipes: { { [string]: any } } = {}
local _plotAssignedIds: { [string]: boolean } = {}

-- Creature spawn state
local _activeCreatureModel: Model? = nil
local _activeCreatureCleanup: (() -> ())? = nil
local _activeCreatureData: { [string]: any }? = nil

-- Egg timer
local _eggTimerThread: thread? = nil

-- Forward declarations
local renderMaterialsTab: () -> ()
local renderToolsTab: () -> ()
local renderCreaturesTab: () -> ()
local renderEggsTab: () -> ()

-- Utility

local function createCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function clearChildren(parent: GuiObject)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function formatMaterialName(itemId: string): string
	return itemId:gsub("_", " "):gsub("(%a)([%w_]*)", function(a, b)
		return string.upper(a) .. b
	end)
end

local function formatTime(seconds: number): string
	if seconds <= 0 then
		return "Ready!"
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	if m > 0 then
		return if s > 0 then string.format("%dm %ds", m, s) else string.format("%dm", m)
	end
	return string.format("%ds", s)
end

local function createEmptyState(parent: GuiObject, text: string)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 0, 60)
	label.Position = UDim2.fromOffset(10, 20)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.textDim
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.TextWrapped = true
	label.Parent = parent
end

-- Data Fetching

local function fetchAllData(callback: (() -> ())?)
	local remaining = 6
	local function onComplete()
		remaining -= 1
		if remaining <= 0 and callback then
			callback()
		end
	end

	task.spawn(function()
		local MiningService = Knit.GetService("MiningService")
		local ok, inv = MiningService:GetMiningInventory():await()
		if ok and type(inv) == "table" then
			_inventory = inv
		end
		onComplete()
	end)

	task.spawn(function()
		local MiningService = Knit.GetService("MiningService")
		local ok, tool = MiningService:GetEquippedTool():await()
		if ok and type(tool) == "string" then
			_equippedTool = tool
		end
		onComplete()
	end)

	task.spawn(function()
		local CreatureService = Knit.GetService("CreatureService")
		local ok, creatures = CreatureService:GetCreatures():await()
		if ok and type(creatures) == "table" then
			_creatures = creatures
		end
		onComplete()
	end)

	task.spawn(function()
		local BreedingService = Knit.GetService("BreedingService")
		local ok, eggs = BreedingService:CheckEggs():await()
		if ok and type(eggs) == "table" then
			_pendingEggs = eggs
		end
		onComplete()
	end)

	task.spawn(function()
		local EggCraftingService = Knit.GetService("EggCraftingService")
		local ok, recipes = EggCraftingService:GetRecipes():await()
		if ok and type(recipes) == "table" then
			_recipes = recipes
		end
		onComplete()
	end)

	task.spawn(function()
		local PlotService = Knit.GetService("PlotService")
		local ok, plotData = PlotService:GetPlotData():await()
		if ok and type(plotData) == "table" and plotData.assignedCreatures then
			_plotAssignedIds = {}
			for _, entry in ipairs(plotData.assignedCreatures) do
				_plotAssignedIds[entry.creatureId] = true
			end
		end
		onComplete()
	end)
end

-- Materials Tab

renderMaterialsTab = function()
	if not _contentFrame then
		return
	end
	clearChildren(_contentFrame)

	-- Build sorted material list (only items in PLACEABLE_BLOCKS with count > 0)
	local materials = {}
	for itemId, count in pairs(_inventory) do
		if count > 0 and PlotConfig.PLACEABLE_BLOCKS[itemId] then
			table.insert(materials, { id = itemId, count = count })
		end
	end

	if #materials == 0 then
		createEmptyState(_contentFrame, "Mine blocks to collect materials!")
		return
	end

	table.sort(materials, function(a, b)
		return (MATERIAL_DEPTH_ORDER[a.id] or 99) < (MATERIAL_DEPTH_ORDER[b.id] or 99)
	end)

	local columns = if isMobile then 3 else 4
	local cellSize = 70

	local gridFrame = Instance.new("Frame")
	gridFrame.Size = UDim2.new(1, 0, 0, 0)
	gridFrame.BackgroundTransparency = 1
	gridFrame.AutomaticSize = Enum.AutomaticSize.Y
	gridFrame.Parent = _contentFrame

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cellSize, cellSize)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = columns
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridFrame

	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingLeft = UDim.new(0, 6)
	gridPad.PaddingTop = UDim.new(0, 6)
	gridPad.Parent = gridFrame

	for i, mat in ipairs(materials) do
		local blockConfig = PlotConfig.PLACEABLE_BLOCKS[mat.id]
		local cell = Instance.new("Frame")
		cell.LayoutOrder = i
		cell.BackgroundColor3 = Color3.fromRGB(blockConfig.color[1], blockConfig.color[2], blockConfig.color[3])
		cell.BorderSizePixel = 0
		cell.Parent = gridFrame
		createCorner(cell, 6)

		-- Count badge
		local countLabel = Instance.new("TextLabel")
		countLabel.Size = UDim2.new(1, -4, 0, 18)
		countLabel.Position = UDim2.fromOffset(2, 2)
		countLabel.BackgroundColor3 = COLORS.bg
		countLabel.BackgroundTransparency = 0.4
		countLabel.Text = tostring(mat.count)
		countLabel.TextColor3 = COLORS.text
		countLabel.TextSize = 12
		countLabel.Font = Enum.Font.GothamBold
		countLabel.Parent = cell
		createCorner(countLabel, 4)

		-- Name at bottom
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -4, 0, 16)
		nameLabel.Position = UDim2.new(0, 2, 1, -18)
		nameLabel.BackgroundColor3 = COLORS.bg
		nameLabel.BackgroundTransparency = 0.4
		nameLabel.Text = blockConfig.name
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextSize = 9
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = cell
		createCorner(nameLabel, 4)
	end
end

-- Tools Tab

local function equipTool(toolId: string)
	local MiningService = Knit.GetService("MiningService")
	MiningService.EquipTool:Fire(toolId)
	_equippedTool = toolId
	renderToolsTab()
end

local function craftTool(toolId: string, button: TextButton?)
	if _crafting then
		return
	end
	_crafting = true
	if button then
		button.Text = "Crafting..."
		button.BackgroundColor3 = COLORS.accent
	end
	local MiningService = Knit.GetService("MiningService")
	MiningService.CraftTool:Fire(toolId)
	-- ToolAcquired listener in KnitStart handles refresh + auto-equip.
	-- Timeout fallback if craft silently fails.
	task.delay(5, function()
		if _crafting then
			_crafting = false
			if _visible and _activeTab == "Tools" then
				renderToolsTab()
			end
		end
	end)
end

renderToolsTab = function()
	if not _contentFrame then
		return
	end
	clearChildren(_contentFrame)

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 0)
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = _contentFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = container

	-- Equipped tool section
	local eqConfig = ToolRegistry.get(_equippedTool) or ToolRegistry.getDefault()

	local eqCard = Instance.new("Frame")
	eqCard.Size = UDim2.new(1, 0, 0, 50)
	eqCard.BackgroundColor3 = COLORS.equipped
	eqCard.BorderSizePixel = 0
	eqCard.LayoutOrder = 0
	eqCard.Parent = container
	createCorner(eqCard, 8)

	local eqTitle = Instance.new("TextLabel")
	eqTitle.Size = UDim2.new(1, -60, 0, 18)
	eqTitle.Position = UDim2.fromOffset(8, 4)
	eqTitle.BackgroundTransparency = 1
	eqTitle.Text = "Equipped: " .. eqConfig.name
	eqTitle.TextColor3 = COLORS.text
	eqTitle.TextSize = 13
	eqTitle.Font = Enum.Font.GothamBold
	eqTitle.TextXAlignment = Enum.TextXAlignment.Left
	eqTitle.Parent = eqCard

	local tierBadge = Instance.new("TextLabel")
	tierBadge.Size = UDim2.fromOffset(44, 16)
	tierBadge.Position = UDim2.new(1, -52, 0, 5)
	tierBadge.BackgroundColor3 = COLORS.accent
	tierBadge.Text = "Tier " .. eqConfig.tier
	tierBadge.TextColor3 = COLORS.bg
	tierBadge.TextSize = 10
	tierBadge.Font = Enum.Font.GothamBold
	tierBadge.Parent = eqCard
	createCorner(tierBadge, 4)

	local eqStats = Instance.new("TextLabel")
	eqStats.Size = UDim2.new(1, -16, 0, 14)
	eqStats.Position = UDim2.fromOffset(8, 26)
	eqStats.BackgroundTransparency = 1
	eqStats.Text = string.format("Power: %d  Speed: %.1f  Reach: %d", eqConfig.power, eqConfig.speed, eqConfig.reach)
	eqStats.TextColor3 = COLORS.text
	eqStats.TextSize = 11
	eqStats.Font = Enum.Font.Gotham
	eqStats.TextXAlignment = Enum.TextXAlignment.Left
	eqStats.Parent = eqCard

	-- Tool list (ordered by tier)
	for orderIdx, toolId in ipairs(ToolRegistry.TierOrder) do
		local toolConfig = ToolRegistry.get(toolId)
		if not toolConfig then
			continue
		end

		local isEquipped = toolId == _equippedTool
		local hasItem = toolId == "paper_hands" or (_inventory[toolId] and _inventory[toolId] > 0)
		local canCraft = not hasItem and toolConfig.craftRecipe and ToolRegistry.canCraft(toolId, _inventory)

		-- Calculate card height (taller if showing recipe materials)
		local recipeMatCount = 0
		if not hasItem and toolConfig.craftRecipe then
			for _ in pairs(toolConfig.craftRecipe) do
				recipeMatCount += 1
			end
		end
		local cardHeight = if recipeMatCount > 0 then 38 + recipeMatCount * 14 else 40

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, cardHeight)
		card.BackgroundColor3 = COLORS.card
		card.BorderSizePixel = 0
		card.LayoutOrder = orderIdx
		card.Parent = container
		createCorner(card, 6)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.55, 0, 0, 16)
		nameLabel.Position = UDim2.fromOffset(8, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = toolConfig.name
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextSize = 12
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local statsLine = Instance.new("TextLabel")
		statsLine.Size = UDim2.new(1, -16, 0, 12)
		statsLine.Position = UDim2.fromOffset(8, 22)
		statsLine.BackgroundTransparency = 1
		statsLine.Text = string.format(
			"Pwr:%d  Spd:%.1f  Rch:%d  T%d",
			toolConfig.power,
			toolConfig.speed,
			toolConfig.reach,
			toolConfig.tier
		)
		statsLine.TextColor3 = COLORS.textDim
		statsLine.TextSize = 10
		statsLine.Font = Enum.Font.Gotham
		statsLine.TextXAlignment = Enum.TextXAlignment.Left
		statsLine.Parent = card

		if isEquipped then
			local eqLabel = Instance.new("TextLabel")
			eqLabel.Size = UDim2.fromOffset(64, 22)
			eqLabel.Position = UDim2.new(1, -72, 0, 9)
			eqLabel.BackgroundTransparency = 1
			eqLabel.Text = "Equipped"
			eqLabel.TextColor3 = COLORS.textDim
			eqLabel.TextSize = 11
			eqLabel.Font = Enum.Font.Gotham
			eqLabel.Parent = card
		elseif hasItem then
			local equipBtn = Instance.new("TextButton")
			equipBtn.Size = UDim2.fromOffset(60, 22)
			equipBtn.Position = UDim2.new(1, -68, 0, 9)
			equipBtn.BackgroundColor3 = COLORS.success
			equipBtn.Text = "Equip"
			equipBtn.TextColor3 = COLORS.bg
			equipBtn.TextSize = 11
			equipBtn.Font = Enum.Font.GothamBold
			equipBtn.Parent = card
			createCorner(equipBtn, 4)
			equipBtn.MouseButton1Click:Connect(function()
				equipTool(toolId)
			end)
		elseif toolConfig.craftRecipe then
			-- Show material requirements
			local matY = 38
			for itemId, needed in pairs(toolConfig.craftRecipe) do
				local have = _inventory[itemId] or 0
				local matLabel = Instance.new("TextLabel")
				matLabel.Size = UDim2.new(0.6, -8, 0, 13)
				matLabel.Position = UDim2.fromOffset(8, matY)
				matLabel.BackgroundTransparency = 1
				matLabel.Text = string.format("%s %d/%d", formatMaterialName(itemId), have, needed)
				matLabel.TextColor3 = if have >= needed then COLORS.success else COLORS.error
				matLabel.TextSize = 10
				matLabel.Font = Enum.Font.Gotham
				matLabel.TextXAlignment = Enum.TextXAlignment.Left
				matLabel.Parent = card
				matY += 14
			end

			local craftBtn = Instance.new("TextButton")
			craftBtn.Size = UDim2.fromOffset(60, 22)
			craftBtn.Position = UDim2.new(1, -68, 0, 9)
			craftBtn.BackgroundColor3 = if canCraft then COLORS.craftable else COLORS.notCraftable
			craftBtn.Text = "Craft"
			craftBtn.TextColor3 = COLORS.text
			craftBtn.TextSize = 11
			craftBtn.Font = Enum.Font.GothamBold
			craftBtn.AutoButtonColor = canCraft ~= nil
			craftBtn.Parent = card
			createCorner(craftBtn, 4)

			if canCraft then
				craftBtn.MouseButton1Click:Connect(function()
					craftTool(toolId, craftBtn)
				end)
			end
		end
	end
end

-- Creatures Tab

local function despawnActiveCreature()
	if _activeCreatureCleanup then
		_activeCreatureCleanup()
		_activeCreatureCleanup = nil
	end
	if _activeCreatureModel and _activeCreatureModel.Parent then
		_activeCreatureModel:Destroy()
	end
	_activeCreatureModel = nil
	_activeCreatureData = nil
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
	_activeCreatureData = creature
	_activeCreatureCleanup = CreatureAI.Start(model, creature.modelData, spawnPos, { model, character })

	-- Add ProximityPrompt for mounting (if creature is mountable)
	local locomotion = creature.modelData.locomotion or "walk"
	if MountConfig.isMountable(locomotion) then
		local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = creature.name or "Creature"
			prompt.ActionText = "Ride"
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = primaryPart

			prompt.Triggered:Connect(function(triggerPlayer: Player)
				if triggerPlayer ~= Player then
					return
				end
				local MountController = Knit.GetController("MountController")
				if MountController and _activeCreatureData and _activeCreatureModel then
					prompt.Enabled = false
					task.spawn(function()
						MountController:mountCreatureFromWorld(
							_activeCreatureData,
							_activeCreatureModel,
							_activeCreatureCleanup
						)
						_activeCreatureCleanup = nil
					end)
				end
			end)
		end
	end

	local rarityColor = EggCraftingConfig.RARITY_COLORS[creature.rarity] or COLORS.success
	VFXUtil.sparkle(spawnPos + Vector3.new(0, 2, 0), rarityColor, 15, 1.5)
end

local function assignCreatureToPlot(creatureId: string)
	task.spawn(function()
		local PlotService = Knit.GetService("PlotService")
		local ok, plotData = PlotService:GetPlotData():await()
		if not ok or type(plotData) ~= "table" or not plotData.origin then
			return
		end

		-- Find first open position
		local assigned = plotData.assignedCreatures or {}
		local usedPositions = {}
		for _, entry in ipairs(assigned) do
			usedPositions[entry.localX .. "," .. entry.localZ] = true
		end

		local localX, localZ
		for _, pos in ipairs(PLOT_CREATURE_POSITIONS) do
			if not usedPositions[pos[1] .. "," .. pos[2]] then
				localX, localZ = pos[1], pos[2]
				break
			end
		end
		if not localX then
			return
		end

		local result = PlotService:AssignCreature(creatureId, localX, localZ):await()
		if result and result.success then
			_plotAssignedIds[creatureId] = true
			if _visible and _activeTab == "Critters" then
				renderCreaturesTab()
			end
		end
	end)
end

local function releaseCreature(creatureId: string, button: TextButton)
	button.Text = "Confirm?"
	button.BackgroundColor3 = COLORS.error
	local confirmed = false

	button.MouseButton1Click:Once(function()
		confirmed = true
		task.spawn(function()
			local CreatureService = Knit.GetService("CreatureService")
			local result = CreatureService:ReleaseCreature(creatureId):await()
			if result and result.success then
				if _activeCreatureModel and _activeCreatureModel:GetAttribute("CreatureId") == creatureId then
					despawnActiveCreature()
				end
				local ok2, creatures = CreatureService:GetCreatures():await()
				if ok2 and type(creatures) == "table" then
					_creatures = creatures
				end
				renderCreaturesTab()
			end
		end)
	end)

	task.delay(3, function()
		if not confirmed and button.Parent then
			button.Text = "Release"
			button.BackgroundColor3 = COLORS.danger
		end
	end)
end

renderCreaturesTab = function()
	if not _contentFrame then
		return
	end
	clearChildren(_contentFrame)

	if #_creatures == 0 then
		createEmptyState(_contentFrame, "Craft eggs to get creatures!")
		return
	end

	local gridFrame = Instance.new("Frame")
	gridFrame.Size = UDim2.new(1, 0, 0, 0)
	gridFrame.BackgroundTransparency = 1
	gridFrame.AutomaticSize = Enum.AutomaticSize.Y
	gridFrame.Parent = _contentFrame

	local cellWidth = if isMobile then 155 else 170
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cellWidth, 140)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = 2
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridFrame

	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingLeft = UDim.new(0, 6)
	gridPad.PaddingTop = UDim.new(0, 6)
	gridPad.Parent = gridFrame

	for i, creature in ipairs(_creatures) do
		local rarityColor = EggCraftingConfig.RARITY_COLORS[creature.rarity] or COLORS.text
		local isOnPlot = _plotAssignedIds[creature.id] or false

		local card = Instance.new("Frame")
		card.Name = creature.id
		card.LayoutOrder = i
		card.BackgroundColor3 = COLORS.card
		card.BorderSizePixel = 0
		card.Parent = gridFrame
		createCorner(card, 6)

		-- Rarity color bar
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, -8, 0, 3)
		bar.Position = UDim2.fromOffset(4, 4)
		bar.BackgroundColor3 = rarityColor
		bar.BorderSizePixel = 0
		bar.Parent = card
		createCorner(bar, 2)

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, -8, 0, 16)
		nameLabel.Position = UDim2.fromOffset(4, 10)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = creature.name or "?"
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextSize = 12
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = card

		-- Rarity text
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Size = UDim2.new(1, -8, 0, 14)
		rarityLabel.Position = UDim2.fromOffset(4, 26)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Text = creature.rarity or "Common"
		rarityLabel.TextColor3 = rarityColor
		rarityLabel.TextSize = 10
		rarityLabel.Font = Enum.Font.Gotham
		rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
		rarityLabel.Parent = card

		-- Stats line
		local stats = creature.stats or { hp = 0, atk = 0, def = 0, spd = 0 }
		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(1, -8, 0, 12)
		statsLabel.Position = UDim2.fromOffset(4, 40)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Text = string.format("HP:%d ATK:%d DEF:%d SPD:%d", stats.hp, stats.atk, stats.def, stats.spd)
		statsLabel.TextColor3 = COLORS.accent
		statsLabel.TextSize = 9
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Parent = card

		-- Action buttons: row 1 = Spawn, Ride, To Plot (3-col); row 2 = Rename, Release (2-col)
		local btnW = math.floor((cellWidth - 16) / 2)
		local btnW3 = math.floor((cellWidth - 20) / 3)
		local btnH = 22
		local btnY1 = 58
		local btnY2 = 84
		local btnX2 = btnW + 10

		local isMountable = MountConfig.isMountable(creature.modelData and creature.modelData.locomotion or "walk")

		-- Spawn
		local spawnBtn = Instance.new("TextButton")
		spawnBtn.Size = UDim2.fromOffset(if isMountable then btnW3 else btnW, btnH)
		spawnBtn.Position = UDim2.fromOffset(4, btnY1)
		spawnBtn.BackgroundColor3 = COLORS.success
		spawnBtn.Text = "Spawn"
		spawnBtn.TextColor3 = COLORS.bg
		spawnBtn.TextSize = 10
		spawnBtn.Font = Enum.Font.GothamBold
		spawnBtn.Parent = card
		createCorner(spawnBtn, 4)
		spawnBtn.MouseButton1Click:Connect(function()
			spawnCreatureInWorld(creature)
		end)

		-- Ride (only for mountable creatures)
		if isMountable then
			local rideBtn = Instance.new("TextButton")
			rideBtn.Size = UDim2.fromOffset(btnW3, btnH)
			rideBtn.Position = UDim2.fromOffset(4 + btnW3 + 4, btnY1)
			rideBtn.BackgroundColor3 = Color3.fromRGB(200, 160, 60)
			rideBtn.Text = "Ride"
			rideBtn.TextColor3 = COLORS.bg
			rideBtn.TextSize = 10
			rideBtn.Font = Enum.Font.GothamBold
			rideBtn.Parent = card
			createCorner(rideBtn, 4)
			rideBtn.MouseButton1Click:Connect(function()
				local MountController = Knit.GetController("MountController")
				if MountController then
					despawnActiveCreature()
					task.spawn(function()
						MountController:mountCreature(creature)
					end)
				end
			end)
		end

		-- To Plot / On Plot
		local plotBtn = Instance.new("TextButton")
		plotBtn.Size = UDim2.fromOffset(if isMountable then btnW3 else btnW, btnH)
		plotBtn.Position = UDim2.fromOffset(if isMountable then (4 + (btnW3 + 4) * 2) else btnX2, btnY1)
		plotBtn.BackgroundColor3 = if isOnPlot then COLORS.textDim else COLORS.accent
		plotBtn.Text = if isOnPlot then "On Plot" else "To Plot"
		plotBtn.TextColor3 = COLORS.bg
		plotBtn.TextSize = 10
		plotBtn.Font = Enum.Font.GothamBold
		plotBtn.AutoButtonColor = not isOnPlot
		plotBtn.Parent = card
		createCorner(plotBtn, 4)
		if not isOnPlot then
			plotBtn.MouseButton1Click:Connect(function()
				assignCreatureToPlot(creature.id)
			end)
		end

		-- Rename
		local renameBtn = Instance.new("TextButton")
		renameBtn.Size = UDim2.fromOffset(btnW, btnH)
		renameBtn.Position = UDim2.fromOffset(4, btnY2)
		renameBtn.BackgroundColor3 = COLORS.panel
		renameBtn.Text = "Rename"
		renameBtn.TextColor3 = COLORS.text
		renameBtn.TextSize = 10
		renameBtn.Font = Enum.Font.GothamBold
		renameBtn.Parent = card
		createCorner(renameBtn, 4)
		renameBtn.MouseButton1Click:Connect(function()
			local nameL = card:FindFirstChild("NameLabel")
			if not nameL then
				return
			end

			local renameBox = Instance.new("TextBox")
			renameBox.Size = nameL.Size
			renameBox.Position = nameL.Position
			renameBox.BackgroundColor3 = COLORS.bg
			renameBox.Text = nameL.Text
			renameBox.TextColor3 = COLORS.text
			renameBox.TextSize = 12
			renameBox.Font = Enum.Font.GothamBold
			renameBox.ClearTextOnFocus = false
			renameBox.Parent = card
			createCorner(renameBox, 4)

			nameL.Visible = false
			renameBox:CaptureFocus()
			renameBox.FocusLost:Connect(function(enterPressed)
				if enterPressed and #renameBox.Text > 0 then
					task.spawn(function()
						local CreatureService = Knit.GetService("CreatureService")
						local result = CreatureService:RenameCreature(creature.id, renameBox.Text):await()
						if result and result.success then
							nameL.Text = renameBox.Text
						end
					end)
				end
				nameL.Visible = true
				renameBox:Destroy()
			end)
		end)

		-- Release
		local relBtn = Instance.new("TextButton")
		relBtn.Size = UDim2.fromOffset(btnW, btnH)
		relBtn.Position = UDim2.fromOffset(btnX2, btnY2)
		relBtn.BackgroundColor3 = COLORS.danger
		relBtn.Text = "Release"
		relBtn.TextColor3 = COLORS.text
		relBtn.TextSize = 10
		relBtn.Font = Enum.Font.GothamBold
		relBtn.Parent = card
		createCorner(relBtn, 4)
		relBtn.MouseButton1Click:Connect(function()
			releaseCreature(creature.id, relBtn)
		end)
	end
end

-- Eggs Tab

local function startEggTimers()
	if _eggTimerThread then
		task.cancel(_eggTimerThread)
		_eggTimerThread = nil
	end

	_eggTimerThread = task.spawn(function()
		local tickCount = 0
		while _visible and _activeTab == "Eggs" do
			task.wait(1)
			tickCount += 1

			-- Decrement local counters
			for _, egg in ipairs(_pendingEggs) do
				if egg.remainingSeconds and egg.remainingSeconds > 0 then
					egg.remainingSeconds -= 1
				end
			end

			-- Update timer labels in UI
			if _contentFrame then
				for _, child in ipairs(_contentFrame:GetDescendants()) do
					if child.Name == "EggTimerLabel" and child:IsA("TextLabel") then
						local eggIdx = child:GetAttribute("EggIndex")
						if eggIdx then
							for _, egg in ipairs(_pendingEggs) do
								if egg.index == eggIdx then
									child.Text = formatTime(egg.remainingSeconds or 0)
									child.TextColor3 = if (egg.remainingSeconds or 0) <= 0
										then COLORS.success
										else COLORS.text
									break
								end
							end
						end
					end
				end
			end

			-- Server sync every 30s
			if tickCount % 30 == 0 then
				local BreedingService = Knit.GetService("BreedingService")
				local ok, eggs = BreedingService:CheckEggs():await()
				if ok and type(eggs) == "table" then
					_pendingEggs = eggs
				end
			end
		end
	end)
end

local function hatchEgg(eggIndex: number, button: TextButton?)
	task.spawn(function()
		local BreedingService = Knit.GetService("BreedingService")
		local ok, result = BreedingService:HatchEgg(eggIndex):await()
		if not ok then
			result = { success = false, error = "Service call failed" }
		end

		if result and result.success then
			local character = Player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local rarityColor = EggCraftingConfig.RARITY_COLORS[result.rarity] or COLORS.success
				VFXUtil.sparkle(rootPart.Position + Vector3.new(0, 3, 0), rarityColor, 30, 2)
				local hatchText = if result.rarity then result.rarity .. " Hatched!" else "Hatched!"
				if result.mutated then
					hatchText = "MUTATION! " .. hatchText
				end
				VFXUtil.risingText(rootPart.Position + Vector3.new(0, 4, 0), hatchText, rarityColor)
			end

			-- Refresh BreedingController world eggs
			local ok, bc = pcall(function()
				return Knit.GetController("BreedingController")
			end)
			if ok and bc and bc.refreshEggs then
				bc:refreshEggs()
			end

			-- Refresh eggs data
			local ok2, eggs = BreedingService:CheckEggs():await()
			if ok2 and type(eggs) == "table" then
				_pendingEggs = eggs
			end

			-- Refresh creatures and switch to Critters tab to show the new hatch
			local ok3, creatures = pcall(function()
				local CreatureService = Knit.GetService("CreatureService")
				local cOk, cList = CreatureService:GetCreatures():await()
				if cOk and type(cList) == "table" then
					_creatures = cList
				end
			end)

			switchTab("Critters")
		elseif button and button.Parent then
			button.Text = "Failed"
			button.BackgroundColor3 = COLORS.error
			task.delay(2, function()
				if button.Parent then
					button.Text = "Hatch"
					button.BackgroundColor3 = COLORS.success
				end
			end)
		end
	end)
end

local function craftEgg(recipeId: string, button: TextButton?)
	if _crafting then
		return
	end
	_crafting = true
	if button then
		button.Text = "Crafting..."
		button.BackgroundColor3 = COLORS.accent
	end

	task.spawn(function()
		local EggCraftingService = Knit.GetService("EggCraftingService")
		local result = EggCraftingService:CraftEgg(recipeId):await()

		if result and result.success then
			local character = Player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local rarityColor = EggCraftingConfig.RARITY_COLORS[result.rarity] or COLORS.success
				VFXUtil.sparkle(rootPart.Position + Vector3.new(0, 3, 0), rarityColor, 25, 2)
				VFXUtil.risingText(
					rootPart.Position + Vector3.new(0, 4, 0),
					(result.displayName or "Egg") .. " crafted!",
					rarityColor
				)
			end

			local ok, bc = pcall(function()
				return Knit.GetController("BreedingController")
			end)
			if ok and bc and bc.refreshEggs then
				bc:refreshEggs()
			end

			-- Refresh all egg-related data
			local ok2, eggs = Knit.GetService("BreedingService"):CheckEggs():await()
			if ok2 and type(eggs) == "table" then
				_pendingEggs = eggs
			end
			local ok3, recipes = EggCraftingService:GetRecipes():await()
			if ok3 and type(recipes) == "table" then
				_recipes = recipes
			end
			local ok4, inv = Knit.GetService("MiningService"):GetMiningInventory():await()
			if ok4 and type(inv) == "table" then
				_inventory = inv
			end

			renderEggsTab()
		else
			if button and button.Parent then
				button.Text = result and result.error or "Failed"
				button.BackgroundColor3 = COLORS.error
				task.delay(2, function()
					renderEggsTab()
				end)
			end
		end

		_crafting = false
	end)
end

renderEggsTab = function()
	if not _contentFrame then
		return
	end
	clearChildren(_contentFrame)

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 0)
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = _contentFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = container

	local orderIdx = 0

	-- Section 1: Pending Eggs
	if #_pendingEggs > 0 then
		local sectionLabel = Instance.new("TextLabel")
		sectionLabel.Size = UDim2.new(1, 0, 0, 20)
		sectionLabel.BackgroundTransparency = 1
		sectionLabel.Text = "Pending Eggs"
		sectionLabel.TextColor3 = COLORS.text
		sectionLabel.TextSize = 14
		sectionLabel.Font = Enum.Font.GothamBold
		sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
		sectionLabel.LayoutOrder = orderIdx
		sectionLabel.Parent = container
		orderIdx += 1

		for _, egg in ipairs(_pendingEggs) do
			local rarityColor = EggCraftingConfig.RARITY_COLORS[egg.rarity] or COLORS.text
			local isReady = (egg.remainingSeconds or 0) <= 0 or egg.ready

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 50)
			card.BackgroundColor3 = COLORS.card
			card.BorderSizePixel = 0
			card.LayoutOrder = orderIdx
			card.Parent = container
			createCorner(card, 6)
			orderIdx += 1

			-- Rarity stripe
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 4, 1, -8)
			stripe.Position = UDim2.fromOffset(4, 4)
			stripe.BackgroundColor3 = rarityColor
			stripe.BorderSizePixel = 0
			stripe.Parent = card
			createCorner(stripe, 2)

			-- Info label
			local sourceText = egg.source or "crafted"
			local infoLabel = Instance.new("TextLabel")
			infoLabel.Size = UDim2.new(0.6, -14, 0, 16)
			infoLabel.Position = UDim2.fromOffset(14, 4)
			infoLabel.BackgroundTransparency = 1
			infoLabel.Text = (egg.rarity or "?") .. " (" .. sourceText .. ")"
			infoLabel.TextColor3 = rarityColor
			infoLabel.TextSize = 11
			infoLabel.Font = Enum.Font.GothamBold
			infoLabel.TextXAlignment = Enum.TextXAlignment.Left
			infoLabel.Parent = card

			-- Timer
			local timerLabel = Instance.new("TextLabel")
			timerLabel.Name = "EggTimerLabel"
			timerLabel.Size = UDim2.new(0.4, 0, 0, 16)
			timerLabel.Position = UDim2.fromOffset(14, 26)
			timerLabel.BackgroundTransparency = 1
			timerLabel.Text = formatTime(egg.remainingSeconds or 0)
			timerLabel.TextColor3 = if isReady then COLORS.success else COLORS.text
			timerLabel.TextSize = 12
			timerLabel.Font = Enum.Font.GothamBold
			timerLabel.TextXAlignment = Enum.TextXAlignment.Left
			timerLabel.Parent = card
			timerLabel:SetAttribute("EggIndex", egg.index)

			-- Hatch button (when ready)
			if isReady then
				local hatchBtn = Instance.new("TextButton")
				hatchBtn.Size = UDim2.fromOffset(60, 24)
				hatchBtn.Position = UDim2.new(1, -68, 0, 13)
				hatchBtn.BackgroundColor3 = COLORS.success
				hatchBtn.Text = "Hatch"
				hatchBtn.TextColor3 = COLORS.bg
				hatchBtn.TextSize = 11
				hatchBtn.Font = Enum.Font.GothamBold
				hatchBtn.Parent = card
				createCorner(hatchBtn, 4)
				hatchBtn.MouseButton1Click:Connect(function()
					hatchEgg(egg.index, hatchBtn)
				end)
			end
		end
	end

	-- Section 2: Craft Eggs
	local craftLabel = Instance.new("TextLabel")
	craftLabel.Size = UDim2.new(1, 0, 0, 20)
	craftLabel.BackgroundTransparency = 1
	craftLabel.Text = "Craft Eggs"
	craftLabel.TextColor3 = COLORS.text
	craftLabel.TextSize = 14
	craftLabel.Font = Enum.Font.GothamBold
	craftLabel.TextXAlignment = Enum.TextXAlignment.Left
	craftLabel.LayoutOrder = orderIdx
	craftLabel.Parent = container
	orderIdx += 1

	if #_recipes == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 30)
		empty.BackgroundTransparency = 1
		empty.Text = "No egg recipes available"
		empty.TextColor3 = COLORS.textDim
		empty.TextSize = 12
		empty.Font = Enum.Font.Gotham
		empty.LayoutOrder = orderIdx
		empty.Parent = container
	else
		for _, recipe in ipairs(_recipes) do
			local rarityColor = EggCraftingConfig.RARITY_COLORS[recipe.rarity] or COLORS.text

			local card = Instance.new("Frame")
			card.Name = recipe.id
			card.Size = UDim2.new(1, 0, 0, 100)
			card.BackgroundColor3 = COLORS.card
			card.BorderSizePixel = 0
			card.LayoutOrder = orderIdx
			card.Parent = container
			createCorner(card, 8)
			orderIdx += 1

			-- Rarity stripe
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 4, 1, -8)
			stripe.Position = UDim2.fromOffset(4, 4)
			stripe.BackgroundColor3 = rarityColor
			stripe.BorderSizePixel = 0
			stripe.Parent = card
			createCorner(stripe, 2)

			-- Name + rarity
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.6, -16, 0, 18)
			nameLabel.Position = UDim2.fromOffset(14, 4)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = recipe.displayName
			nameLabel.TextColor3 = rarityColor
			nameLabel.TextSize = 13
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = card

			local rarityBadge = Instance.new("TextLabel")
			rarityBadge.Size = UDim2.new(0.4, -8, 0, 16)
			rarityBadge.Position = UDim2.new(0.6, 0, 0, 5)
			rarityBadge.BackgroundTransparency = 1
			rarityBadge.Text = recipe.rarity
			rarityBadge.TextColor3 = rarityColor
			rarityBadge.TextSize = 10
			rarityBadge.Font = Enum.Font.Gotham
			rarityBadge.TextXAlignment = Enum.TextXAlignment.Right
			rarityBadge.Parent = card

			-- Hatch time
			local timeLabel = Instance.new("TextLabel")
			timeLabel.Size = UDim2.new(0.5, -14, 0, 14)
			timeLabel.Position = UDim2.fromOffset(14, 24)
			timeLabel.BackgroundTransparency = 1
			timeLabel.Text = "Hatch: " .. formatTime(recipe.hatchTime)
			timeLabel.TextColor3 = COLORS.textDim
			timeLabel.TextSize = 10
			timeLabel.Font = Enum.Font.Gotham
			timeLabel.TextXAlignment = Enum.TextXAlignment.Left
			timeLabel.Parent = card

			-- Stats
			local bstats = recipe.baseStats
			if bstats then
				local statsLine = Instance.new("TextLabel")
				statsLine.Size = UDim2.new(0.5, -8, 0, 14)
				statsLine.Position = UDim2.new(0.5, 0, 0, 24)
				statsLine.BackgroundTransparency = 1
				statsLine.Text =
					string.format("HP:%d ATK:%d DEF:%d SPD:%d", bstats.hp, bstats.atk, bstats.def, bstats.spd)
				statsLine.TextColor3 = COLORS.textDim
				statsLine.TextSize = 9
				statsLine.Font = Enum.Font.Gotham
				statsLine.TextXAlignment = Enum.TextXAlignment.Right
				statsLine.Parent = card
			end

			-- Materials
			local matY = 42
			for _, mat in ipairs(recipe.materials) do
				local enough = mat.have >= mat.need
				local matLabel = Instance.new("TextLabel")
				matLabel.Size = UDim2.new(1, -20, 0, 13)
				matLabel.Position = UDim2.fromOffset(14, matY)
				matLabel.BackgroundTransparency = 1
				matLabel.Text = string.format("%s  %d / %d", formatMaterialName(mat.itemId), mat.have, mat.need)
				matLabel.TextColor3 = if enough then COLORS.success else COLORS.error
				matLabel.TextSize = 10
				matLabel.Font = Enum.Font.Gotham
				matLabel.TextXAlignment = Enum.TextXAlignment.Left
				matLabel.Parent = card
				matY += 14
			end

			-- Craft button
			local craftBtn = Instance.new("TextButton")
			craftBtn.Size = UDim2.new(1, -20, 0, 22)
			craftBtn.Position = UDim2.new(0, 10, 1, -28)
			craftBtn.BackgroundColor3 = if recipe.canCraft then COLORS.craftable else COLORS.notCraftable
			craftBtn.Text = if recipe.canCraft then "Craft Egg" else "Need Materials"
			craftBtn.TextColor3 = COLORS.text
			craftBtn.TextSize = 11
			craftBtn.Font = Enum.Font.GothamBold
			craftBtn.AutoButtonColor = recipe.canCraft
			craftBtn.Parent = card
			createCorner(craftBtn, 4)

			if recipe.canCraft then
				craftBtn.MouseButton1Click:Connect(function()
					craftEgg(recipe.id, craftBtn)
				end)
			end
		end
	end

	-- Start egg timers
	startEggTimers()
end

-- Tab Switching & Panel Toggle

local function switchTab(tabName: string)
	_activeTab = tabName

	for name, btn in pairs(_tabButtons) do
		btn.BackgroundColor3 = if name == tabName then COLORS.tabActive else COLORS.tabInactive
		btn.TextColor3 = if name == tabName then COLORS.text else COLORS.textDim
	end

	-- Stop egg timers when leaving eggs tab
	if tabName ~= "Eggs" and _eggTimerThread then
		task.cancel(_eggTimerThread)
		_eggTimerThread = nil
	end

	if tabName == "Mats" then
		renderMaterialsTab()
	elseif tabName == "Tools" then
		renderToolsTab()
	elseif tabName == "Critters" then
		renderCreaturesTab()
	elseif tabName == "Eggs" then
		renderEggsTab()
	end
end

local function togglePanel()
	_visible = not _visible
	if _mainFrame then
		_mainFrame.Visible = _visible
	end

	if _visible then
		fetchAllData(function()
			if _visible then
				switchTab(_activeTab)
			end
		end)
	else
		if _eggTimerThread then
			task.cancel(_eggTimerThread)
			_eggTimerThread = nil
		end
	end
end

-- UI Construction

local function buildUI()
	if _screenGui then
		_screenGui:Destroy()
	end

	_screenGui = Instance.new("ScreenGui")
	_screenGui.Name = "BackpackUI"
	_screenGui.ResetOnSpawn = false
	_screenGui.DisplayOrder = 9
	_screenGui.Parent = PlayerGui

	-- Toggle button
	local toggleSize = if isMobile then 48 else 44
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "BackpackToggle"
	toggleBtn.Size = UDim2.fromOffset(toggleSize, toggleSize)
	toggleBtn.Position = UDim2.new(0, 10, 0.5, 0)
	toggleBtn.AnchorPoint = Vector2.new(0, 0.5)
	toggleBtn.BackgroundColor3 = COLORS.panel
	toggleBtn.Text = "\xF0\x9F\x93\xA6" -- 📦
	toggleBtn.TextSize = 22
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextColor3 = COLORS.text
	toggleBtn.Parent = _screenGui
	createCorner(toggleBtn, 10)

	-- Main panel
	_mainFrame = Instance.new("Frame")
	_mainFrame.Name = "BackpackPanel"
	_mainFrame.Size = if isMobile then UDim2.new(0.92, 0, 0.75, 0) else UDim2.new(0.8, 0, 0.7, 0)
	_mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	_mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	_mainFrame.BackgroundColor3 = COLORS.bg
	_mainFrame.BorderSizePixel = 0
	_mainFrame.Visible = false
	_mainFrame.Parent = _screenGui
	createCorner(_mainFrame, 12)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(420, 520)
	sizeConstraint.MinSize = Vector2.new(300, 400)
	sizeConstraint.Parent = _mainFrame

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 36)
	titleBar.BackgroundColor3 = COLORS.panel
	titleBar.BorderSizePixel = 0
	titleBar.Parent = _mainFrame
	createCorner(titleBar, 12)

	-- Fill bottom of title bar (hide rounded corners)
	local titleFill = Instance.new("Frame")
	titleFill.Size = UDim2.new(1, 0, 0, 12)
	titleFill.Position = UDim2.new(0, 0, 1, -12)
	titleFill.BackgroundColor3 = COLORS.panel
	titleFill.BorderSizePixel = 0
	titleFill.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -40, 1, 0)
	titleLabel.Position = UDim2.fromOffset(12, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Backpack"
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

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, 32)
	tabBar.Position = UDim2.fromOffset(0, 36)
	tabBar.BackgroundColor3 = COLORS.panel
	tabBar.BorderSizePixel = 0
	tabBar.Parent = _mainFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Parent = tabBar

	_tabButtons = {}
	for _, tabName in ipairs(TABS) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = tabName
		tabBtn.Size = UDim2.new(1 / #TABS, 0, 1, 0)
		tabBtn.BackgroundColor3 = if tabName == _activeTab then COLORS.tabActive else COLORS.tabInactive
		tabBtn.Text = tabName
		tabBtn.TextColor3 = if tabName == _activeTab then COLORS.text else COLORS.textDim
		tabBtn.TextSize = 12
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.BorderSizePixel = 0
		tabBtn.Parent = tabBar

		tabBtn.MouseButton1Click:Connect(function()
			switchTab(tabName)
		end)

		_tabButtons[tabName] = tabBtn
	end

	-- Content area (scrolling)
	_contentFrame = Instance.new("ScrollingFrame")
	_contentFrame.Name = "Content"
	_contentFrame.Size = UDim2.new(1, 0, 1, -68)
	_contentFrame.Position = UDim2.fromOffset(0, 68)
	_contentFrame.BackgroundTransparency = 1
	_contentFrame.ScrollBarThickness = 4
	_contentFrame.ScrollBarImageColor3 = COLORS.textDim
	_contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	_contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	_contentFrame.Parent = _mainFrame

	-- Event handlers
	toggleBtn.MouseButton1Click:Connect(togglePanel)
	closeBtn.MouseButton1Click:Connect(function()
		_visible = false
		_mainFrame.Visible = false
		if _eggTimerThread then
			task.cancel(_eggTimerThread)
			_eggTimerThread = nil
		end
	end)
end

-- Lifecycle

local BackpackController = Knit.CreateController({ Name = "BackpackController" })

function BackpackController:KnitInit() end

function BackpackController:KnitStart()
	task.delay(2, function()
		buildUI()
	end)

	-- Keyboard/gamepad hotkeys
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.DPadDown then
			togglePanel()
		end
	end)

	-- Live update listeners
	task.spawn(function()
		local MiningService = Knit.GetService("MiningService")

		-- Material count update on mine
		MiningService.MiningResult:Connect(function(success, droppedItemId, droppedCount)
			if success and droppedItemId and droppedCount then
				_inventory[droppedItemId] = (_inventory[droppedItemId] or 0) + droppedCount
				if _visible and _activeTab == "Mats" then
					renderMaterialsTab()
				end
			end
		end)

		-- Tool equipped
		MiningService.ToolEquipped:Connect(function(toolId)
			_equippedTool = toolId
			if _visible and _activeTab == "Tools" then
				renderToolsTab()
			end
		end)

		-- Tool acquired (crafted)
		MiningService.ToolAcquired:Connect(function(toolId)
			_inventory[toolId] = (_inventory[toolId] or 0) + 1
			_crafting = false
			-- Auto-equip newly crafted tool
			_equippedTool = toolId
			MiningService.EquipTool:Fire(toolId)
			if _visible and _activeTab == "Tools" then
				task.spawn(function()
					local ok, inv = MiningService:GetMiningInventory():await()
					if ok and type(inv) == "table" then
						_inventory = inv
					end
					renderToolsTab()
				end)
			end
		end)
	end)

	-- Creature live updates
	task.spawn(function()
		local CreatureService = Knit.GetService("CreatureService")

		CreatureService.CreatureAdded:Connect(function()
			task.spawn(function()
				local ok, creatures = CreatureService:GetCreatures():await()
				if ok and type(creatures) == "table" then
					_creatures = creatures
				end
				if _visible and _activeTab == "Critters" then
					renderCreaturesTab()
				end
			end)
		end)

		CreatureService.CreatureRemoved:Connect(function()
			task.spawn(function()
				local ok, creatures = CreatureService:GetCreatures():await()
				if ok and type(creatures) == "table" then
					_creatures = creatures
				end
				if _visible and _activeTab == "Critters" then
					renderCreaturesTab()
				end
			end)
		end)
	end)
end

function BackpackController:DespawnActiveCreature()
	despawnActiveCreature()
end

return BackpackController
