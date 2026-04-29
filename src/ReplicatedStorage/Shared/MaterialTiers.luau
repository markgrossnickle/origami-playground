--!strict
--[[
	MaterialTiers — single source of truth for the layer × bulk × ore × tier mapping.
	Phase 1: exposes canonical layer→item mapping and helpers for routing drops.
]]

local MaterialTiers = {}

export type LayerTier = {
	layerIndex: number,
	layerName: string,
	tierName: string,
	bulkItemId: string,
	oreItemId: string,
}

MaterialTiers.Layers = {
	{
		layerIndex = 1,
		layerName = "Paper Fields",
		tierName = "Common",
		bulkItemId = "paper",
		oreItemId = "inkdrop",
	},
	{
		layerIndex = 2,
		layerName = "Pulp Caverns",
		tierName = "Uncommon",
		bulkItemId = "pulp",
		oreItemId = "clay_bead",
	},
	{
		layerIndex = 3,
		layerName = "Fold Tunnels",
		tierName = "Standard",
		bulkItemId = "folded_stone",
		oreItemId = "quartz",
	},
	{
		layerIndex = 4,
		layerName = "Origami Depths",
		tierName = "Premium",
		bulkItemId = "origami_rock",
		oreItemId = "gem_fragment",
	},
	{
		layerIndex = 5,
		layerName = "Crystal Lattice",
		tierName = "Metallic",
		bulkItemId = "crystal",
		oreItemId = "foil_shard",
	},
	{
		layerIndex = 6,
		layerName = "Void Seams",
		tierName = "Mythic",
		bulkItemId = "void_stone",
		oreItemId = "shadow_wisp",
	},
	{
		layerIndex = 7,
		layerName = "The Core",
		tierName = "Master",
		bulkItemId = "prismatic_block",
		oreItemId = "prism_core",
	},
} :: { LayerTier }

local BULK_IDS: { [string]: number } = {}
local ORE_IDS: { [string]: number } = {}
for _, layer in MaterialTiers.Layers do
	BULK_IDS[layer.bulkItemId] = layer.layerIndex
	ORE_IDS[layer.oreItemId] = layer.layerIndex
end

MaterialTiers.BulkOrder = {}
MaterialTiers.OreOrder = {}
for _, layer in MaterialTiers.Layers do
	table.insert(MaterialTiers.BulkOrder, layer.bulkItemId)
	table.insert(MaterialTiers.OreOrder, layer.oreItemId)
end

function MaterialTiers.getRole(itemId: string): string?
	if BULK_IDS[itemId] then
		return "bulk"
	end
	if ORE_IDS[itemId] then
		return "ore"
	end
	return nil
end

function MaterialTiers.isBulk(itemId: string): boolean
	return BULK_IDS[itemId] ~= nil
end

function MaterialTiers.isOre(itemId: string): boolean
	return ORE_IDS[itemId] ~= nil
end

function MaterialTiers.getLayerForItem(itemId: string): LayerTier?
	local idx = BULK_IDS[itemId] or ORE_IDS[itemId]
	if idx then
		return MaterialTiers.Layers[idx]
	end
	return nil
end

function MaterialTiers.getLayer(layerIndex: number): LayerTier?
	return MaterialTiers.Layers[layerIndex]
end

return MaterialTiers
