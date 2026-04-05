--[[
	EggCraftingController — client-side egg crafting UI.
	Shows recipe list with material requirements, craft button, VFX.
	Triggers BreedingController egg refresh on successful craft.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local VFXUtil = require(ReplicatedStorage.Shared.VFXUtil)
local EggCraftingConfig = require(ReplicatedStorage.Shared.EggCraftingConfig)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local COLORS = {
	bg = Color3.fromRGB(25, 25, 35),
	panel = Color3.fromRGB(35, 35, 50),
	card = Color3.fromRGB(45, 45, 65),
	cardHover = Color3.fromRGB(55, 55, 80),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	accent = Color3.fromRGB(100, 180, 255),
	craftable = Color3.fromRGB(80, 200, 120),
	notCraftable = Color3.fromRGB(120, 120, 140),
}

-- State
local _screenGui: ScreenGui? = nil
local _mainFrame: Frame? = nil
local _visible = false
local _recipes = {}
local _crafting = false

local function createCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function formatTime(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	else
		return string.format("%dm", m)
	end
end

local function formatMaterialName(itemId: string): string
	return itemId:gsub("_", " "):gsub("(%a)([%w_]*)", function(a, b)
		return string.upper(a) .. b
	end)
end

local function buildUI()
	if _screenGui then
		_screenGui:Destroy()
	end

	_screenGui = Instance.new("ScreenGui")
	_screenGui.Name = "EggCraftingUI"
	_screenGui.ResetOnSpawn = false
	_screenGui.DisplayOrder = 8
	_screenGui.Parent = PlayerGui

	-- Toggle button
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "CraftToggle"
	toggleBtn.Size = UDim2.fromOffset(44, 44)
	toggleBtn.Position = UDim2.new(0, 10, 0.5, -70)
	toggleBtn.BackgroundColor3 = COLORS.panel
	toggleBtn.Text = "🥚"
	toggleBtn.TextSize = 22
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextColor3 = COLORS.text
	toggleBtn.Parent = _screenGui
	createCorner(toggleBtn, 10)

	-- Main panel
	_mainFrame = Instance.new("Frame")
	_mainFrame.Name = "CraftPanel"
	_mainFrame.Size = UDim2.new(0.8, 0, 0.65, 0)
	_mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	_mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	_mainFrame.BackgroundColor3 = COLORS.bg
	_mainFrame.BorderSizePixel = 0
	_mainFrame.Visible = false
	_mainFrame.Parent = _screenGui
	createCorner(_mainFrame, 12)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(380, 480)
	sizeConstraint.MinSize = Vector2.new(240, 300)
	sizeConstraint.Parent = _mainFrame

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundColor3 = COLORS.panel
	title.Text = "Egg Crafting"
	title.TextColor3 = COLORS.text
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.Parent = _mainFrame
	createCorner(title, 12)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.Position = UDim2.new(1, -32, 0, 4)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.textDim
	closeBtn.TextSize = 14
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = _mainFrame

	-- Scrolling recipe list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "RecipeList"
	scroll.Size = UDim2.new(1, -16, 1, -44)
	scroll.Position = UDim2.fromOffset(8, 40)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COLORS.textDim
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = _mainFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	-- Toggle logic
	toggleBtn.MouseButton1Click:Connect(function()
		_visible = not _visible
		_mainFrame.Visible = _visible
		if _visible then
			refreshRecipes()
		end
	end)

	closeBtn.MouseButton1Click:Connect(function()
		_visible = false
		_mainFrame.Visible = false
	end)
end

local function createRecipeCard(recipe: { [string]: any }, parent: GuiObject)
	local rarityColor = EggCraftingConfig.RARITY_COLORS[recipe.rarity] or COLORS.text

	local card = Instance.new("Frame")
	card.Name = recipe.id
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = parent
	createCorner(card, 8)

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
	nameLabel.Size = UDim2.new(0.6, -16, 0, 20)
	nameLabel.Position = UDim2.fromOffset(14, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = recipe.displayName
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = card

	-- Rarity badge
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(0.4, -8, 0, 20)
	rarityLabel.Position = UDim2.new(0.6, 0, 0, 6)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = recipe.rarity
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.TextSize = 11
	rarityLabel.Font = Enum.Font.Gotham
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Right
	rarityLabel.Parent = card

	-- Hatch time
	local timeLabel = Instance.new("TextLabel")
	timeLabel.Size = UDim2.new(0.5, -14, 0, 16)
	timeLabel.Position = UDim2.fromOffset(14, 26)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = "Hatch: " .. formatTime(recipe.hatchTime)
	timeLabel.TextColor3 = COLORS.textDim
	timeLabel.TextSize = 11
	timeLabel.Font = Enum.Font.Gotham
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Parent = card

	-- Stats
	local stats = recipe.baseStats
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(0.5, -8, 0, 16)
	statsLabel.Position = UDim2.new(0.5, 0, 0, 26)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = string.format("HP:%d ATK:%d DEF:%d SPD:%d", stats.hp, stats.atk, stats.def, stats.spd)
	statsLabel.TextColor3 = COLORS.textDim
	statsLabel.TextSize = 9
	statsLabel.Font = Enum.Font.Gotham
	statsLabel.TextXAlignment = Enum.TextXAlignment.Right
	statsLabel.Parent = card

	-- Materials
	local matY = 46
	for _, mat in ipairs(recipe.materials) do
		local enough = mat.have >= mat.need
		local matLabel = Instance.new("TextLabel")
		matLabel.Size = UDim2.new(1, -20, 0, 14)
		matLabel.Position = UDim2.fromOffset(14, matY)
		matLabel.BackgroundTransparency = 1
		matLabel.Text = string.format("%s  %d / %d", formatMaterialName(mat.itemId), mat.have, mat.need)
		matLabel.TextColor3 = if enough then COLORS.success else COLORS.error
		matLabel.TextSize = 11
		matLabel.Font = Enum.Font.Gotham
		matLabel.TextXAlignment = Enum.TextXAlignment.Left
		matLabel.Parent = card
		matY += 16
	end

	-- Craft button
	local craftBtn = Instance.new("TextButton")
	craftBtn.Size = UDim2.new(1, -20, 0, 24)
	craftBtn.Position = UDim2.new(0, 10, 1, -30)
	craftBtn.BackgroundColor3 = if recipe.canCraft then COLORS.craftable else COLORS.notCraftable
	craftBtn.Text = if recipe.canCraft then "Craft Egg" else "Need Materials"
	craftBtn.TextColor3 = COLORS.text
	craftBtn.TextSize = 12
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.AutoButtonColor = recipe.canCraft
	craftBtn.Parent = card
	createCorner(craftBtn, 6)

	if recipe.canCraft then
		craftBtn.MouseButton1Click:Connect(function()
			if _crafting then
				return
			end
			craftEgg(recipe.id, craftBtn)
		end)
	end
end

function craftEgg(recipeId: string, button: TextButton?)
	_crafting = true
	if button then
		button.Text = "Crafting..."
		button.BackgroundColor3 = COLORS.accent
	end

	task.spawn(function()
		local EggCraftingService = Knit.GetService("EggCraftingService")
		local result = EggCraftingService:CraftEgg(recipeId):await()

		if result and result.success then
			-- VFX
			local character = Player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local rarityColor = EggCraftingConfig.RARITY_COLORS[result.rarity] or COLORS.success
				VFXUtil.sparkle(rootPart.Position + Vector3.new(0, 3, 0), rarityColor, 25, 2)
				VFXUtil.risingText(rootPart.Position + Vector3.new(0, 4, 0), result.displayName .. " crafted!", rarityColor)
			end

			-- Refresh BreedingController eggs (eggs share the PendingEggs system)
			local ok, BreedingController = pcall(function()
				return Knit.GetController("BreedingController")
			end)
			if ok and BreedingController and BreedingController.refreshEggs then
				BreedingController:refreshEggs()
			end

			-- Refresh recipes to update material counts
			refreshRecipes()
		else
			if button then
				button.Text = result and result.error or "Failed"
				button.BackgroundColor3 = COLORS.error
				task.delay(2, function()
					refreshRecipes()
				end)
			end
		end

		_crafting = false
	end)
end

function refreshRecipes()
	if not _mainFrame then
		return
	end

	task.spawn(function()
		local EggCraftingService = Knit.GetService("EggCraftingService")
		local success, recipes = EggCraftingService:GetRecipes():await()

		if not success or type(recipes) ~= "table" then
			return
		end
		_recipes = recipes

		local scroll = _mainFrame:FindFirstChild("RecipeList")
		if not scroll then
			return
		end

		-- Clear existing cards
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		-- Create recipe cards
		for _, recipe in ipairs(recipes) do
			createRecipeCard(recipe, scroll)
		end
	end)
end

---------- Lifecycle ----------

local EggCraftingController = Knit.CreateController({ Name = "EggCraftingController" })

function EggCraftingController:KnitInit() end

function EggCraftingController:KnitStart()
	task.delay(2, function()
		buildUI()
	end)
end

return EggCraftingController
