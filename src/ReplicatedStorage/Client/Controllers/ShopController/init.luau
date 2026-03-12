--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)

local ShopConfig = require(ReplicatedStorage.Shared.ShopConfig)

local Player = Knit.Player
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Layout constants
local IS_MOBILE = UserInputService.TouchEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()
local BUTTON_MIN_SIZE = 48
local GRID_COLUMNS = if IS_MOBILE then 2 else 3

--[=[
	@class ShopController
	Client-side shop UI. Builds UI programmatically with category tabs, item grid,
	and purchase flow. Touch-friendly and gamepad-navigable.
]=]
local ShopController = Knit.CreateController({
	Name = "ShopController",
})

ShopController._trove = Trove.new()
ShopController._isOpen = false
ShopController._selectedCategory = nil :: string?
ShopController._shopGui = nil :: ScreenGui?
ShopController._itemsFrame = nil :: Frame?
ShopController._currencyLabels = {} :: { [string]: TextLabel }
ShopController._categoryButtons = {} :: { [string]: TextButton }

-- ============================================================================
-- UI Construction
-- ============================================================================

local function createTextSize(): number
	if IS_CONSOLE then
		return 24
	elseif IS_MOBILE then
		return 16
	end
	return 18
end

local function createInstance<T>(className: string, props: { [string]: any }): T
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst :: any
end

function ShopController:_buildUI()
	local textSize = createTextSize()

	-- Main ScreenGui
	local gui = createInstance("ScreenGui", {
		Name = "ShopGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = PlayerGui,
	}) :: ScreenGui
	self._shopGui = gui

	-- Background overlay
	local overlay = createInstance("Frame", {
		Name = "Overlay",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = gui,
	}) :: Frame

	-- Main container
	local container = createInstance("Frame", {
		Name = "Container",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if IS_MOBILE then UDim2.fromScale(0.95, 0.9) else UDim2.fromScale(0.7, 0.8),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		Parent = gui,
	}) :: Frame
	createInstance("UICorner", { CornerRadius = UDim.new(0, 12), Parent = container })

	-- Header with title and currency
	local header = createInstance("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Color3.fromRGB(40, 40, 55),
		Parent = container,
	}) :: Frame
	createInstance("UICorner", { CornerRadius = UDim.new(0, 12), Parent = header })

	createInstance("TextLabel", {
		Name = "Title",
		Text = "Shop",
		Font = Enum.Font.GothamBold,
		TextSize = textSize + 4,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, 100, 1, 0),
		Position = UDim2.new(0, 16, 0, 0),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	-- Currency display
	local currencyFrame = createInstance("Frame", {
		Name = "Currencies",
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
		Parent = header,
	}) :: Frame
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
		Parent = currencyFrame,
	})

	-- Build currency labels sorted by display order
	local sortedCurrencies = {}
	for name, def in ShopConfig.Currencies do
		table.insert(sortedCurrencies, { name = name, def = def })
	end
	table.sort(sortedCurrencies, function(a, b)
		return a.def.DisplayOrder < b.def.DisplayOrder
	end)

	for _, entry in sortedCurrencies do
		local label = createInstance("TextLabel", {
			Name = entry.name,
			Text = `{entry.def.Name}: 0`,
			Font = Enum.Font.GothamMedium,
			TextSize = textSize,
			TextColor3 = Color3.fromRGB(255, 215, 0),
			Size = UDim2.new(0, 120, 1, 0),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = currencyFrame,
		}) :: TextLabel
		self._currencyLabels[entry.name] = label
	end

	-- Close button
	local closeBtn = createInstance("TextButton", {
		Name = "Close",
		Text = "X",
		Font = Enum.Font.GothamBold,
		TextSize = textSize + 2,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, math.max(BUTTON_MIN_SIZE, 40), 0, math.max(BUTTON_MIN_SIZE, 40)),
		Position = UDim2.new(1, -50, 0, 5),
		BackgroundColor3 = Color3.fromRGB(180, 50, 50),
		Parent = header,
	}) :: TextButton
	createInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = closeBtn })

	self._trove:Connect(closeBtn.Activated, function()
		self:Close()
	end)

	-- Dismiss by clicking overlay
	self._trove:Connect((overlay :: any).InputBegan, function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self:Close()
		end
	end)

	-- Category tabs
	local tabFrame = createInstance("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, math.max(BUTTON_MIN_SIZE, 40)),
		Position = UDim2.new(0, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = container,
	}) :: Frame
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = tabFrame,
	})

	for _, category in ShopConfig.CategoryOrder do
		local tabBtn = createInstance("TextButton", {
			Name = category,
			Text = category,
			Font = Enum.Font.GothamMedium,
			TextSize = textSize - 2,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(0, math.max(90, BUTTON_MIN_SIZE * 2), 0, math.max(BUTTON_MIN_SIZE, 36)),
			BackgroundColor3 = Color3.fromRGB(50, 50, 65),
			Parent = tabFrame,
		}) :: TextButton
		createInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = tabBtn })

		self._categoryButtons[category] = tabBtn
		self._trove:Connect(tabBtn.Activated, function()
			self:_selectCategory(category)
		end)
	end

	-- Items scroll frame
	local itemsScroll = createInstance("ScrollingFrame", {
		Name = "Items",
		Size = UDim2.new(1, -16, 1, -102),
		Position = UDim2.new(0, 8, 0, 96),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = container,
	}) :: ScrollingFrame
	createInstance("UIGridLayout", {
		CellSize = UDim2.new(1 / GRID_COLUMNS, -8, 0, if IS_MOBILE then 120 else 150),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = itemsScroll,
	})
	self._itemsFrame = itemsScroll :: any

	-- Select first category
	if #ShopConfig.CategoryOrder > 0 then
		self:_selectCategory(ShopConfig.CategoryOrder[1])
	end
end

function ShopController:_selectCategory(category: string)
	self._selectedCategory = category

	-- Update tab highlights
	for cat, btn in self._categoryButtons do
		btn.BackgroundColor3 = if cat == category then Color3.fromRGB(80, 80, 200) else Color3.fromRGB(50, 50, 65)
	end

	-- Populate items
	self:_populateItems(category)
end

function ShopController:_populateItems(category: string)
	local itemsFrame = self._itemsFrame
	if not itemsFrame then
		return
	end

	-- Clear existing items
	for _, child in itemsFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local items = ShopConfig.ItemsByCategory[category]
	if not items then
		return
	end

	local textSize = createTextSize()
	local ShopService = Knit.GetService("ShopService")

	for i, item in items do
		local card = createInstance("Frame", {
			Name = item.Id,
			BackgroundColor3 = Color3.fromRGB(45, 45, 60),
			LayoutOrder = i,
			Parent = itemsFrame,
		}) :: Frame
		createInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = card })

		createInstance("TextLabel", {
			Name = "Name",
			Text = item.Name,
			Font = Enum.Font.GothamBold,
			TextSize = textSize,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.new(0, 4, 0, 4),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
		})

		createInstance("TextLabel", {
			Name = "Description",
			Text = item.Description,
			Font = Enum.Font.Gotham,
			TextSize = textSize - 4,
			TextColor3 = Color3.fromRGB(180, 180, 180),
			Size = UDim2.new(1, -8, 0, 36),
			Position = UDim2.new(0, 4, 0, 28),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Parent = card,
		})

		local buyBtn = createInstance("TextButton", {
			Name = "Buy",
			Text = `{item.Price} {item.Currency}`,
			Font = Enum.Font.GothamBold,
			TextSize = textSize - 2,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, -16, 0, math.max(BUTTON_MIN_SIZE, 36)),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			BackgroundColor3 = Color3.fromRGB(60, 160, 60),
			Parent = card,
		}) :: TextButton
		createInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = buyBtn })

		self._trove:Connect(buyBtn.Activated, function()
			self:_promptPurchase(item, buyBtn, ShopService)
		end)
	end
end

function ShopController:_promptPurchase(item: ShopConfig.ShopItem, buyBtn: TextButton, ShopService: any)
	local originalText = buyBtn.Text
	buyBtn.Text = "Confirm?"
	buyBtn.BackgroundColor3 = Color3.fromRGB(200, 160, 30)

	-- Wait for second tap to confirm or revert after 3s
	local confirmed = false
	local connection: RBXScriptConnection?

	local function reset()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		buyBtn.Text = originalText
		buyBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 60)
	end

	connection = buyBtn.Activated:Connect(function()
		if confirmed then
			return
		end
		confirmed = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		buyBtn.Text = "..."
		buyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

		task.spawn(function()
			local ok, result = ShopService:PurchaseItem(item.Id):await()
			if ok then
				local success, message = result[1], result[2]
				if success then
					buyBtn.Text = "Owned!"
					buyBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 60)
				else
					buyBtn.Text = message or "Failed"
					buyBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
				end
			else
				buyBtn.Text = "Error"
				buyBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
			end
			task.wait(1.5)
			reset()
		end)
	end)

	-- Auto-revert after 3 seconds if not confirmed
	task.delay(3, function()
		if not confirmed then
			reset()
		end
	end)
end

-- ============================================================================
-- Currency Updates
-- ============================================================================

function ShopController:_updateCurrencyDisplay(currencyName: string, amount: number)
	local label = self._currencyLabels[currencyName]
	if label then
		local def = ShopConfig.Currencies[currencyName]
		label.Text = `{def and def.Name or currencyName}: {amount}`
	end
end

function ShopController:_refreshAllCurrencies()
	local ShopService = Knit.GetService("ShopService")
	for currencyName, _ in ShopConfig.Currencies do
		task.spawn(function()
			local ok, amount = ShopService:GetCurrency(currencyName):await()
			if ok then
				self:_updateCurrencyDisplay(currencyName, amount)
			end
		end)
	end
end

-- ============================================================================
-- Open / Close
-- ============================================================================

function ShopController:Open()
	if self._isOpen then
		return
	end
	self._isOpen = true
	if self._shopGui then
		self._shopGui.Enabled = true
	end
	self:_refreshAllCurrencies()
end

function ShopController:Close()
	if not self._isOpen then
		return
	end
	self._isOpen = false
	if self._shopGui then
		self._shopGui.Enabled = false
	end
end

function ShopController:Toggle()
	if self._isOpen then
		self:Close()
	else
		self:Open()
	end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function ShopController:KnitInit()
	self:_buildUI()
end

function ShopController:KnitStart()
	local ShopService = Knit.GetService("ShopService")

	-- Listen for currency changes
	ShopService.CurrencyChanged:Connect(function(currencyName: string, newAmount: number)
		self:_updateCurrencyDisplay(currencyName, newAmount)
	end)

	-- Listen for purchase confirmations
	ShopService.ItemPurchased:Connect(function(_itemId: string)
		self:_refreshAllCurrencies()
	end)

	-- Keybind: B to toggle shop
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			self:Toggle()
		end
		-- Gamepad: Y button
		if input.KeyCode == Enum.KeyCode.ButtonY then
			self:Toggle()
		end
	end)
end

return ShopController
