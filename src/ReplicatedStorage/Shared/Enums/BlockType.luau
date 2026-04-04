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

	-- Fairy World biome (surface) — lilac mushroom grove
	FairyMoss = 102,
	EnchantedSoil = 103,
	FairyFiller = 104,
	FairyTrunk = 105,
	FairyCanopy = 106,

	-- Fairy Glade biome (surface) — golden sunlit clearing
	GladeGrass = 107,
	GladeSoil = 108,
	GladeTrunk = 109,
	GladeCanopy = 144,

	-- Fairy Hollow biome (surface) — deep twilight blue
	HollowMoss = 145,
	HollowSoil = 146,
	HollowTrunk = 147,
	HollowCanopy = 148,

	-- Clockwork biome (surface)
	CorrugatedCardboard = 110,
	DarkCardboard = 111,
	CopperGear = 112,
	BrassLeaf = 113,

	-- Neon Reef biome (surface)
	CoralPlate = 150,
	ReefRock = 151,
	CoralFiller = 152,
	CoralTrunk = 153,
	CoralCanopy = 154,
	OrangeAccent = 155,

	-- Crystal Bloom biome (surface)
	CrystalGround = 170,
	RoseQuartz = 171,
	CitrineTrunk = 172,
	AquamarineCanopy = 173,
	DiamondAccent = 174,

	-- Sunset Mesa biome (surface)
	Sandstone = 180, -- burnt orange sandstone
	RedClay = 181, -- dusty red clay subsurface
	SandstoneTan = 182, -- sandstone tan cactus trunk
	WarmPinkTop = 183, -- warm pink cactus top
	DeepPurpleAccent = 184, -- deep purple accent

	-- Frozen Auroras biome (surface)
	GlacierIce = 190,
	MintFrost = 191,
	IceWhiteTrunk = 192,
	AuroraVioletCanopy = 193,
	DeepIndigo = 194,

	-- Egg nodes (rare, found underground)
	EggNode = 200,

	-- Confetti Carnival biome (surface)
	PartyPaper = 201,
	GoldPaper = 202,
	PinataWood = 203,
	PinataLeaves = 204,
	ConfettiFiller = 205,

	-- Ink River biome (surface)
	ScrollParchment = 120,
	AgedPaper = 121,
	InkBrushTrunk = 122,
	InkSplatterLeaf = 123,

	-- Paste Waterfalls biome (surface)
	PapierMache = 130,
	NewspaperGray = 131,
	PasteDripTrunk = 132,
	PasteDripLeaf = 133,

	-- Balloon Chambers biome (surface)
	BalloonRed = 140,
	NewspaperLayer = 141,
	BalloonString = 142,
	BalloonTop = 143,

	-- Ember Wastes biome (surface)
	VolcanicRock = 160,
	AshStone = 161,
	ScorchedBase = 162,
	BasaltColumn = 163,
	MoltenCap = 164,
	CrimsonVein = 165,

	-- Pulp Nebula biome (surface)
	CosmicPaper = 210,
	StellarDust = 211,
	SatelliteTrunk = 212,
	CyanCanopy = 213,
	NebulaFiller = 214,

	-- Mosaic Bazaar biome (surface)
	TurquoiseTile = 215,
	TerracottaClay = 216,
	SaffronTrunk = 217,
	CobaltDome = 218,
	MosaicSandstone = 219,

	-- Washi Hot Springs biome (surface)
	WashiPaper = 220,
	CoralPaper = 221,
	BambooTrunk = 222,
	BambooTop = 223,
	SteamFiller = 224,

	-- Gazette Metropolis biome (surface)
	NewsprintSurface = 230,
	InkSubsurface = 231,
	SepiaTrunk = 232,
	DustyCanopy = 233,
	RedHeadline = 234,

	-- Crayon Savanna biome (surface)
	WaxySurface = 240,
	CrayonSubsurface = 241,
	CrayonTrunk = 242,
	CrayonCanopy = 243,
	BurntOrange = 244,

	-- Pastel Cloudtops biome (surface)
	BabyBlueSurface = 250,
	LavenderSubsurface = 251,
	CreamTrunk = 252,
	RosePinkCanopy = 253,
	SoftPeach = 254,
}
