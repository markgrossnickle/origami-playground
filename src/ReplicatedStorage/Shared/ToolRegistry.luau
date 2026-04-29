--!strict

type ToolConfig = {
	id: string,
	name: string,
	power: number,
	speed: number,
	reach: number,
	tier: number,
	cost: number?,
	craftRecipe: { [string]: number }?,
}

local ToolRegistry = {}

local tools: { [string]: ToolConfig } = {
	paper_hands = {
		id = "paper_hands",
		name = "Paper Hands",
		power = 1,
		speed = 2,
		reach = 24,
		tier = 0,
	},
	cardboard_pick = {
		id = "cardboard_pick",
		name = "Cardboard Pick",
		power = 2,
		speed = 2.5,
		reach = 28,
		tier = 1,
		craftRecipe = { paper = 20 },
	},
	stone_pick = {
		id = "stone_pick",
		name = "Stone Pick",
		power = 4,
		speed = 3,
		reach = 32,
		tier = 2,
		craftRecipe = { folded_stone = 20, pulp = 10 },
	},
	crystal_pick = {
		id = "crystal_pick",
		name = "Crystal Pick",
		power = 8,
		speed = 3.5,
		reach = 36,
		tier = 3,
		craftRecipe = { crystal = 10, origami_rock = 15 },
	},
	void_pick = {
		id = "void_pick",
		name = "Void Pick",
		power = 15,
		speed = 4,
		reach = 40,
		tier = 4,
		craftRecipe = { void_stone = 10, crystal = 5 },
	},
	prismatic_pick = {
		id = "prismatic_pick",
		name = "Prismatic Pick",
		power = 25,
		speed = 4.5,
		reach = 44,
		tier = 5,
		craftRecipe = { prismatic_block = 5, void_stone = 10 },
	},
}

-- Ordered list of tool IDs by tier for UI display
ToolRegistry.TierOrder = {
	"paper_hands",
	"cardboard_pick",
	"stone_pick",
	"crystal_pick",
	"void_pick",
	"prismatic_pick",
}

function ToolRegistry.get(toolId: string): ToolConfig?
	return tools[toolId]
end

function ToolRegistry.getDefault(): ToolConfig
	return tools.paper_hands
end

function ToolRegistry.getAllTools(): { [string]: ToolConfig }
	return tools
end

function ToolRegistry.canCraft(toolId: string, inventory: { [string]: number }): boolean
	local tool = tools[toolId]
	if not tool or not tool.craftRecipe then
		return false
	end
	for itemId, needed in tool.craftRecipe do
		local have = inventory[itemId] or 0
		if have < needed then
			return false
		end
	end
	return true
end

return ToolRegistry
