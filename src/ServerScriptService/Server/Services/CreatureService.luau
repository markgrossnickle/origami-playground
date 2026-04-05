--[[
	CreatureService — structured creature data wrapper around HatchedCreatures.
	Provides AddCreature, GetCreatures, ReleaseCreature, RenameCreature, SpawnCreature.
	Transparently migrates old raw modelData entries to full CreatureData on first read.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local EggCraftingConfig = require(ReplicatedStorage.Shared.EggCraftingConfig)

local CreatureService = Knit.CreateService({
	Name = "CreatureService",
	Client = {
		CreatureAdded = Knit.CreateSignal(), -- (creatureData)
		CreatureRemoved = Knit.CreateSignal(), -- (creatureId)
	},
})

export type CreatureData = {
	id: string,
	name: string,
	modelData: { [string]: any },
	rarity: string,
	stats: { hp: number, atk: number, def: number, spd: number },
	source: string, -- "crafted" | "bred"
	parentRecipeId: string?,
	parent1Id: string?,
	parent2Id: string?,
	createdAt: number,
	breedCooldownUntil: number?,
}

local function generateId(): string
	return HttpService:GenerateGUID(false)
end

-- Migrate a raw modelData entry (old format) to full CreatureData
local function migrateEntry(raw: any): CreatureData
	-- Already migrated
	if type(raw) == "table" and raw.id and raw.modelData then
		return raw :: CreatureData
	end
	-- Old format: raw IS the modelData directly
	return {
		id = generateId(),
		name = if type(raw) == "table" and raw.name then raw.name else "Creature",
		modelData = raw,
		rarity = "Common",
		stats = { hp = 50, atk = 8, def = 5, spd = 10 },
		source = "bred",
		createdAt = os.time(),
	}
end

-- Read and migrate all creatures for a player
local function getCreatureList(player: Player): { CreatureData }
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end

	local raw = data.HatchedCreatures or {}
	local migrated = false
	local creatures: { CreatureData } = {}

	for i, entry in ipairs(raw) do
		local creature = migrateEntry(entry)
		if creature ~= entry then
			raw[i] = creature
			migrated = true
		end
		table.insert(creatures, creature)
	end

	if migrated then
		PlayerDataService:Write(player, { "HatchedCreatures" }, raw)
	end

	return creatures
end

--- Add a new creature to the player's collection. Returns the CreatureData.
function CreatureService:AddCreature(
	player: Player,
	data: {
		name: string?,
		modelData: { [string]: any },
		rarity: string?,
		stats: { hp: number, atk: number, def: number, spd: number }?,
		source: string?,
		parentRecipeId: string?,
		parent1Id: string?,
		parent2Id: string?,
	}
): CreatureData
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local pdata = PlayerDataService:Read(player)
	if not pdata then
		error("Player data not loaded")
	end

	local creature: CreatureData = {
		id = generateId(),
		name = data.name or (data.modelData and data.modelData.name) or "Creature",
		modelData = data.modelData,
		rarity = data.rarity or "Common",
		stats = data.stats or { hp = 50, atk = 8, def = 5, spd = 10 },
		source = data.source or "crafted",
		parentRecipeId = data.parentRecipeId,
		parent1Id = data.parent1Id,
		parent2Id = data.parent2Id,
		createdAt = os.time(),
	}

	local hatched = pdata.HatchedCreatures or {}
	table.insert(hatched, creature)
	PlayerDataService:Write(player, { "HatchedCreatures" }, hatched)

	self.Client.CreatureAdded:Fire(player, creature)
	return creature
end

--- Get all creatures for a player.
function CreatureService.Client:GetCreatures(player: Player): { CreatureData }
	return getCreatureList(player)
end

--- Release (delete) a creature by ID.
function CreatureService.Client:ReleaseCreature(player: Player, creatureId: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local hatched = data.HatchedCreatures or {}
	for i, entry in ipairs(hatched) do
		local creature = migrateEntry(entry)
		if creature.id == creatureId then
			table.remove(hatched, i)
			PlayerDataService:Write(player, { "HatchedCreatures" }, hatched)
			CreatureService.Client.CreatureRemoved:Fire(player, creatureId)
			return { success = true }
		end
	end
	return { success = false, error = "Creature not found" }
end

--- Rename a creature by ID.
function CreatureService.Client:RenameCreature(player: Player, creatureId: string, newName: string)
	if #newName < 1 or #newName > 30 then
		return { success = false, error = "Name must be 1-30 characters" }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local hatched = data.HatchedCreatures or {}
	for i, entry in ipairs(hatched) do
		local creature = migrateEntry(entry)
		if creature.id == creatureId then
			creature.name = newName
			hatched[i] = creature
			PlayerDataService:Write(player, { "HatchedCreatures" }, hatched)
			return { success = true, name = newName }
		end
	end
	return { success = false, error = "Creature not found" }
end

--- Get a single creature by ID.
function CreatureService:GetCreatureById(player: Player, creatureId: string): CreatureData?
	local creatures = getCreatureList(player)
	for _, creature in ipairs(creatures) do
		if creature.id == creatureId then
			return creature
		end
	end
	return nil
end

--- Check if a creature can breed (cooldown check).
function CreatureService:CanBreed(player: Player, creatureId: string): (boolean, number?)
	local creature = self:GetCreatureById(player, creatureId)
	if not creature then
		return false, nil
	end
	local now = os.time()
	if creature.breedCooldownUntil and now < creature.breedCooldownUntil then
		return false, creature.breedCooldownUntil - now
	end
	return true, nil
end

--- Set breed cooldown on a creature.
function CreatureService:SetBreedCooldown(player: Player, creatureId: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return
	end

	local hatched = data.HatchedCreatures or {}
	for i, entry in ipairs(hatched) do
		local creature = migrateEntry(entry)
		if creature.id == creatureId then
			creature.breedCooldownUntil = os.time() + EggCraftingConfig.BREED_COOLDOWN
			hatched[i] = creature
			PlayerDataService:Write(player, { "HatchedCreatures" }, hatched)
			return
		end
	end
end

function CreatureService:KnitInit() end
function CreatureService:KnitStart() end

return CreatureService
