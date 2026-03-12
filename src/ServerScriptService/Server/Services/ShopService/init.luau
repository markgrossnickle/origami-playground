--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ShopConfig = require(ReplicatedStorage.Shared.ShopConfig)

local PlayerDataService
local AnalyticsService
local MonetizationService

--[=[
	@class ShopService
	Reusable shop framework with category-based browsing, multiple currencies, and purchase validation.
]=]
local ShopService = Knit.CreateService({
	Name = "ShopService",
	ItemPurchased = Signal.new(), -- (player: Player, itemId: string)
	Client = {
		ItemPurchased = Knit.CreateSignal(), -- (itemId: string)
		CurrencyChanged = Knit.CreateSignal(), -- (currencyName: string, newAmount: number)
	},
})

-- ============================================================================
-- Currency Management
-- ============================================================================

function ShopService:GetCurrency(player: Player, currencyName: string): number
	return PlayerDataService:Read(player, { currencyName }) or 0
end

function ShopService:AddCurrency(player: Player, currencyName: string, amount: number)
	if amount <= 0 then
		return
	end
	local current = self:GetCurrency(player, currencyName)
	local newAmount = current + amount

	-- Apply premium multiplier for earnings
	if MonetizationService and MonetizationService:IsPremium(player) then
		local multiplier = MonetizationService:GetPremiumMultiplier()
		newAmount = current + math.floor(amount * multiplier)
	end

	PlayerDataService:Write(player, { currencyName }, newAmount)
	self.Client.CurrencyChanged:Fire(player, currencyName, newAmount)

	if AnalyticsService then
		AnalyticsService:TrackEconomy(player, currencyName, amount, "Source", "ShopService_AddCurrency")
	end
end

function ShopService:SpendCurrency(player: Player, currencyName: string, amount: number): boolean
	if amount <= 0 then
		return false
	end
	local current = self:GetCurrency(player, currencyName)
	if current < amount then
		return false
	end
	local newAmount = current - amount
	PlayerDataService:Write(player, { currencyName }, newAmount)
	self.Client.CurrencyChanged:Fire(player, currencyName, newAmount)
	return true
end

-- ============================================================================
-- Shop Operations
-- ============================================================================

function ShopService:GetShopItems(): { ShopConfig.ShopItem }
	return ShopConfig.Items
end

function ShopService:GetInventory(player: Player): { [string]: number }
	return PlayerDataService:Read(player, { "Inventory" }) or {}
end

function ShopService:CanAfford(player: Player, itemId: string): boolean
	local item = ShopConfig.ItemsById[itemId]
	if not item then
		return false
	end
	local current = self:GetCurrency(player, item.Currency)
	return current >= item.Price
end

function ShopService:PurchaseItem(player: Player, itemId: string): (boolean, string)
	local item = ShopConfig.ItemsById[itemId]
	if not item then
		return false, "Item not found"
	end

	-- Check one-time purchase
	if item.OneTimePurchase then
		local inventory = self:GetInventory(player)
		if inventory[itemId] and inventory[itemId] > 0 then
			return false, "Already owned"
		end
	end

	-- Check currency
	if not self:CanAfford(player, itemId) then
		return false, "Not enough " .. item.Currency
	end

	-- Deduct currency
	local spent = self:SpendCurrency(player, item.Currency, item.Price)
	if not spent then
		return false, "Transaction failed"
	end

	-- Grant item
	local inventory = PlayerDataService:Read(player, { "Inventory" }) or {}
	inventory[itemId] = (inventory[itemId] or 0) + 1
	PlayerDataService:Write(player, { "Inventory" }, inventory)

	-- Fire signals
	self.ItemPurchased:Fire(player, itemId)
	self.Client.ItemPurchased:Fire(player, itemId)

	-- Track analytics
	if AnalyticsService then
		AnalyticsService:ItemPurchased(player, itemId, item.Currency, item.Price)
	end

	return true, "Success"
end

-- ============================================================================
-- Client API
-- ============================================================================

function ShopService.Client:GetShopItems(_player: Player)
	return self.Server:GetShopItems()
end

function ShopService.Client:GetInventory(player: Player)
	return self.Server:GetInventory(player)
end

function ShopService.Client:GetCurrency(player: Player, currencyName: string)
	return self.Server:GetCurrency(player, currencyName)
end

function ShopService.Client:CanAfford(player: Player, itemId: string)
	return self.Server:CanAfford(player, itemId)
end

function ShopService.Client:PurchaseItem(player: Player, itemId: string)
	return self.Server:PurchaseItem(player, itemId)
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function ShopService:KnitInit()
	PlayerDataService = Knit.GetService("PlayerDataService")
	AnalyticsService = Knit.GetService("AnalyticsService")
	MonetizationService = Knit.GetService("MonetizationService")

	Players.PlayerRemoving:Connect(function(_player: Player)
		-- Cleanup handled by PlayerDataService
	end)
end

function ShopService:KnitStart() end

return ShopService
