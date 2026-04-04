--!strict

local BlockType = require(script.Parent.Enums.BlockType)

export type OreConfig = {
	blockType: number,
	chance: number,
	veinSize: { min: number, max: number },
	veinsPerChunk: number,
}

export type DepthLayer = {
	name: string,
	minDepth: number, -- in studs (positive = deeper)
	maxDepth: number,
	primaryBlock: number,
	secondaryBlock: number?,
	surfaceBlock: number?, -- used only for the topmost layer
	subsurfaceBlock: number?, -- block directly under surface
	ores: { OreConfig },
	eggChance: number, -- chance of an egg node per chunk in this layer
}

local BiomeConfig = {}

-- Define all biome surfaces
BiomeConfig.Biomes = {
	paper_fields = {
		name = "Paper Fields",
		surfaceBlock = BlockType.PaperGrass,
		subsurfaceBlock = BlockType.Paper,
		fillerBlock = BlockType.Cardboard,
		structureType = "tree",
		treeDensity = 0.05,
		trunkHeightMin = 3,
		trunkHeightMax = 5,
		canopyRadius = 2,
		trunkBlock = BlockType.Wood,
		canopyBlock = BlockType.Leaves,
	},
	sunset_mesa = {
		name = "Sunset Mesa",
		surfaceBlock = BlockType.Sandstone,
		subsurfaceBlock = BlockType.RedClay,
		fillerBlock = BlockType.Cardboard,
		structureType = "tree",
		treeDensity = 0.04,
		trunkHeightMin = 3,
		trunkHeightMax = 5,
		canopyRadius = 1,
		trunkBlock = BlockType.SandstoneTan,
		canopyBlock = BlockType.WarmPinkTop,
		terrainFrequency = 0.004,
		maxElevationBlocks = 15,
		terrainOctaves = 2,
		terrainSmoothingRadius = 1,
		caveThreshold = 0.65,
		treeDensityMultiplier = 0.3,
	},
	neon_mushrooms = {
		name = "Neon Mushrooms",
		surfaceBlock = BlockType.CoralPlate,
		subsurfaceBlock = BlockType.ReefRock,
		fillerBlock = BlockType.CoralFiller,
		structureType = "mushroom",
		treeDensity = 0.04,
		trunkHeightMin = 2,
		trunkHeightMax = 3,
		canopyRadius = 3,
		trunkBlock = BlockType.CoralTrunk,
		canopyBlock = BlockType.CoralCanopy,
		terrainFrequency = 0.005,
		maxElevationBlocks = 25,
		terrainOctaves = 2,
		terrainSmoothingRadius = 2,
		caveThreshold = 0.48,
		treeDensityMultiplier = 1.0,
	},
}

-- Keep BiomeConfig.Surface pointing to paper_fields for backwards compatibility
BiomeConfig.Surface = BiomeConfig.Biomes.paper_fields

-- Sector assignments
local SECTOR_BIOMES = {
	"paper_fields",
}
local SECTOR_COUNT = #SECTOR_BIOMES

-- Returns the biome config for a given world position (in studs)
function BiomeConfig.getBiome(wx: number, wz: number)
	if SECTOR_COUNT == 1 then
		return BiomeConfig.Biomes[SECTOR_BIOMES[1]]
	end

	-- Angle-based sector
	local angle = math.atan2(wx, wz)
	if angle < 0 then
		angle = angle + math.pi * 2
	end
	local sectorIndex = math.floor(angle / (math.pi * 2 / SECTOR_COUNT)) + 1
	sectorIndex = math.clamp(sectorIndex, 1, SECTOR_COUNT)

	return BiomeConfig.Biomes[SECTOR_BIOMES[sectorIndex]]
end

-- Helper: get biome for a chunk coordinate
function BiomeConfig.getBiomeForChunk(cx: number, cz: number)
	local CHUNK_STUDS = 80
	local wx = cx * CHUNK_STUDS + CHUNK_STUDS / 2
	local wz = cz * CHUNK_STUDS + CHUNK_STUDS / 2
	return BiomeConfig.getBiome(wx, wz)
end

-- 7 depth layers (depth measured in studs below surface, positive = deeper)
BiomeConfig.DepthLayers = {
	-- Layer 1: Paper Fields
	{
		name = "Paper Fields",
		minDepth = 0,
		maxDepth = 80,
		primaryBlock = BlockType.Paper,
		secondaryBlock = BlockType.Cardboard,
		surfaceBlock = BlockType.PaperGrass,
		subsurfaceBlock = BlockType.Paper,
		ores = {
			{ blockType = BlockType.DriedPulp, chance = 0.05, veinSize = { min = 3, max = 6 }, veinsPerChunk = 3 },
		},
		eggChance = 0,
	} :: DepthLayer,

	-- Layer 2: Pulp Caverns
	{
		name = "Pulp Caverns",
		minDepth = 80,
		maxDepth = 240,
		primaryBlock = BlockType.CompressedPulp,
		secondaryBlock = BlockType.Clay,
		ores = {
			{ blockType = BlockType.RecycledFiber, chance = 0.04, veinSize = { min = 3, max = 5 }, veinsPerChunk = 3 },
			{ blockType = BlockType.PulpOre, chance = 0.02, veinSize = { min = 2, max = 4 }, veinsPerChunk = 2 },
		},
		eggChance = 0.01,
	} :: DepthLayer,

	-- Layer 3: Fold Tunnels
	{
		name = "Fold Tunnels",
		minDepth = 240,
		maxDepth = 480,
		primaryBlock = BlockType.FoldedStone,
		secondaryBlock = BlockType.InkStone,
		ores = {
			{ blockType = BlockType.PaperQuartz, chance = 0.03, veinSize = { min = 2, max = 5 }, veinsPerChunk = 3 },
			{ blockType = BlockType.PaperCrystal, chance = 0.015, veinSize = { min = 1, max = 3 }, veinsPerChunk = 2 },
		},
		eggChance = 0.02,
	} :: DepthLayer,

	-- Layer 4: Origami Depths
	{
		name = "Origami Depths",
		minDepth = 480,
		maxDepth = 800,
		primaryBlock = BlockType.OrigamiRock,
		secondaryBlock = BlockType.GemFragment,
		ores = {
			{ blockType = BlockType.FoilOre, chance = 0.02, veinSize = { min = 2, max = 4 }, veinsPerChunk = 2 },
			{ blockType = BlockType.RubyPaper, chance = 0.01, veinSize = { min = 1, max = 3 }, veinsPerChunk = 1 },
		},
		eggChance = 0.03,
	} :: DepthLayer,

	-- Layer 5: Crystal Lattice
	{
		name = "Crystal Lattice",
		minDepth = 800,
		maxDepth = 1200,
		primaryBlock = BlockType.CrystalBlock,
		secondaryBlock = BlockType.FoilSheet,
		ores = {
			{ blockType = BlockType.MetalOrigami, chance = 0.02, veinSize = { min = 2, max = 4 }, veinsPerChunk = 2 },
			{ blockType = BlockType.SapphireCrystal, chance = 0.01, veinSize = { min = 1, max = 3 }, veinsPerChunk = 1 },
		},
		eggChance = 0.04,
	} :: DepthLayer,

	-- Layer 6: Void Seams
	{
		name = "Void Seams",
		minDepth = 1200,
		maxDepth = 1600,
		primaryBlock = BlockType.VoidStone,
		secondaryBlock = BlockType.DarkPaper,
		ores = {
			{ blockType = BlockType.ShadowFold, chance = 0.015, veinSize = { min = 1, max = 3 }, veinsPerChunk = 2 },
			{ blockType = BlockType.VoidCrystal, chance = 0.008, veinSize = { min = 1, max = 2 }, veinsPerChunk = 1 },
		},
		eggChance = 0.05,
	} :: DepthLayer,

	-- Layer 7: The Core
	{
		name = "The Core",
		minDepth = 1600,
		maxDepth = 2000,
		primaryBlock = BlockType.PrismaticBlock,
		secondaryBlock = BlockType.CoreFragment,
		ores = {
			{ blockType = BlockType.RainbowPaper, chance = 0.01, veinSize = { min = 1, max = 2 }, veinsPerChunk = 1 },
		},
		eggChance = 0.08,
	} :: DepthLayer,
}

function BiomeConfig.getDepthLayer(depth: number): DepthLayer
	if depth < 80 then
		return BiomeConfig.DepthLayers[1]
	elseif depth < 240 then
		return BiomeConfig.DepthLayers[2]
	elseif depth < 480 then
		return BiomeConfig.DepthLayers[3]
	elseif depth < 800 then
		return BiomeConfig.DepthLayers[4]
	elseif depth < 1200 then
		return BiomeConfig.DepthLayers[5]
	elseif depth < 1600 then
		return BiomeConfig.DepthLayers[6]
	else
		return BiomeConfig.DepthLayers[7]
	end
end

return BiomeConfig
