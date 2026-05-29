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

	-- Analytics / Milestones + funnels (MilestoneService).
	-- Milestones: one-shot First* flags, keyed by milestone name -> true.
	-- Funnels.Onboarding: monotonic step index for the 10-minute-hook funnel
	-- (1 SpawnedIn -> 2 BlockMined -> 3 OreFound -> 4 CraftStarted ->
	-- 5 CraftClaimed). No retention funnel — Roblox tracks retention natively.
	Milestones: { [string]: boolean },
	Funnels: { Onboarding: number },

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
	MiningInventory: {
		bulk: { [string]: number },
		ore: { [string]: number },
		tools: { [string]: number },
		misc: { [string]: number },
	},
	EquippedTool: string,
	BlocksMined: number,
	DepthReached: number,

	-- Region ownership (Phase 2). OwnedRegionId is "" when unclaimed
	-- (sentinel — PlayerDataService:Write asserts non-nil values).
	-- RegionHomePoint is meaningful only when OwnedRegionId ~= "".
	OwnedRegionId: string,
	RegionHomePoint: { x: number, y: number, z: number },

	-- Surface Plots — DEPRECATED in Phase 2. PlotService no longer registers
	-- with Knit; the field is retained orphaned to avoid a profile schema bump.
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

	Milestones = {},
	Funnels = { Onboarding = 0 },

	ProcessedReceipts = {},

	GiftsGiven = 0,
	GiftsReceived = 0,

	PendingEggs = {},
	HatchedCreatures = {},

	SavedEmotes = {},

	MiningInventory = { bulk = {}, ore = {}, tools = {}, misc = {} },
	EquippedTool = "paper_hands",
	BlocksMined = 0,
	DepthReached = 0,

	OwnedRegionId = "",
	RegionHomePoint = { x = 0, y = 0, z = 0 },

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
