--[[
	EggCraftingConfig — egg recipes mapping mining materials → creature eggs with rarity tiers.
	6 recipes, one per major depth tier. Each defines materials, hatch time, base stats, and LLM theme.
]]

local EggCraftingConfig = {}

export type EggRecipe = {
	id: string,
	rarity: string,
	displayName: string,
	theme: string, -- LLM prompt context for creature generation
	materials: { { itemId: string, count: number } },
	hatchTime: number, -- seconds
	baseStats: { hp: number, atk: number, def: number, spd: number },
	eggColor: { number },
}

-- Rarity ordering (lowest → highest)
EggCraftingConfig.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

EggCraftingConfig.RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(100, 200, 100),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 40),
	Mythic = Color3.fromRGB(255, 60, 120),
}

EggCraftingConfig.RARITY_INDEX = {}
for i, r in ipairs(EggCraftingConfig.RARITY_ORDER) do
	EggCraftingConfig.RARITY_INDEX[r] = i
end

-- Breed cooldown (used by Phase 3)
EggCraftingConfig.BREED_COOLDOWN = 4 * 60 * 60 -- 4 hours in seconds

-- Mutation chance for breeding (Phase 3)
EggCraftingConfig.MUTATION_CHANCE = 0.05
EggCraftingConfig.MUTATION_STAT_SCALE = 1.2

EggCraftingConfig.RECIPES = {
	{
		id = "egg_common",
		rarity = "Common",
		displayName = "Paper Egg",
		theme = "a small, simple paper creature from shallow fields — papery texture, light colors, gentle demeanor",
		materials = {
			{ itemId = "paper_scrap", count = 10 },
			{ itemId = "cardboard", count = 5 },
		},
		hatchTime = 30 * 60, -- 30 minutes
		baseStats = { hp = 50, atk = 8, def = 5, spd = 10 },
		eggColor = { 200, 200, 190 },
	},
	{
		id = "egg_uncommon",
		rarity = "Uncommon",
		displayName = "Pulp Egg",
		theme = "a sturdy creature from underground pulp caverns — dense fibrous body, earthy tones, burrowing abilities",
		materials = {
			{ itemId = "compressed_pulp", count = 10 },
			{ itemId = "clay_chunk", count = 5 },
		},
		hatchTime = 60 * 60, -- 1 hour
		baseStats = { hp = 70, atk = 12, def = 10, spd = 8 },
		eggColor = { 180, 150, 110 },
	},
	{
		id = "egg_rare",
		rarity = "Rare",
		displayName = "Folded Egg",
		theme = "an elegant creature from deep fold tunnels — intricate folded geometry, crystalline accents, agile",
		materials = {
			{ itemId = "folded_stone", count = 10 },
			{ itemId = "quartz_shard", count = 5 },
		},
		hatchTime = 2 * 60 * 60, -- 2 hours
		baseStats = { hp = 90, atk = 18, def = 15, spd = 14 },
		eggColor = { 140, 160, 220 },
	},
	{
		id = "egg_epic",
		rarity = "Epic",
		displayName = "Crystal Egg",
		theme = "a powerful creature from the crystal lattice depths — glowing crystalline body, neon accents, fierce",
		materials = {
			{ itemId = "crystal_shard", count = 10 },
			{ itemId = "gem_fragment", count = 5 },
		},
		hatchTime = 4 * 60 * 60, -- 4 hours
		baseStats = { hp = 120, atk = 25, def = 20, spd = 18 },
		eggColor = { 180, 100, 240 },
	},
	{
		id = "egg_legendary",
		rarity = "Legendary",
		displayName = "Void Egg",
		theme = "a fearsome creature from the void seams — dark shadowy body with glowing void cracks, intimidating aura",
		materials = {
			{ itemId = "void_stone", count = 10 },
			{ itemId = "shadow_fold", count = 5 },
		},
		hatchTime = 8 * 60 * 60, -- 8 hours
		baseStats = { hp = 160, atk = 35, def = 28, spd = 22 },
		eggColor = { 60, 40, 80 },
	},
	{
		id = "egg_mythic",
		rarity = "Mythic",
		displayName = "Prismatic Egg",
		theme = "a legendary prismatic creature from the core — rainbow shifting colors, radiant energy, awe-inspiring",
		materials = {
			{ itemId = "prismatic_shard", count = 5 },
			{ itemId = "core_fragment", count = 5 },
		},
		hatchTime = 12 * 60 * 60, -- 12 hours
		baseStats = { hp = 200, atk = 45, def = 35, spd = 28 },
		eggColor = { 255, 200, 255 },
	},
} :: { EggRecipe }

local _recipeMap: { [string]: EggRecipe } = {}
for _, recipe in ipairs(EggCraftingConfig.RECIPES) do
	_recipeMap[recipe.id] = recipe
end

function EggCraftingConfig.getRecipeById(recipeId: string): EggRecipe?
	return _recipeMap[recipeId]
end

function EggCraftingConfig.canCraft(recipeId: string, miningInventory: { [string]: number }): boolean
	local recipe = _recipeMap[recipeId]
	if not recipe then
		return false
	end
	for _, mat in ipairs(recipe.materials) do
		if (miningInventory[mat.itemId] or 0) < mat.count then
			return false
		end
	end
	return true
end

return EggCraftingConfig
