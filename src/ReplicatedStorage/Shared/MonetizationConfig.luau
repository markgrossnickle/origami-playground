--!strict
--[=[
	@class MonetizationConfig
	Shared configuration for GamePasses, Developer Products, and Daily Login Rewards.
	Update these tables with real IDs when forking the template.
]=]

export type GamePassEntry = {
	Id: number,
	Name: string,
}

export type DevProductEntry = {
	Id: number,
	Name: string,
	Handler: string,
}

export type DailyReward = {
	Type: string,
	Currency: string?,
	Amount: number?,
	ItemId: string?,
	Description: string,
}

-- Map pass names to GamePass IDs. Update IDs for your game.
local GamePasses: { [string]: GamePassEntry } = {
	VIP = { Id = 0, Name = "VIP" },
	DoubleCoins = { Id = 0, Name = "Double Coins" },
	AutoFarm = { Id = 0, Name = "Auto Farm" },
}

-- Map product names to Developer Product IDs + handler function names.
-- Handler is the name of a method on MonetizationService that processes the receipt.
local DevProducts: { [string]: DevProductEntry } = {
	["100Coins"] = { Id = 0, Name = "100 Coins", Handler = "_handleCoinProduct" },
	["500Coins"] = { Id = 0, Name = "500 Coins", Handler = "_handleCoinProduct" },
	["1000Coins"] = { Id = 0, Name = "1000 Coins", Handler = "_handleCoinProduct" },
	VIPBoost = { Id = 0, Name = "VIP Boost (1hr)", Handler = "_handleBoostProduct" },
}

-- Coin amounts for dev products (used by _handleCoinProduct)
local DevProductCoinAmounts: { [string]: number } = {
	["100Coins"] = 100,
	["500Coins"] = 500,
	["1000Coins"] = 1000,
}

-- Daily login rewards (7-day cycle, repeats)
local DailyRewards: { DailyReward } = {
	{ Type = "Currency", Currency = "Coins", Amount = 50, Description = "50 Coins" },
	{ Type = "Currency", Currency = "Coins", Amount = 75, Description = "75 Coins" },
	{ Type = "Currency", Currency = "Coins", Amount = 100, Description = "100 Coins" },
	{ Type = "Currency", Currency = "Coins", Amount = 150, Description = "150 Coins" },
	{ Type = "Currency", Currency = "Coins", Amount = 200, Description = "200 Coins" },
	{ Type = "Currency", Currency = "Coins", Amount = 300, Description = "300 Coins" },
	{ Type = "Currency", Currency = "Gems", Amount = 10, Description = "10 Gems" },
}

-- Premium membership multiplier for currency earnings
local PremiumMultiplier = 1.5

return {
	GamePasses = GamePasses,
	DevProducts = DevProducts,
	DevProductCoinAmounts = DevProductCoinAmounts,
	DailyRewards = DailyRewards,
	PremiumMultiplier = PremiumMultiplier,
}
