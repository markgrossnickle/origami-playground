--[[
	WorkshopTab — renders the Workshop tab inside the BackpackController.
	Handles type filters, pending crafts, recipe cards, crafted items, and equip/place actions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WorkshopConfig = require(ReplicatedStorage.Shared.WorkshopConfig)
local EggCraftingConfig = require(ReplicatedStorage.Shared.EggCraftingConfig)

local Player = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled

local WorkshopTab = {}

-- These are injected by BackpackController
WorkshopTab.COLORS = nil :: any
WorkshopTab.createCorner = nil :: any
WorkshopTab.clearChildren = nil :: any
WorkshopTab.formatMaterialName = nil :: any
WorkshopTab.formatTime = nil :: any
WorkshopTab.createEmptyState = nil :: any
WorkshopTab.showPromptModal = nil :: any
WorkshopTab.contentFrame = nil :: any
WorkshopTab.screenGui = nil :: any
WorkshopTab.onRefreshNeeded = nil :: (() -> ())?

-- State
local _pendingCrafts: { any } = {}
local _craftedItems: { any } = {}
local _workshopRecipes: { any } = {}
local _equipped: { [string]: string? } = {}
local _typeFilter: string = "accessory"
local _crafting = false
local _craftTimerThread: thread? = nil

function WorkshopTab.getPendingCrafts()
	return _pendingCrafts
end

function WorkshopTab.fetchData(callback: (() -> ())?)
	local remaining = 4
	local function onComplete()
		remaining -= 1
		if remaining <= 0 and callback then
			callback()
		end
	end

	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local ok, recipes = WorkshopService:GetRecipes():await()
		if ok and type(recipes) == "table" then
			_workshopRecipes = recipes
		end
		onComplete()
	end)

	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local ok, crafts = WorkshopService:CheckCrafts():await()
		if ok and type(crafts) == "table" then
			_pendingCrafts = crafts
		end
		onComplete()
	end)

	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local ok, items = WorkshopService:GetCraftedItems():await()
		if ok and type(items) == "table" then
			_craftedItems = items
		end
		onComplete()
	end)

	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local ok, eq = WorkshopService:GetEquipped():await()
		if ok and type(eq) == "table" then
			_equipped = eq
		end
		onComplete()
	end)
end

function WorkshopTab.stopTimers()
	if _craftTimerThread then
		task.cancel(_craftTimerThread)
		_craftTimerThread = nil
	end
end

local function startCraftTimers(renderFn: () -> ())
	WorkshopTab.stopTimers()

	_craftTimerThread = task.spawn(function()
		while true do
			task.wait(1)

			for _, craft in ipairs(_pendingCrafts) do
				if craft.remainingSeconds and craft.remainingSeconds > 0 then
					craft.remainingSeconds -= 1
				end
			end

			local needsRerender = false
			for _, craft in ipairs(_pendingCrafts) do
				if craft.remainingSeconds == 0 then
					needsRerender = true
					break
				end
			end

			if needsRerender then
				renderFn()
			elseif WorkshopTab.contentFrame then
				for _, child in ipairs(WorkshopTab.contentFrame:GetDescendants()) do
					if child.Name == "CraftTimerLabel" and child:IsA("TextLabel") then
						local craftIdx = child:GetAttribute("CraftIndex")
						if craftIdx then
							for _, craft in ipairs(_pendingCrafts) do
								if craft.index == craftIdx then
									child.Text = WorkshopTab.formatTime(craft.remainingSeconds or 0)
									child.TextColor3 = if (craft.remainingSeconds or 0) <= 0
										then WorkshopTab.COLORS.success
										else WorkshopTab.COLORS.text
									break
								end
							end
						end
					end
				end
			end
		end
	end)
end

local function claimItem(craftIndex: number, button: TextButton?)
	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local ok, result = WorkshopService:ClaimItem(craftIndex):await()
		if not ok then
			result = { success = false, error = "Service call failed" }
		end

		if result and result.success then
			-- Refresh data and re-render
			local ok2, crafts = WorkshopService:CheckCrafts():await()
			if ok2 and type(crafts) == "table" then
				_pendingCrafts = crafts
			end
			local ok3, items = WorkshopService:GetCraftedItems():await()
			if ok3 and type(items) == "table" then
				_craftedItems = items
			end
			if WorkshopTab.onRefreshNeeded then
				WorkshopTab.onRefreshNeeded()
			end
		elseif button and button.Parent then
			button.Text = "Failed"
			button.BackgroundColor3 = WorkshopTab.COLORS.error
			task.delay(2, function()
				if button.Parent then
					button.Text = "Claim"
					button.BackgroundColor3 = WorkshopTab.COLORS.success
				end
			end)
		end
	end)
end

local function craftItem(recipeId: string, button: TextButton?, userPrompt: string?)
	if _crafting then
		return
	end
	_crafting = true
	if button then
		button.Text = "Crafting..."
		button.BackgroundColor3 = WorkshopTab.COLORS.accent
	end

	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local result = WorkshopService:CraftItem(recipeId, userPrompt or ""):await()

		if result and result.success then
			-- Refresh all workshop data
			local ok2, crafts = WorkshopService:CheckCrafts():await()
			if ok2 and type(crafts) == "table" then
				_pendingCrafts = crafts
			end
			local ok3, recipes = WorkshopService:GetRecipes():await()
			if ok3 and type(recipes) == "table" then
				_workshopRecipes = recipes
			end
			if WorkshopTab.onRefreshNeeded then
				WorkshopTab.onRefreshNeeded()
			end
		else
			if button and button.Parent then
				button.Text = result and result.error or "Failed"
				button.BackgroundColor3 = WorkshopTab.COLORS.error
				task.delay(2, function()
					if WorkshopTab.onRefreshNeeded then
						WorkshopTab.onRefreshNeeded()
					end
				end)
			end
		end

		_crafting = false
	end)
end

local function equipItem(itemId: string, button: TextButton?)
	task.spawn(function()
		if button then
			button.Text = "..."
		end
		local WorkshopService = Knit.GetService("WorkshopService")
		local result = WorkshopService:EquipItem(itemId):await()

		if result and result.success then
			local ok2, eq = WorkshopService:GetEquipped():await()
			if ok2 and type(eq) == "table" then
				_equipped = eq
			end
			if WorkshopTab.onRefreshNeeded then
				WorkshopTab.onRefreshNeeded()
			end
		elseif button and button.Parent then
			button.Text = result and result.error or "Failed"
			task.delay(2, function()
				if WorkshopTab.onRefreshNeeded then
					WorkshopTab.onRefreshNeeded()
				end
			end)
		end
	end)
end

local function unequipItem(itemType: string)
	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")
		local result = WorkshopService:UnequipItem(itemType):await()

		if result and result.success then
			local ok2, eq = WorkshopService:GetEquipped():await()
			if ok2 and type(eq) == "table" then
				_equipped = eq
			end
			if WorkshopTab.onRefreshNeeded then
				WorkshopTab.onRefreshNeeded()
			end
		end
	end)
end

local function deleteItem(itemId: string, button: TextButton)
	button.Text = "Confirm?"
	button.BackgroundColor3 = WorkshopTab.COLORS.error
	local confirmed = false

	button.MouseButton1Click:Once(function()
		confirmed = true
		task.spawn(function()
			local WorkshopService = Knit.GetService("WorkshopService")
			WorkshopService:DeleteItem(itemId):await()

			local ok2, items = WorkshopService:GetCraftedItems():await()
			if ok2 and type(items) == "table" then
				_craftedItems = items
			end
			local ok3, eq = WorkshopService:GetEquipped():await()
			if ok3 and type(eq) == "table" then
				_equipped = eq
			end
			if WorkshopTab.onRefreshNeeded then
				WorkshopTab.onRefreshNeeded()
			end
		end)
	end)

	task.delay(3, function()
		if not confirmed and button.Parent then
			button.Text = "Delete"
			button.BackgroundColor3 = WorkshopTab.COLORS.danger
		end
	end)
end

local function renameItem(itemId: string, card: Frame, nameLabel: TextLabel)
	local COLORS = WorkshopTab.COLORS

	local renameBox = Instance.new("TextBox")
	renameBox.Size = nameLabel.Size
	renameBox.Position = nameLabel.Position
	renameBox.BackgroundColor3 = COLORS.bg
	renameBox.Text = nameLabel.Text
	renameBox.TextColor3 = COLORS.text
	renameBox.TextSize = 12
	renameBox.Font = Enum.Font.GothamBold
	renameBox.ClearTextOnFocus = false
	renameBox.Parent = card
	WorkshopTab.createCorner(renameBox, 4)

	nameLabel.Visible = false
	renameBox:CaptureFocus()
	renameBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and #renameBox.Text > 0 then
			task.spawn(function()
				local WorkshopService = Knit.GetService("WorkshopService")
				local result = WorkshopService:RenameItem(itemId, renameBox.Text):await()
				if result and result.success then
					nameLabel.Text = renameBox.Text
				end
			end)
		end
		nameLabel.Visible = true
		renameBox:Destroy()
	end)
end

local function placeProp(itemId: string, button: TextButton?)
	task.spawn(function()
		if button then
			button.Text = "Placing..."
		end
		-- Place at a default position on the plot (center, ground level)
		local WorkshopService = Knit.GetService("WorkshopService")
		local result = WorkshopService:PlaceProp(itemId, 12, 0, 12):await()

		if result and result.success then
			if button and button.Parent then
				button.Text = "Placed!"
				button.BackgroundColor3 = WorkshopTab.COLORS.success
				task.delay(1.5, function()
					if WorkshopTab.onRefreshNeeded then
						WorkshopTab.onRefreshNeeded()
					end
				end)
			end
		elseif button and button.Parent then
			button.Text = result and result.error or "Failed"
			button.BackgroundColor3 = WorkshopTab.COLORS.error
			task.delay(2, function()
				if button.Parent then
					button.Text = "Place"
					button.BackgroundColor3 = WorkshopTab.COLORS.accent
				end
			end)
		end
	end)
end

function WorkshopTab.render()
	local contentFrame = WorkshopTab.contentFrame
	if not contentFrame then
		return
	end
	WorkshopTab.clearChildren(contentFrame)

	local COLORS = WorkshopTab.COLORS
	local createCorner = WorkshopTab.createCorner
	local formatMaterialName = WorkshopTab.formatMaterialName
	local formatTime = WorkshopTab.formatTime

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 0)
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = contentFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.Parent = container

	local orderIdx = 0

	-- ═══════════════════════════════
	-- Section 1: Pending Crafts
	-- ═══════════════════════════════
	if #_pendingCrafts > 0 then
		local sectionLabel = Instance.new("TextLabel")
		sectionLabel.Size = UDim2.new(1, 0, 0, 20)
		sectionLabel.BackgroundTransparency = 1
		sectionLabel.Text = "Pending Crafts"
		sectionLabel.TextColor3 = COLORS.text
		sectionLabel.TextSize = 14
		sectionLabel.Font = Enum.Font.GothamBold
		sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
		sectionLabel.LayoutOrder = orderIdx
		sectionLabel.Parent = container
		orderIdx += 1

		for _, craft in ipairs(_pendingCrafts) do
			local rarityColor = EggCraftingConfig.RARITY_COLORS[craft.rarity] or COLORS.text
			local isReady = (craft.remainingSeconds or 0) <= 0 or craft.ready

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

			-- Info
			local typeDisplay = WorkshopConfig.ITEM_TYPE_DISPLAY[craft.itemType] or craft.itemType
			local infoLabel = Instance.new("TextLabel")
			infoLabel.Size = UDim2.new(0.6, -14, 0, 16)
			infoLabel.Position = UDim2.fromOffset(14, 4)
			infoLabel.BackgroundTransparency = 1
			infoLabel.Text = (craft.displayName or "?") .. " (" .. typeDisplay .. ")"
			infoLabel.TextColor3 = rarityColor
			infoLabel.TextSize = 11
			infoLabel.Font = Enum.Font.GothamBold
			infoLabel.TextXAlignment = Enum.TextXAlignment.Left
			infoLabel.TextTruncate = Enum.TextTruncate.AtEnd
			infoLabel.Parent = card

			-- Timer
			local timerLabel = Instance.new("TextLabel")
			timerLabel.Name = "CraftTimerLabel"
			timerLabel.Size = UDim2.new(0.4, 0, 0, 16)
			timerLabel.Position = UDim2.fromOffset(14, 26)
			timerLabel.BackgroundTransparency = 1
			timerLabel.Text = formatTime(craft.remainingSeconds or 0)
			timerLabel.TextColor3 = if isReady then COLORS.success else COLORS.text
			timerLabel.TextSize = 12
			timerLabel.Font = Enum.Font.GothamBold
			timerLabel.TextXAlignment = Enum.TextXAlignment.Left
			timerLabel.Parent = card
			timerLabel:SetAttribute("CraftIndex", craft.index)

			-- Claim button
			if isReady then
				local claimBtn = Instance.new("TextButton")
				claimBtn.Size = UDim2.fromOffset(60, 24)
				claimBtn.Position = UDim2.new(1, -68, 0, 13)
				claimBtn.BackgroundColor3 = COLORS.success
				claimBtn.Text = "Claim"
				claimBtn.TextColor3 = COLORS.bg
				claimBtn.TextSize = 11
				claimBtn.Font = Enum.Font.GothamBold
				claimBtn.Parent = card
				createCorner(claimBtn, 4)
				claimBtn.MouseButton1Click:Connect(function()
					claimItem(craft.index, claimBtn)
				end)
			end
		end
	end

	-- ═══════════════════════════════
	-- Section 2: Type Filter Bar
	-- ═══════════════════════════════
	local filterBar = Instance.new("Frame")
	filterBar.Size = UDim2.new(1, 0, 0, 28)
	filterBar.BackgroundTransparency = 1
	filterBar.LayoutOrder = orderIdx
	filterBar.Parent = container
	orderIdx += 1

	local filterLayout = Instance.new("UIListLayout")
	filterLayout.FillDirection = Enum.FillDirection.Horizontal
	filterLayout.Padding = UDim.new(0, 4)
	filterLayout.Parent = filterBar

	for i, itemType in ipairs(WorkshopConfig.ITEM_TYPES) do
		local isActive = itemType == _typeFilter
		local display = WorkshopConfig.ITEM_TYPE_DISPLAY[itemType] or itemType

		local filterBtn = Instance.new("TextButton")
		filterBtn.Size = UDim2.new(1 / 4, -4, 1, 0)
		filterBtn.LayoutOrder = i
		filterBtn.BackgroundColor3 = if isActive then COLORS.accent else COLORS.card
		filterBtn.Text = display
		filterBtn.TextColor3 = if isActive then COLORS.bg else COLORS.textDim
		filterBtn.TextSize = 10
		filterBtn.Font = Enum.Font.GothamBold
		filterBtn.BorderSizePixel = 0
		filterBtn.Parent = filterBar
		createCorner(filterBtn, 4)

		filterBtn.MouseButton1Click:Connect(function()
			_typeFilter = itemType
			WorkshopTab.render()
		end)
	end

	-- ═══════════════════════════════
	-- Section 3: Recipes for current type
	-- ═══════════════════════════════
	local recipesLabel = Instance.new("TextLabel")
	recipesLabel.Size = UDim2.new(1, 0, 0, 20)
	recipesLabel.BackgroundTransparency = 1
	recipesLabel.Text = "Craft " .. (WorkshopConfig.ITEM_TYPE_DISPLAY[_typeFilter] or "Items")
	recipesLabel.TextColor3 = COLORS.text
	recipesLabel.TextSize = 14
	recipesLabel.Font = Enum.Font.GothamBold
	recipesLabel.TextXAlignment = Enum.TextXAlignment.Left
	recipesLabel.LayoutOrder = orderIdx
	recipesLabel.Parent = container
	orderIdx += 1

	local filteredRecipes = {}
	for _, recipe in ipairs(_workshopRecipes) do
		if recipe.itemType == _typeFilter then
			table.insert(filteredRecipes, recipe)
		end
	end

	if #filteredRecipes == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 30)
		empty.BackgroundTransparency = 1
		empty.Text = "No recipes available"
		empty.TextColor3 = COLORS.textDim
		empty.TextSize = 12
		empty.Font = Enum.Font.Gotham
		empty.LayoutOrder = orderIdx
		empty.Parent = container
		orderIdx += 1
	else
		for _, recipe in ipairs(filteredRecipes) do
			local rarityColor = EggCraftingConfig.RARITY_COLORS[recipe.rarity] or COLORS.text

			local card = Instance.new("Frame")
			card.Name = recipe.id
			card.Size = UDim2.new(1, 0, 0, 90)
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

			-- Name
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

			-- Rarity badge
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

			-- Craft time
			local timeLabel = Instance.new("TextLabel")
			timeLabel.Size = UDim2.new(0.5, -14, 0, 14)
			timeLabel.Position = UDim2.fromOffset(14, 24)
			timeLabel.BackgroundTransparency = 1
			timeLabel.Text = "Time: " .. formatTime(recipe.craftTime)
			timeLabel.TextColor3 = COLORS.textDim
			timeLabel.TextSize = 10
			timeLabel.Font = Enum.Font.Gotham
			timeLabel.TextXAlignment = Enum.TextXAlignment.Left
			timeLabel.Parent = card

			-- Materials
			local matY = 40
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
			craftBtn.Text = if recipe.canCraft then "Craft" else "Need Materials"
			craftBtn.TextColor3 = COLORS.text
			craftBtn.TextSize = 11
			craftBtn.Font = Enum.Font.GothamBold
			craftBtn.AutoButtonColor = recipe.canCraft
			craftBtn.Parent = card
			createCorner(craftBtn, 4)

			if recipe.canCraft then
				craftBtn.Activated:Connect(function()
					local promptSubtitle = if _typeFilter == "costume"
						then "Describe your costume (optional)"
						elseif _typeFilter == "tool" then "Describe your weapon (optional)"
						elseif _typeFilter == "prop" then "Describe your decoration (optional)"
						else "Describe your accessory (optional)"

					WorkshopTab.showPromptModal(recipe.displayName, function(promptText)
						if promptText ~= nil then
							craftItem(recipe.id, craftBtn, promptText)
						end
					end, promptSubtitle)
				end)
			end
		end
	end

	-- ═══════════════════════════════
	-- Section 4: Your Items (filtered by type)
	-- ═══════════════════════════════
	local filteredItems = {}
	for _, item in ipairs(_craftedItems) do
		if item.itemType == _typeFilter then
			table.insert(filteredItems, item)
		end
	end

	local itemsLabel = Instance.new("TextLabel")
	itemsLabel.Size = UDim2.new(1, 0, 0, 20)
	itemsLabel.BackgroundTransparency = 1
	itemsLabel.Text = "Your "
		.. (WorkshopConfig.ITEM_TYPE_DISPLAY[_typeFilter] or "Items")
		.. " ("
		.. #filteredItems
		.. ")"
	itemsLabel.TextColor3 = COLORS.text
	itemsLabel.TextSize = 14
	itemsLabel.Font = Enum.Font.GothamBold
	itemsLabel.TextXAlignment = Enum.TextXAlignment.Left
	itemsLabel.LayoutOrder = orderIdx
	itemsLabel.Parent = container
	orderIdx += 1

	if #filteredItems == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 30)
		empty.BackgroundTransparency = 1
		empty.Text = "No items yet — craft some!"
		empty.TextColor3 = COLORS.textDim
		empty.TextSize = 12
		empty.Font = Enum.Font.Gotham
		empty.LayoutOrder = orderIdx
		empty.Parent = container
	else
		local cellWidth = if isMobile then 155 else 170
		local gridFrame = Instance.new("Frame")
		gridFrame.Size = UDim2.new(1, 0, 0, 0)
		gridFrame.BackgroundTransparency = 1
		gridFrame.AutomaticSize = Enum.AutomaticSize.Y
		gridFrame.LayoutOrder = orderIdx
		gridFrame.Parent = container
		orderIdx += 1

		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(cellWidth, 120)
		grid.CellPadding = UDim2.fromOffset(6, 6)
		grid.FillDirection = Enum.FillDirection.Horizontal
		grid.FillDirectionMaxCells = 2
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = gridFrame

		local gridPad = Instance.new("UIPadding")
		gridPad.PaddingTop = UDim.new(0, 4)
		gridPad.Parent = gridFrame

		for i, item in ipairs(filteredItems) do
			local rarityColor = EggCraftingConfig.RARITY_COLORS[item.rarity] or COLORS.text
			local isEquipped = _equipped[item.itemType] == item.id

			local card = Instance.new("Frame")
			card.Name = item.id
			card.LayoutOrder = i
			card.BackgroundColor3 = if isEquipped then COLORS.equipped else COLORS.card
			card.BorderSizePixel = 0
			card.Parent = gridFrame
			createCorner(card, 6)

			-- Rarity bar
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(1, -8, 0, 3)
			bar.Position = UDim2.fromOffset(4, 4)
			bar.BackgroundColor3 = rarityColor
			bar.BorderSizePixel = 0
			bar.Parent = card
			createCorner(bar, 2)

			-- Name
			local nameL = Instance.new("TextLabel")
			nameL.Name = "NameLabel"
			nameL.Size = UDim2.new(1, -8, 0, 16)
			nameL.Position = UDim2.fromOffset(4, 10)
			nameL.BackgroundTransparency = 1
			nameL.Text = item.name or "?"
			nameL.TextColor3 = COLORS.text
			nameL.TextSize = 12
			nameL.Font = Enum.Font.GothamBold
			nameL.TextXAlignment = Enum.TextXAlignment.Left
			nameL.TextTruncate = Enum.TextTruncate.AtEnd
			nameL.Parent = card

			-- Rarity
			local rarityL = Instance.new("TextLabel")
			rarityL.Size = UDim2.new(1, -8, 0, 14)
			rarityL.Position = UDim2.fromOffset(4, 26)
			rarityL.BackgroundTransparency = 1
			rarityL.Text = item.rarity or "Common"
			rarityL.TextColor3 = rarityColor
			rarityL.TextSize = 10
			rarityL.Font = Enum.Font.Gotham
			rarityL.TextXAlignment = Enum.TextXAlignment.Left
			rarityL.Parent = card

			-- Tool stats if applicable
			if item.toolStats then
				local statsL = Instance.new("TextLabel")
				statsL.Size = UDim2.new(1, -8, 0, 12)
				statsL.Position = UDim2.fromOffset(4, 40)
				statsL.BackgroundTransparency = 1
				statsL.Text = string.format(
					"DMG:%d SPD:%.1f RNG:%d",
					item.toolStats.damage,
					item.toolStats.speed,
					item.toolStats.range
				)
				statsL.TextColor3 = COLORS.accent
				statsL.TextSize = 9
				statsL.Font = Enum.Font.Gotham
				statsL.TextXAlignment = Enum.TextXAlignment.Left
				statsL.Parent = card
			end

			-- Action buttons
			local btnW = math.floor((cellWidth - 16) / 2)
			local btnH = 22
			local btnY1 = 56
			local btnY2 = 82
			local btnX2 = btnW + 10
			local isProp = item.itemType == "prop"

			-- Equip / Unequip / Place
			local equipBtn = Instance.new("TextButton")
			equipBtn.Size = UDim2.fromOffset(btnW, btnH)
			equipBtn.Position = UDim2.fromOffset(4, btnY1)
			equipBtn.Parent = card
			createCorner(equipBtn, 4)

			if isProp then
				equipBtn.BackgroundColor3 = COLORS.accent
				equipBtn.Text = "Place"
				equipBtn.TextColor3 = COLORS.bg
				equipBtn.TextSize = 10
				equipBtn.Font = Enum.Font.GothamBold
				equipBtn.MouseButton1Click:Connect(function()
					placeProp(item.id, equipBtn)
				end)
			elseif isEquipped then
				equipBtn.BackgroundColor3 = COLORS.textDim
				equipBtn.Text = "Unequip"
				equipBtn.TextColor3 = COLORS.bg
				equipBtn.TextSize = 10
				equipBtn.Font = Enum.Font.GothamBold
				equipBtn.MouseButton1Click:Connect(function()
					unequipItem(item.itemType)
				end)
			else
				equipBtn.BackgroundColor3 = COLORS.success
				equipBtn.Text = "Equip"
				equipBtn.TextColor3 = COLORS.bg
				equipBtn.TextSize = 10
				equipBtn.Font = Enum.Font.GothamBold
				equipBtn.MouseButton1Click:Connect(function()
					equipItem(item.id, equipBtn)
				end)
			end

			-- Rename
			local renameBtn = Instance.new("TextButton")
			renameBtn.Size = UDim2.fromOffset(btnW, btnH)
			renameBtn.Position = UDim2.fromOffset(btnX2, btnY1)
			renameBtn.BackgroundColor3 = COLORS.panel
			renameBtn.Text = "Rename"
			renameBtn.TextColor3 = COLORS.text
			renameBtn.TextSize = 10
			renameBtn.Font = Enum.Font.GothamBold
			renameBtn.Parent = card
			createCorner(renameBtn, 4)
			renameBtn.MouseButton1Click:Connect(function()
				local nl = card:FindFirstChild("NameLabel")
				if nl then
					renameItem(item.id, card, nl)
				end
			end)

			-- Delete
			local delBtn = Instance.new("TextButton")
			delBtn.Size = UDim2.new(1, -8, 0, btnH)
			delBtn.Position = UDim2.fromOffset(4, btnY2)
			delBtn.BackgroundColor3 = COLORS.danger
			delBtn.Text = "Delete"
			delBtn.TextColor3 = COLORS.text
			delBtn.TextSize = 10
			delBtn.Font = Enum.Font.GothamBold
			delBtn.Parent = card
			createCorner(delBtn, 4)
			delBtn.MouseButton1Click:Connect(function()
				deleteItem(item.id, delBtn)
			end)
		end
	end

	-- Start craft timers
	startCraftTimers(WorkshopTab.render)
end

function WorkshopTab.connectLiveUpdates()
	task.spawn(function()
		local WorkshopService = Knit.GetService("WorkshopService")

		WorkshopService.ItemCrafted:Connect(function()
			task.spawn(function()
				local ok, crafts = WorkshopService:CheckCrafts():await()
				if ok and type(crafts) == "table" then
					_pendingCrafts = crafts
				end
			end)
		end)

		WorkshopService.ItemClaimed:Connect(function()
			task.spawn(function()
				local ok, crafts = WorkshopService:CheckCrafts():await()
				if ok and type(crafts) == "table" then
					_pendingCrafts = crafts
				end
				local ok2, items = WorkshopService:GetCraftedItems():await()
				if ok2 and type(items) == "table" then
					_craftedItems = items
				end
			end)
		end)

		WorkshopService.ItemEquipped:Connect(function()
			task.spawn(function()
				local ok, eq = WorkshopService:GetEquipped():await()
				if ok and type(eq) == "table" then
					_equipped = eq
				end
			end)
		end)

		WorkshopService.ItemUnequipped:Connect(function()
			task.spawn(function()
				local ok, eq = WorkshopService:GetEquipped():await()
				if ok and type(eq) == "table" then
					_equipped = eq
				end
			end)
		end)
	end)
end

return WorkshopTab
