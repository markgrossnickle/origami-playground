--!strict
--[=[
	@class PlayerData
	@server
]=]

export type PlayerData = {
	-- Currencies
	Coins: number,
	Gems: number,

	-- Shop / Inventory
	Inventory: { [string]: number },

	-- Daily Login Rewards
	LoginStreak: number,
	LastLoginDate: string,
	LastLoginRewardClaimed: boolean,

	-- Analytics / Session tracking
	FirstJoinDate: string,
	TotalPlayTime: number,
	SessionCount: number,
	LastSessionStart: number,

	-- Monetization: processed receipt IDs to prevent double-processing
	ProcessedReceipts: { [string]: boolean },
}

local playerDataTemplate: PlayerData = {
	Coins = 0,
	Gems = 0,

	Inventory = {},

	LoginStreak = 0,
	LastLoginDate = "",
	LastLoginRewardClaimed = false,

	FirstJoinDate = "",
	TotalPlayTime = 0,
	SessionCount = 0,
	LastSessionStart = 0,

	ProcessedReceipts = {},
}

return playerDataTemplate
