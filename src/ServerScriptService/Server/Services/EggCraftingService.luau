--[[
	EggCraftingService — craft creature eggs from mining materials.
	Validates recipe, deducts materials from MiningInventory, calls OrigamiService for LLM creature data,
	creates PendingEgg entry (shared with breeding eggs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local EggCraftingConfig = require(ReplicatedStorage.Shared.EggCraftingConfig)

local EggCraftingService = Knit.CreateService({
	Name = "EggCraftingService",
	Client = {
		EggCrafted = Knit.CreateSignal(), -- (recipeId, eggIndex)
	},
})

local MAX_EGGS = 3 -- crafted eggs allow more slots than breeding alone

-- Get available recipes and whether the player can afford each.
function EggCraftingService.Client:GetRecipes(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end

	local inv = data.MiningInventory or {}
	local recipes = {}
	for _, recipe in ipairs(EggCraftingConfig.RECIPES) do
		local mats = {}
		local canCraft = true
		for _, mat in ipairs(recipe.materials) do
			local have = inv[mat.itemId] or 0
			table.insert(mats, { itemId = mat.itemId, need = mat.count, have = have })
			if have < mat.count then
				canCraft = false
			end
		end
		table.insert(recipes, {
			id = recipe.id,
			rarity = recipe.rarity,
			displayName = recipe.displayName,
			hatchTime = recipe.hatchTime,
			baseStats = recipe.baseStats,
			eggColor = recipe.eggColor,
			materials = mats,
			canCraft = canCraft,
		})
	end
	return recipes
end

-- Craft an egg from a recipe.
function EggCraftingService.Client:CraftEgg(player: Player, recipeId: string)
	local recipe = EggCraftingConfig.getRecipeById(recipeId)
	if not recipe then
		return { success = false, error = "Invalid recipe" }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	-- Check egg capacity
	if #(data.PendingEggs or {}) >= MAX_EGGS then
		return { success = false, error = "No egg slots available (max " .. MAX_EGGS .. ")" }
	end

	-- Check materials
	local inv = data.MiningInventory or {}
	for _, mat in ipairs(recipe.materials) do
		if (inv[mat.itemId] or 0) < mat.count then
			return { success = false, error = "Not enough " .. mat.itemId:gsub("_", " ") }
		end
	end

	-- Deduct materials
	for _, mat in ipairs(recipe.materials) do
		local current = PlayerDataService:Read(player, { "MiningInventory", mat.itemId }) or 0
		PlayerDataService:Write(player, { "MiningInventory", mat.itemId }, current - mat.count)
	end

	-- Build LLM prompt from recipe theme
	local prompt = string.format(
		"Create a %s-rarity creature: %s. "
			.. "Make it unique with interesting features. It should be small to medium sized. Category: creature.",
		recipe.rarity:lower(),
		recipe.theme
	)

	-- Call OrigamiService for creature model data
	local OrigamiService = Knit.GetService("OrigamiService")
	local result = OrigamiService.Client:RequestModel(player, prompt, "creature", "lowpoly")

	local offspringData = nil
	if result and result.success and result.model then
		offspringData = result.model
	end

	-- Create PendingEgg (same format as breeding eggs so BreedingController can display them)
	local hatchTime = os.time() + recipe.hatchTime
	local egg = {
		parent1Name = recipe.displayName,
		parent2Name = recipe.rarity,
		hatchTime = hatchTime,
		offspringData = offspringData, -- nil if LLM failed; will retry on hatch
		breedPrompt = prompt,
		style = "lowpoly",
		-- Crafted egg extra fields
		source = "crafted",
		recipeId = recipe.id,
		rarity = recipe.rarity,
		baseStats = recipe.baseStats,
		eggColor = recipe.eggColor,
	}

	local eggs = data.PendingEggs or {}
	table.insert(eggs, egg)
	PlayerDataService:Write(player, { "PendingEggs" }, eggs)

	local eggIndex = #eggs
	self.EggCrafted:Fire(player, recipeId, eggIndex)

	return {
		success = true,
		eggIndex = eggIndex,
		hatchTime = hatchTime,
		rarity = recipe.rarity,
		displayName = recipe.displayName,
	}
end

function EggCraftingService:KnitInit() end
function EggCraftingService:KnitStart() end

return EggCraftingService
