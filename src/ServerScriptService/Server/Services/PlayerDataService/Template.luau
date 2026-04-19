--!strict
--[=[
	@class PlayerData
	@server
]=]

export type PlayerData = {
	-- Currencies
	Folds: number,
	Cranes: number,
	Paper: number, -- Paper Tokens for Workshop (FL 2.5 Lite) creations

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

	-- Mining / Expedition
	MiningInventory: { [string]: number },
	EquippedTool: string,
	BlocksMined: number,
	DepthReached: number,

	-- Surface Plots
	PlotData: {
		plotIndex: number, -- -1 = unclaimed
		placedBlocks: { [string]: string }, -- "x,y,z" = materialItemId
		assignedCreatures: { { creatureId: string, localX: number, localZ: number } },
	},

	-- Workshop Crafting
	PendingCrafts: { any }, -- workshop craft queue (max 3)
	CraftedItems: { any }, -- completed items collection (max 50)
	Equipped: { accessory: string?, tool: string?, costume: string? },
	PlacedProps: { { itemId: string, localX: number, localY: number, localZ: number } },
}

local playerDataTemplate: PlayerData = {
	Folds = 0,
	Cranes = 0,
	Paper = 3, -- New players start with 3 Paper Tokens

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

	MiningInventory = {},
	EquippedTool = "prismatic_pick", -- DEBUG: best tool for testing
	BlocksMined = 0,
	DepthReached = 0,

	PlotData = {
		plotIndex = -1,
		placedBlocks = {},
		assignedCreatures = {},
	},

	PendingCrafts = {},
	CraftedItems = {},
	Equipped = {},
	PlacedProps = {},
}

return playerDataTemplate
