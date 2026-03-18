--!strict
--[=[
	@class PlayerData
	@server
]=]

export type PlayerData = {
	-- Currencies
	Folds: number,
	Cranes: number,

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

	-- Prosocial: Gifting
	GiftsGiven: number,
	GiftsReceived: number,

	-- Prosocial: Breeding
	PendingEggs: { any },
	HatchedCreatures: { any },

	-- Prosocial: Emotes
	SavedEmotes: { any },

	-- Prosocial: Co-op TD
	CoopTDWins: number,
	CoopTDHighestWave: number,
}

local playerDataTemplate: PlayerData = {
	Folds = 0,
	Cranes = 0,

	Inventory = {},

	LoginStreak = 0,
	LastLoginDate = "",
	LastLoginRewardClaimed = false,

	FirstJoinDate = "",
	TotalPlayTime = 0,
	SessionCount = 0,
	LastSessionStart = 0,

	ProcessedReceipts = {},

	GiftsGiven = 0,
	GiftsReceived = 0,

	PendingEggs = {},
	HatchedCreatures = {},

	SavedEmotes = {},

	CoopTDWins = 0,
	CoopTDHighestWave = 0,
}

return playerDataTemplate
