--!strict
--[=[
	@class ShopConfig
	Shared configuration for the in-game shop.
	Define all purchasable items, categories, and currencies here.
	Both server (ShopService) and client (ShopController) read from this config.
]=]

export type ShopItem = {
	Id: string,
	Name: string,
	Category: string,
	Price: number,
	Currency: string,
	Icon: string,
	Description: string,
	OneTimePurchase: boolean,
}

export type CurrencyDefinition = {
	Name: string,
	Icon: string,
	DisplayOrder: number,
}

-- Supported currencies. Add new currencies here.
local Currencies: { [string]: CurrencyDefinition } = {
	Coins = { Name = "Coins", Icon = "rbxassetid://0", DisplayOrder = 1 },
	Gems = { Name = "Gems", Icon = "rbxassetid://0", DisplayOrder = 2 },
}

-- Category display order for the shop UI
local CategoryOrder: { string } = {
	"Boosts",
	"Items",
	"Cosmetics",
	"Pets",
}

-- All shop items. Add your game's items here.
local Items: { ShopItem } = {
	{
		Id = "speed_boost",
		Name = "Speed Boost",
		Category = "Boosts",
		Price = 100,
		Currency = "Coins",
		Icon = "rbxassetid://0",
		Description = "2x speed for 60 seconds",
		OneTimePurchase = false,
	},
	{
		Id = "double_xp",
		Name = "Double XP",
		Category = "Boosts",
		Price = 200,
		Currency = "Coins",
		Icon = "rbxassetid://0",
		Description = "2x XP for 5 minutes",
		OneTimePurchase = false,
	},
	{
		Id = "starter_pack",
		Name = "Starter Pack",
		Category = "Items",
		Price = 5,
		Currency = "Gems",
		Icon = "rbxassetid://0",
		Description = "A pack of useful starter items",
		OneTimePurchase = true,
	},
}

-- Build lookup table by Id
local ItemsById: { [string]: ShopItem } = {}
for _, item in Items do
	ItemsById[item.Id] = item
end

-- Build items grouped by category
local ItemsByCategory: { [string]: { ShopItem } } = {}
for _, item in Items do
	if not ItemsByCategory[item.Category] then
		ItemsByCategory[item.Category] = {}
	end
	table.insert(ItemsByCategory[item.Category], item)
end

return {
	Currencies = Currencies,
	CategoryOrder = CategoryOrder,
	Items = Items,
	ItemsById = ItemsById,
	ItemsByCategory = ItemsByCategory,
}
