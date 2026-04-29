--!strict
--[[
	TerrainMaterialMap
	Maps BlockType IDs to Roblox Terrain Enum.Material values.
	Returns nil for blocks that should NOT be rendered as terrain (Air, special blocks).
	Origami Expedition palette: warm paper tones surface, cool crystals deep.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local TerrainMaterialMap = {}

local materialMap: { [number]: Enum.Material } = {
	-- Layer 1: Paper Fields
	[BlockType.PaperGrass] = Enum.Material.Grass,
	[BlockType.Paper] = Enum.Material.Sand, -- closest to smooth paper
	[BlockType.Cardboard] = Enum.Material.Ground,
	[BlockType.InkdropOre] = Enum.Material.Ground,

	-- Layer 2: Pulp Caverns
	[BlockType.Pulp] = Enum.Material.Ground,
	[BlockType.ClayBeadOre] = Enum.Material.Mud,
	[BlockType.RecycledFiber] = Enum.Material.Ground,
	[BlockType.PulpOre] = Enum.Material.Rock,

	-- Layer 3: Fold Tunnels
	[BlockType.FoldedStone] = Enum.Material.Slate,
	[BlockType.QuartzOre] = Enum.Material.Salt,
	[BlockType.PaperCrystal] = Enum.Material.Salt,
	[BlockType.InkStone] = Enum.Material.Slate,

	-- Layer 4: Origami Depths
	[BlockType.OrigamiRock] = Enum.Material.Rock,
	[BlockType.GemFragmentOre] = Enum.Material.Rock,
	[BlockType.FoilOre] = Enum.Material.Rock,
	[BlockType.RubyPaper] = Enum.Material.Rock,

	-- Layer 5: Crystal Lattice
	[BlockType.Crystal] = Enum.Material.Salt,
	[BlockType.FoilShardOre] = Enum.Material.Rock,
	[BlockType.MetalOrigami] = Enum.Material.Rock,
	[BlockType.SapphireCrystal] = Enum.Material.Salt,

	-- Layer 6: Void Seams
	[BlockType.VoidStone] = Enum.Material.Basalt,
	[BlockType.DarkPaper] = Enum.Material.Basalt,
	[BlockType.ShadowWispOre] = Enum.Material.Basalt,
	[BlockType.VoidCrystal] = Enum.Material.Basalt,

	-- Layer 7: The Core
	[BlockType.PrismaticBlock] = Enum.Material.Salt,
	[BlockType.PrismCoreOre] = Enum.Material.Salt,
	[BlockType.RainbowPaper] = Enum.Material.Salt,

	-- Special
	[BlockType.EggNode] = Enum.Material.Salt,
	[BlockType.Bedrock] = Enum.Material.Basalt,
}

function TerrainMaterialMap.getMaterial(blockTypeId: number): Enum.Material?
	return materialMap[blockTypeId]
end

return TerrainMaterialMap
