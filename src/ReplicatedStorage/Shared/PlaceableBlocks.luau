--!strict
--[[
	PlaceableBlocks — single source of truth for which inventory items are
	placeable in the voxel world, and how they look in the hotbar/backpack
	UIs. Replaces PlotConfig.PLACEABLE_BLOCKS (deprecated in Phase 2).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local MaterialTiers = require(ReplicatedStorage.Shared.MaterialTiers)

local PlaceableBlocks = {}

export type PlaceableInfo = {
	color: { number },
	material: string,
	name: string,
}

PlaceableBlocks.PLACEABLE_ITEMS = {
	paper = { color = { 255, 250, 235 }, material = "SmoothPlastic", name = "Paper" },
	pulp = { color = { 160, 140, 110 }, material = "Ground", name = "Pulp" },
	folded_stone = { color = { 140, 145, 155 }, material = "Slate", name = "Folded Stone" },
	origami_rock = { color = { 120, 100, 130 }, material = "Granite", name = "Origami Rock" },
	crystal = { color = { 150, 200, 255 }, material = "Glass", name = "Crystal" },
	void_stone = { color = { 25, 15, 40 }, material = "Basalt", name = "Void Stone" },
	prismatic_block = { color = { 255, 200, 255 }, material = "Neon", name = "Prismatic Block" },
	wood = { color = { 140, 100, 60 }, material = "Wood", name = "Wood" },
} :: { [string]: PlaceableInfo }

PlaceableBlocks.ITEM_TO_BLOCK = {
	paper = BlockType.Paper,
	pulp = BlockType.Pulp,
	folded_stone = BlockType.FoldedStone,
	origami_rock = BlockType.OrigamiRock,
	crystal = BlockType.Crystal,
	void_stone = BlockType.VoidStone,
	prismatic_block = BlockType.PrismaticBlock,
	wood = BlockType.Wood,
} :: { [string]: number }

for _, layer in MaterialTiers.Layers do
	if PlaceableBlocks.PLACEABLE_ITEMS[layer.bulkItemId] == nil then
		warn(
			string.format(
				"[PlaceableBlocks] missing PLACEABLE_ITEMS entry for bulk %q (layer %d)",
				layer.bulkItemId,
				layer.layerIndex
			)
		)
	end
end

function PlaceableBlocks.isPlaceable(itemId: string): boolean
	return PlaceableBlocks.PLACEABLE_ITEMS[itemId] ~= nil
end

function PlaceableBlocks.getInfo(itemId: string): PlaceableInfo?
	return PlaceableBlocks.PLACEABLE_ITEMS[itemId]
end

function PlaceableBlocks.getBlockType(itemId: string): number?
	return PlaceableBlocks.ITEM_TO_BLOCK[itemId]
end

return PlaceableBlocks
