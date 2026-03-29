--!strict

export type BlockType = number

return {
	-- Core
	Air = 0,
	Bedrock = 255,

	-- Paper Fields (Layer 1: 0 to -80 studs depth)
	PaperGrass = 1,
	Paper = 2,
	Cardboard = 3,
	DriedPulp = 4,

	-- Pulp Caverns (Layer 2: -80 to -240)
	CompressedPulp = 10,
	Clay = 11,
	RecycledFiber = 12,
	PulpOre = 13,

	-- Fold Tunnels (Layer 3: -240 to -480)
	FoldedStone = 20,
	PaperQuartz = 21,
	PaperCrystal = 22,
	InkStone = 23,

	-- Origami Depths (Layer 4: -480 to -800)
	OrigamiRock = 30,
	GemFragment = 31,
	FoilOre = 32,
	RubyPaper = 33,

	-- Crystal Lattice (Layer 5: -800 to -1200)
	CrystalBlock = 40,
	FoilSheet = 41,
	MetalOrigami = 42,
	SapphireCrystal = 43,

	-- Void Seams (Layer 6: -1200 to -1600)
	VoidStone = 50,
	DarkPaper = 51,
	ShadowFold = 52,
	VoidCrystal = 53,

	-- The Core (Layer 7: -1600 to -2000)
	PrismaticBlock = 60,
	CoreFragment = 61,
	RainbowPaper = 62,

	-- Surface nature
	Wood = 100,
	Leaves = 101,

	-- Egg nodes (rare, found underground)
	EggNode = 200,
}
