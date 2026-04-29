--[[
	WorkshopConfig — recipes for crafting accessories, tools, costumes, and props from mining materials.
	24 recipes across 4 item types and 6 rarity tiers. Each item is LLM-generated from player prompts.
]]

local EggCraftingConfig = require(script.Parent.EggCraftingConfig)

local WorkshopConfig = {}

-- Re-export rarity system from EggCraftingConfig
WorkshopConfig.RARITY_ORDER = EggCraftingConfig.RARITY_ORDER
WorkshopConfig.RARITY_COLORS = EggCraftingConfig.RARITY_COLORS
WorkshopConfig.RARITY_INDEX = EggCraftingConfig.RARITY_INDEX

-- Item types
export type ItemType = "accessory" | "tool" | "costume" | "prop"

WorkshopConfig.ITEM_TYPES = { "accessory", "tool", "costume", "prop" }

WorkshopConfig.ITEM_TYPE_DISPLAY = {
	accessory = "Accessories",
	tool = "Tools",
	costume = "Costumes",
	prop = "Props",
}

-- Attachment points for accessories
WorkshopConfig.ATTACH_POINTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"RightUpperArm",
	"LeftUpperArm",
	"RightFoot",
	"LeftFoot",
}

-- Limits
WorkshopConfig.MAX_PENDING_CRAFTS = 3
WorkshopConfig.MAX_CRAFTED_ITEMS = 50

export type WorkshopRecipe = {
	id: string,
	itemType: ItemType,
	rarity: string,
	displayName: string,
	theme: string,
	materials: { { itemId: string, count: number } },
	craftTime: number, -- seconds
	attachPoint: string?, -- accessories only
	toolStats: { damage: number, speed: number, range: number }?, -- tools only
	placementSize: { x: number, y: number, z: number }?, -- props only
}

WorkshopConfig.RECIPES = {
	-- ═══════════════════════════════
	-- ACCESSORIES (6 recipes)
	-- ═══════════════════════════════
	{
		id = "acc_common",
		itemType = "accessory",
		rarity = "Common",
		displayName = "Paper Hat",
		theme = "a simple folded paper hat — lightweight, papery texture, soft white or cream colors",
		materials = {
			{ itemId = "paper", count = 8 },
			{ itemId = "inkdrop", count = 2 },
		},
		craftTime = 20 * 60, -- 20 minutes
		attachPoint = "Head",
	},
	{
		id = "acc_uncommon",
		itemType = "accessory",
		rarity = "Uncommon",
		displayName = "Pulp Shoulder Pad",
		theme = "a sturdy shoulder pad made from compressed pulp — earthy tones, layered fibrous texture",
		materials = {
			{ itemId = "pulp", count = 8 },
			{ itemId = "clay_bead", count = 4 },
		},
		craftTime = 45 * 60, -- 45 minutes
		attachPoint = "RightUpperArm",
	},
	{
		id = "acc_rare",
		itemType = "accessory",
		rarity = "Rare",
		displayName = "Crystal Circlet",
		theme = "an elegant circlet with crystalline gems — blue and white shimmer, geometric facets",
		materials = {
			{ itemId = "folded_stone", count = 8 },
			{ itemId = "quartz", count = 5 },
		},
		craftTime = 90 * 60, -- 1.5 hours
		attachPoint = "Head",
	},
	{
		id = "acc_epic",
		itemType = "accessory",
		rarity = "Epic",
		displayName = "Gem-Studded Belt",
		theme = "an ornate belt studded with glowing gems — purple and gold accents, intricate origami folds",
		materials = {
			{ itemId = "crystal", count = 8 },
			{ itemId = "gem_fragment", count = 5 },
		},
		craftTime = 3 * 60 * 60, -- 3 hours
		attachPoint = "LowerTorso",
	},
	{
		id = "acc_legendary",
		itemType = "accessory",
		rarity = "Legendary",
		displayName = "Void Halo",
		theme = "a floating dark halo with void energy cracks — shadowy with glowing purple fissures, ominous aura",
		materials = {
			{ itemId = "void_stone", count = 8 },
			{ itemId = "shadow_wisp", count = 5 },
		},
		craftTime = 6 * 60 * 60, -- 6 hours
		attachPoint = "Head",
	},
	{
		id = "acc_mythic",
		itemType = "accessory",
		rarity = "Mythic",
		displayName = "Prismatic Wings",
		theme = "radiant wings that shift through rainbow colors — prismatic crystal feathers, ethereal glow",
		materials = {
			{ itemId = "prismatic_block", count = 5 },
			{ itemId = "prism_core", count = 3 },
		},
		craftTime = 10 * 60 * 60, -- 10 hours
		attachPoint = "UpperTorso",
	},

	-- ═══════════════════════════════
	-- TOOLS (6 recipes)
	-- ═══════════════════════════════
	{
		id = "tool_common",
		itemType = "tool",
		rarity = "Common",
		displayName = "Paper Wand",
		theme = "a simple rolled-paper wand — light, papery, slightly bent tip with faint glow",
		materials = {
			{ itemId = "paper", count = 10 },
			{ itemId = "inkdrop", count = 3 },
		},
		craftTime = 25 * 60, -- 25 minutes
		toolStats = { damage = 5, speed = 1.2, range = 8 },
	},
	{
		id = "tool_uncommon",
		itemType = "tool",
		rarity = "Uncommon",
		displayName = "Pulp Mace",
		theme = "a dense mace made from hardened pulp and clay — earthy brown, heavy spiked head",
		materials = {
			{ itemId = "pulp", count = 10 },
			{ itemId = "clay_bead", count = 6 },
		},
		craftTime = 50 * 60, -- 50 minutes
		toolStats = { damage = 10, speed = 0.9, range = 6 },
	},
	{
		id = "tool_rare",
		itemType = "tool",
		rarity = "Rare",
		displayName = "Folded Blade",
		theme = "a sharp blade folded from stone and quartz — geometric edges, crystalline blue sheen",
		materials = {
			{ itemId = "folded_stone", count = 10 },
			{ itemId = "quartz", count = 6 },
		},
		craftTime = 2 * 60 * 60, -- 2 hours
		toolStats = { damage = 18, speed = 1.1, range = 7 },
	},
	{
		id = "tool_epic",
		itemType = "tool",
		rarity = "Epic",
		displayName = "Crystal Staff",
		theme = "an elegant staff topped with a glowing crystal orb — purple energy tendrils, intricate handle",
		materials = {
			{ itemId = "crystal", count = 10 },
			{ itemId = "gem_fragment", count = 6 },
		},
		craftTime = 5 * 60 * 60, -- 5 hours
		toolStats = { damage = 28, speed = 1.0, range = 12 },
	},
	{
		id = "tool_legendary",
		itemType = "tool",
		rarity = "Legendary",
		displayName = "Void Scythe",
		theme = "a fearsome scythe dripping with void energy — dark blade, glowing purple edge, shadow wisps",
		materials = {
			{ itemId = "void_stone", count = 10 },
			{ itemId = "shadow_wisp", count = 6 },
		},
		craftTime = 8 * 60 * 60, -- 8 hours
		toolStats = { damage = 40, speed = 0.8, range = 10 },
	},
	{
		id = "tool_mythic",
		itemType = "tool",
		rarity = "Mythic",
		displayName = "Prismatic Scepter",
		theme = "a legendary scepter radiating rainbow energy — shifting prismatic crystal head, golden handle",
		materials = {
			{ itemId = "prismatic_block", count = 5 },
			{ itemId = "prism_core", count = 5 },
		},
		craftTime = 12 * 60 * 60, -- 12 hours
		toolStats = { damage = 55, speed = 1.0, range = 14 },
	},

	-- ═══════════════════════════════
	-- COSTUMES (5 recipes, Uncommon→Mythic)
	-- ═══════════════════════════════
	{
		id = "costume_uncommon",
		itemType = "costume",
		rarity = "Uncommon",
		displayName = "Pulp Outfit",
		theme = "a full-body outfit made from layered compressed pulp — earthy explorer look, fibrous texture",
		materials = {
			{ itemId = "pulp", count = 15 },
			{ itemId = "clay_bead", count = 8 },
		},
		craftTime = 30 * 60, -- 30 minutes
	},
	{
		id = "costume_rare",
		itemType = "costume",
		rarity = "Rare",
		displayName = "Crystal Armor",
		theme = "crystalline body armor with quartz plating — blue shimmer, geometric faceted plates",
		materials = {
			{ itemId = "folded_stone", count = 15 },
			{ itemId = "quartz", count = 8 },
		},
		craftTime = 2 * 60 * 60, -- 2 hours
	},
	{
		id = "costume_epic",
		itemType = "costume",
		rarity = "Epic",
		displayName = "Gem Knight Suit",
		theme = "a full knight suit studded with glowing gems — purple and gold plates, regal origami patterns",
		materials = {
			{ itemId = "crystal", count = 15 },
			{ itemId = "gem_fragment", count = 8 },
		},
		craftTime = 6 * 60 * 60, -- 6 hours
	},
	{
		id = "costume_legendary",
		itemType = "costume",
		rarity = "Legendary",
		displayName = "Void Wraith",
		theme = "a shadowy wraith costume with void energy — dark flowing robes, glowing void cracks, ethereal",
		materials = {
			{ itemId = "void_stone", count = 15 },
			{ itemId = "shadow_wisp", count = 8 },
		},
		craftTime = 10 * 60 * 60, -- 10 hours
	},
	{
		id = "costume_mythic",
		itemType = "costume",
		rarity = "Mythic",
		displayName = "Prismatic Avatar",
		theme = "a legendary full-body transformation — rainbow shifting energy form, radiant prismatic glow",
		materials = {
			{ itemId = "prismatic_block", count = 8 },
			{ itemId = "prism_core", count = 5 },
		},
		craftTime = 14 * 60 * 60, -- 14 hours
	},

	-- ═══════════════════════════════
	-- PROPS (5 recipes, Common→Legendary)
	-- ═══════════════════════════════
	{
		id = "prop_common",
		itemType = "prop",
		rarity = "Common",
		displayName = "Paper Decoration",
		theme = "a small folded paper decoration — origami flower or simple shape, white and pastel colors",
		materials = {
			{ itemId = "paper", count = 6 },
			{ itemId = "inkdrop", count = 2 },
		},
		craftTime = 15 * 60, -- 15 minutes
		placementSize = { x = 3, y = 3, z = 3 },
	},
	{
		id = "prop_uncommon",
		itemType = "prop",
		rarity = "Uncommon",
		displayName = "Clay Statue",
		theme = "a small clay and pulp statue — earthy tones, hand-sculpted look, rustic charm",
		materials = {
			{ itemId = "pulp", count = 8 },
			{ itemId = "clay_bead", count = 5 },
		},
		craftTime = 40 * 60, -- 40 minutes
		placementSize = { x = 4, y = 6, z = 4 },
	},
	{
		id = "prop_rare",
		itemType = "prop",
		rarity = "Rare",
		displayName = "Crystal Fountain",
		theme = "a decorative fountain with crystal water effects — blue quartz basin, shimmering water",
		materials = {
			{ itemId = "folded_stone", count = 10 },
			{ itemId = "quartz", count = 6 },
		},
		craftTime = 2 * 60 * 60, -- 2 hours
		placementSize = { x = 6, y = 5, z = 6 },
	},
	{
		id = "prop_epic",
		itemType = "prop",
		rarity = "Epic",
		displayName = "Gem Totem",
		theme = "a glowing totem pillar with embedded gems — purple energy veins, ancient origami carvings",
		materials = {
			{ itemId = "crystal", count = 10 },
			{ itemId = "gem_fragment", count = 6 },
		},
		craftTime = 5 * 60 * 60, -- 5 hours
		placementSize = { x = 4, y = 10, z = 4 },
	},
	{
		id = "prop_legendary",
		itemType = "prop",
		rarity = "Legendary",
		displayName = "Prismatic Shrine",
		theme = "a radiant shrine pulsing with prismatic energy — rainbow crystal spires, ethereal glow",
		materials = {
			{ itemId = "prismatic_block", count = 4 },
			{ itemId = "prism_core", count = 3 },
		},
		craftTime = 10 * 60 * 60, -- 10 hours
		placementSize = { x = 8, y = 8, z = 8 },
	},
} :: { WorkshopRecipe }

-- Build lookup maps
local _recipeMap: { [string]: WorkshopRecipe } = {}
local _recipesByType: { [string]: { WorkshopRecipe } } = {}

for _, recipe in ipairs(WorkshopConfig.RECIPES) do
	_recipeMap[recipe.id] = recipe
	if not _recipesByType[recipe.itemType] then
		_recipesByType[recipe.itemType] = {}
	end
	table.insert(_recipesByType[recipe.itemType], recipe)
end

function WorkshopConfig.getRecipeById(recipeId: string): WorkshopRecipe?
	return _recipeMap[recipeId]
end

function WorkshopConfig.getRecipesByType(itemType: ItemType): { WorkshopRecipe }
	return _recipesByType[itemType] or {}
end

local function _resolveCount(miningInventory: any, itemId: string): number
	if type(miningInventory) ~= "table" then
		return 0
	end
	if miningInventory.bulk or miningInventory.ore or miningInventory.misc or miningInventory.tools then
		local bulk = (miningInventory.bulk and miningInventory.bulk[itemId]) or 0
		local ore = (miningInventory.ore and miningInventory.ore[itemId]) or 0
		local misc = (miningInventory.misc and miningInventory.misc[itemId]) or 0
		return bulk + ore + misc
	end
	return miningInventory[itemId] or 0
end

function WorkshopConfig.canCraft(recipeId: string, miningInventory: any): boolean
	local recipe = _recipeMap[recipeId]
	if not recipe then
		return false
	end
	for _, mat in ipairs(recipe.materials) do
		if _resolveCount(miningInventory, mat.itemId) < mat.count then
			return false
		end
	end
	return true
end

return WorkshopConfig
