--!strict

local BlockType = require(script.Parent.Enums.BlockType)

type BlockConfig = {
	id: number,
	name: string,
	hardness: number,
	color: Color3,
	material: Enum.Material,
	mineable: boolean,
	minTier: number,
	drops: { { itemId: string, count: number, chance: number } }?,
	xp: number,
}

local BlockRegistry = {}

local blocks: { [number]: BlockConfig } = {
	[BlockType.Air] = {
		id = BlockType.Air,
		name = "Air",
		hardness = 0,
		color = Color3.new(0, 0, 0),
		material = Enum.Material.Air,
		mineable = false,
		minTier = 0,
		xp = 0,
	},

	-- ═══════════════════════════════════════════
	-- Layer 1: Paper Fields (0 to -80 depth)
	-- Warm paper tones, soft materials
	-- ═══════════════════════════════════════════

	[BlockType.PaperGrass] = {
		id = BlockType.PaperGrass,
		name = "Paper Grass",
		hardness = 1,
		color = Color3.fromRGB(180, 210, 140), -- soft green paper
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "paper_scrap", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.Paper] = {
		id = BlockType.Paper,
		name = "Paper",
		hardness = 1,
		color = Color3.fromRGB(255, 250, 235), -- soft cream
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "paper_scrap", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.Cardboard] = {
		id = BlockType.Cardboard,
		name = "Cardboard",
		hardness = 2,
		color = Color3.fromRGB(190, 160, 120), -- kraft brown
		material = Enum.Material.WoodPlanks,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cardboard", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.DriedPulp] = {
		id = BlockType.DriedPulp,
		name = "Dried Pulp",
		hardness = 2,
		color = Color3.fromRGB(200, 180, 150), -- tan
		material = Enum.Material.Ground,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "dried_pulp", count = 1, chance = 1 } },
		xp = 2,
	},

	-- ═══════════════════════════════════════════
	-- Layer 2: Pulp Caverns (-80 to -240 depth)
	-- Compressed, denser materials
	-- ═══════════════════════════════════════════

	[BlockType.CompressedPulp] = {
		id = BlockType.CompressedPulp,
		name = "Compressed Pulp",
		hardness = 4,
		color = Color3.fromRGB(160, 140, 110), -- dark tan
		material = Enum.Material.Ground,
		mineable = true,
		minTier = 1,
		drops = { { itemId = "compressed_pulp", count = 1, chance = 1 } },
		xp = 3,
	},
	[BlockType.Clay] = {
		id = BlockType.Clay,
		name = "Clay",
		hardness = 3,
		color = Color3.fromRGB(170, 140, 120), -- clay brown
		material = Enum.Material.Mud,
		mineable = true,
		minTier = 1,
		drops = { { itemId = "clay_chunk", count = 1, chance = 1 } },
		xp = 3,
	},
	[BlockType.RecycledFiber] = {
		id = BlockType.RecycledFiber,
		name = "Recycled Fiber",
		hardness = 3,
		color = Color3.fromRGB(150, 160, 140), -- gray-green
		material = Enum.Material.Fabric,
		mineable = true,
		minTier = 1,
		drops = { { itemId = "recycled_fiber", count = 1, chance = 1 } },
		xp = 4,
	},
	[BlockType.PulpOre] = {
		id = BlockType.PulpOre,
		name = "Pulp Ore",
		hardness = 5,
		color = Color3.fromRGB(200, 170, 80), -- golden pulp
		material = Enum.Material.Ground,
		mineable = true,
		minTier = 1,
		drops = { { itemId = "pulp_ore", count = 1, chance = 1 }, { itemId = "cardboard", count = 1, chance = 0.3 } },
		xp = 6,
	},

	-- ═══════════════════════════════════════════
	-- Layer 3: Fold Tunnels (-240 to -480 depth)
	-- Geometric, crystalline paper
	-- ═══════════════════════════════════════════

	[BlockType.FoldedStone] = {
		id = BlockType.FoldedStone,
		name = "Folded Stone",
		hardness = 8,
		color = Color3.fromRGB(140, 145, 155), -- blue-gray stone
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 2,
		drops = { { itemId = "folded_stone", count = 1, chance = 1 } },
		xp = 5,
	},
	[BlockType.PaperQuartz] = {
		id = BlockType.PaperQuartz,
		name = "Paper Quartz",
		hardness = 6,
		color = Color3.fromRGB(230, 225, 240), -- pale quartz
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 2,
		drops = { { itemId = "quartz_shard", count = 1, chance = 1 } },
		xp = 7,
	},
	[BlockType.PaperCrystal] = {
		id = BlockType.PaperCrystal,
		name = "Paper Crystal",
		hardness = 10,
		color = Color3.fromRGB(200, 220, 255), -- ice blue
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 2,
		drops = { { itemId = "paper_crystal", count = 1, chance = 1 } },
		xp = 10,
	},
	[BlockType.InkStone] = {
		id = BlockType.InkStone,
		name = "Ink Stone",
		hardness = 7,
		color = Color3.fromRGB(50, 50, 70), -- dark ink blue
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 2,
		drops = { { itemId = "ink_stone", count = 1, chance = 1 } },
		xp = 8,
	},

	-- ═══════════════════════════════════════════
	-- Layer 4: Origami Depths (-480 to -800 depth)
	-- Rich, gem-like materials
	-- ═══════════════════════════════════════════

	[BlockType.OrigamiRock] = {
		id = BlockType.OrigamiRock,
		name = "Origami Rock",
		hardness = 12,
		color = Color3.fromRGB(120, 100, 130), -- purple-gray
		material = Enum.Material.Granite,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "origami_rock", count = 1, chance = 1 } },
		xp = 10,
	},
	[BlockType.GemFragment] = {
		id = BlockType.GemFragment,
		name = "Gem Fragment",
		hardness = 15,
		color = Color3.fromRGB(220, 100, 180), -- pink gem
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "gem_fragment", count = 1, chance = 1 } },
		xp = 15,
	},
	[BlockType.FoilOre] = {
		id = BlockType.FoilOre,
		name = "Foil Ore",
		hardness = 14,
		color = Color3.fromRGB(255, 200, 50), -- gold foil
		material = Enum.Material.Foil,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "foil_ore", count = 1, chance = 1 } },
		xp = 12,
	},
	[BlockType.RubyPaper] = {
		id = BlockType.RubyPaper,
		name = "Ruby Paper",
		hardness = 18,
		color = Color3.fromRGB(220, 30, 60), -- ruby red
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "ruby_paper", count = 1, chance = 1 } },
		xp = 20,
	},

	-- ═══════════════════════════════════════════
	-- Layer 5: Crystal Lattice (-800 to -1200 depth)
	-- Metallic, crystalline
	-- ═══════════════════════════════════════════

	[BlockType.CrystalBlock] = {
		id = BlockType.CrystalBlock,
		name = "Crystal Block",
		hardness = 20,
		color = Color3.fromRGB(150, 200, 255), -- bright crystal blue
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "crystal_shard", count = 1, chance = 1 } },
		xp = 18,
	},
	[BlockType.FoilSheet] = {
		id = BlockType.FoilSheet,
		name = "Foil Sheet",
		hardness = 18,
		color = Color3.fromRGB(220, 220, 230), -- silver foil
		material = Enum.Material.Foil,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "foil_sheet", count = 1, chance = 1 } },
		xp = 15,
	},
	[BlockType.MetalOrigami] = {
		id = BlockType.MetalOrigami,
		name = "Metal Origami",
		hardness = 25,
		color = Color3.fromRGB(180, 180, 200), -- steel
		material = Enum.Material.Metal,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "metal_origami", count = 1, chance = 1 } },
		xp = 20,
	},
	[BlockType.SapphireCrystal] = {
		id = BlockType.SapphireCrystal,
		name = "Sapphire Crystal",
		hardness = 22,
		color = Color3.fromRGB(20, 80, 200), -- deep sapphire
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 3,
		drops = { { itemId = "sapphire_crystal", count = 1, chance = 1 } },
		xp = 25,
	},

	-- ═══════════════════════════════════════════
	-- Layer 6: Void Seams (-1200 to -1600 depth)
	-- Dark, mysterious materials
	-- ═══════════════════════════════════════════

	[BlockType.VoidStone] = {
		id = BlockType.VoidStone,
		name = "Void Stone",
		hardness = 30,
		color = Color3.fromRGB(25, 15, 40), -- deep purple-black
		material = Enum.Material.Basalt,
		mineable = true,
		minTier = 4,
		drops = { { itemId = "void_stone", count = 1, chance = 1 } },
		xp = 25,
	},
	[BlockType.DarkPaper] = {
		id = BlockType.DarkPaper,
		name = "Dark Paper",
		hardness = 28,
		color = Color3.fromRGB(40, 30, 50), -- dark violet
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 4,
		drops = { { itemId = "dark_paper", count = 1, chance = 1 } },
		xp = 22,
	},
	[BlockType.ShadowFold] = {
		id = BlockType.ShadowFold,
		name = "Shadow Fold",
		hardness = 35,
		color = Color3.fromRGB(60, 20, 80), -- deep magenta
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 4,
		drops = { { itemId = "shadow_fold", count = 1, chance = 1 } },
		xp = 30,
	},
	[BlockType.VoidCrystal] = {
		id = BlockType.VoidCrystal,
		name = "Void Crystal",
		hardness = 40,
		color = Color3.fromRGB(150, 0, 255), -- neon purple
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 4,
		drops = { { itemId = "void_crystal", count = 1, chance = 1 } },
		xp = 40,
	},

	-- ═══════════════════════════════════════════
	-- Layer 7: The Core (-1600 to -2000 depth)
	-- Prismatic, rainbow materials
	-- ═══════════════════════════════════════════

	[BlockType.PrismaticBlock] = {
		id = BlockType.PrismaticBlock,
		name = "Prismatic Block",
		hardness = 50,
		color = Color3.fromRGB(255, 200, 255), -- pink-white prismatic
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 5,
		drops = { { itemId = "prismatic_shard", count = 1, chance = 1 } },
		xp = 50,
	},
	[BlockType.CoreFragment] = {
		id = BlockType.CoreFragment,
		name = "Core Fragment",
		hardness = 60,
		color = Color3.fromRGB(255, 255, 200), -- golden glow
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 5,
		drops = { { itemId = "core_fragment", count = 1, chance = 1 } },
		xp = 60,
	},
	[BlockType.RainbowPaper] = {
		id = BlockType.RainbowPaper,
		name = "Rainbow Paper",
		hardness = 45,
		color = Color3.fromRGB(255, 150, 100), -- warm rainbow
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 5,
		drops = { { itemId = "rainbow_paper", count = 1, chance = 1 } },
		xp = 55,
	},

	-- ═══════════════════════════════════════════
	-- Nature (surface)
	-- ═══════════════════════════════════════════

	[BlockType.Wood] = {
		id = BlockType.Wood,
		name = "Wood",
		hardness = 2,
		color = Color3.fromRGB(190, 160, 120), -- kraft paper trunk
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "wood", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.Leaves] = {
		id = BlockType.Leaves,
		name = "Leaves",
		hardness = 0.5,
		color = Color3.fromRGB(150, 200, 140), -- soft green origami
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "paper_scrap", count = 1, chance = 0.5 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Structure-specific blocks (mixed mode)
	-- ═══════════════════════════════════════════

	[BlockType.CactusGreen] = {
		id = BlockType.CactusGreen,
		name = "Cactus",
		hardness = 2,
		color = Color3.fromRGB(80, 160, 60),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cactus", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CactusFlower] = {
		id = BlockType.CactusFlower,
		name = "Cactus Flower",
		hardness = 0.5,
		color = Color3.fromRGB(255, 200, 80),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cactus_flower", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.BoulderGray] = {
		id = BlockType.BoulderGray,
		name = "Boulder",
		hardness = 3,
		color = Color3.fromRGB(140, 135, 130),
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "boulder", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.BonsaiBark] = {
		id = BlockType.BonsaiBark,
		name = "Bonsai Trunk",
		hardness = 2,
		color = Color3.fromRGB(90, 60, 40),
		material = Enum.Material.WoodPlanks,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "bonsai_bark", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CherryBlossom] = {
		id = BlockType.CherryBlossom,
		name = "Cherry Blossom",
		hardness = 0.5,
		color = Color3.fromRGB(255, 180, 200),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cherry_blossom", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.LotusPetal] = {
		id = BlockType.LotusPetal,
		name = "Lotus Petal",
		hardness = 1,
		color = Color3.fromRGB(250, 240, 245),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "lotus_petal", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.LotusCenter] = {
		id = BlockType.LotusCenter,
		name = "Lotus Heart",
		hardness = 1,
		color = Color3.fromRGB(255, 220, 100),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "lotus_center", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.FlyTrapStem] = {
		id = BlockType.FlyTrapStem,
		name = "Fly Trap Stem",
		hardness = 2,
		color = Color3.fromRGB(70, 140, 50),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "fly_trap_stem", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.FlyTrapMaw] = {
		id = BlockType.FlyTrapMaw,
		name = "Fly Trap Maw",
		hardness = 1,
		color = Color3.fromRGB(210, 50, 60),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "fly_trap_maw", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.PineNeedle] = {
		id = BlockType.PineNeedle,
		name = "Pine Needle",
		hardness = 0.3,
		color = Color3.fromRGB(30, 90, 40),
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "pine_needle", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.WillowVine] = {
		id = BlockType.WillowVine,
		name = "Willow Vine",
		hardness = 0.3,
		color = Color3.fromRGB(140, 180, 80),
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "willow_vine", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.WillowLeaves] = {
		id = BlockType.WillowLeaves,
		name = "Willow Leaves",
		hardness = 0.3,
		color = Color3.fromRGB(150, 190, 90),
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "willow_vine", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.PalmFrond] = {
		id = BlockType.PalmFrond,
		name = "Palm Frond",
		hardness = 0.3,
		color = Color3.fromRGB(60, 160, 50),
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "palm_frond", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.GiantBark] = {
		id = BlockType.GiantBark,
		name = "Giant Bark",
		hardness = 2,
		color = Color3.fromRGB(70, 45, 25),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "giant_bark", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.BirchBark] = {
		id = BlockType.BirchBark,
		name = "Birch Bark",
		hardness = 1,
		color = Color3.fromRGB(230, 225, 210),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "birch_bark", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.MushroomStem] = {
		id = BlockType.MushroomStem,
		name = "Mushroom Stem",
		hardness = 1,
		color = Color3.fromRGB(180, 255, 220),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "mushroom_stem", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.MushroomCap] = {
		id = BlockType.MushroomCap,
		name = "Mushroom Cap",
		hardness = 0.5,
		color = Color3.fromRGB(255, 60, 200),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "mushroom_cap", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.ShelfBracket] = {
		id = BlockType.ShelfBracket,
		name = "Shelf Fungus",
		hardness = 1,
		color = Color3.fromRGB(255, 170, 50),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "shelf_bracket", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Fairy World biome (surface)
	-- Enchanted fairy forest with glowing mushrooms
	-- ═══════════════════════════════════════════

	[BlockType.FairyMoss] = {
		id = BlockType.FairyMoss,
		name = "Fairy Moss",
		hardness = 1,
		color = Color3.fromRGB(180, 150, 220), -- soft lilac
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "fairy_moss", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.EnchantedSoil] = {
		id = BlockType.EnchantedSoil,
		name = "Enchanted Soil",
		hardness = 2,
		color = Color3.fromRGB(100, 60, 140), -- deep violet
		material = Enum.Material.Mud,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "enchanted_soil", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.FairyFiller] = {
		id = BlockType.FairyFiller,
		name = "Fairy Stone",
		hardness = 2,
		color = Color3.fromRGB(60, 40, 80), -- dark mystical purple
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "fairy_filler", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.FairyTrunk] = {
		id = BlockType.FairyTrunk,
		name = "Silver Stem",
		hardness = 2,
		color = Color3.fromRGB(220, 210, 240), -- silvery lavender
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "fairy_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.FairyCanopy] = {
		id = BlockType.FairyCanopy,
		name = "Fairy Cap",
		hardness = 0.5,
		color = Color3.fromRGB(255, 130, 200), -- glowing pink
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "fairy_canopy", count = 1, chance = 0.5 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Fairy Glade biome (surface)
	-- Golden sunlit fairy clearing
	-- ═══════════════════════════════════════════

	[BlockType.GladeGrass] = {
		id = BlockType.GladeGrass,
		name = "Glade Grass",
		hardness = 1,
		color = Color3.fromRGB(200, 220, 130), -- warm golden-green
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "glade_grass", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.GladeSoil] = {
		id = BlockType.GladeSoil,
		name = "Glade Soil",
		hardness = 2,
		color = Color3.fromRGB(140, 110, 60), -- warm brown
		material = Enum.Material.Mud,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "glade_soil", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.GladeTrunk] = {
		id = BlockType.GladeTrunk,
		name = "Golden Bark",
		hardness = 2,
		color = Color3.fromRGB(240, 210, 140), -- warm gold bark
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "glade_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.GladeCanopy] = {
		id = BlockType.GladeCanopy,
		name = "Sunlit Leaves",
		hardness = 0.5,
		color = Color3.fromRGB(255, 240, 100), -- glowing yellow-gold
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "glade_canopy", count = 1, chance = 0.5 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Fairy Hollow biome (surface)
	-- Deep twilight blue fairy hollow
	-- ═══════════════════════════════════════════

	[BlockType.HollowMoss] = {
		id = BlockType.HollowMoss,
		name = "Hollow Moss",
		hardness = 1,
		color = Color3.fromRGB(80, 120, 170), -- twilight blue
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "hollow_moss", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.HollowSoil] = {
		id = BlockType.HollowSoil,
		name = "Hollow Soil",
		hardness = 2,
		color = Color3.fromRGB(40, 50, 90), -- deep blue-gray
		material = Enum.Material.Mud,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "hollow_soil", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.HollowTrunk] = {
		id = BlockType.HollowTrunk,
		name = "Moonwood",
		hardness = 2,
		color = Color3.fromRGB(160, 180, 210), -- pale blue-silver
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "hollow_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.HollowCanopy] = {
		id = BlockType.HollowCanopy,
		name = "Moonpetal",
		hardness = 0.5,
		color = Color3.fromRGB(100, 200, 255), -- glowing cyan-blue
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "hollow_canopy", count = 1, chance = 0.5 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Sunset Mesa biome (surface)
	-- Desert canyon at golden hour
	-- ═══════════════════════════════════════════

	[BlockType.Sandstone] = {
		id = BlockType.Sandstone,
		name = "Sandstone",
		hardness = 1,
		color = Color3.fromRGB(210, 130, 60), -- burnt orange
		material = Enum.Material.Sandstone,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "sandstone", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.RedClay] = {
		id = BlockType.RedClay,
		name = "Red Clay",
		hardness = 2,
		color = Color3.fromRGB(160, 70, 50), -- dusty red clay
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "red_clay", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.SandstoneTan] = {
		id = BlockType.SandstoneTan,
		name = "Sandstone Trunk",
		hardness = 2,
		color = Color3.fromRGB(220, 190, 140), -- sandstone tan
		material = Enum.Material.Sandstone,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "sandstone", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.WarmPinkTop] = {
		id = BlockType.WarmPinkTop,
		name = "Cactus Bloom",
		hardness = 0.5,
		color = Color3.fromRGB(220, 140, 160), -- warm pink
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "sandstone", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.DeepPurpleAccent] = {
		id = BlockType.DeepPurpleAccent,
		name = "Desert Amethyst",
		hardness = 1,
		color = Color3.fromRGB(80, 30, 90), -- deep purple
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "sandstone", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Clockwork biome (surface)
	-- Steampunk cardboard & metal
	-- ═══════════════════════════════════════════

	[BlockType.CorrugatedCardboard] = {
		id = BlockType.CorrugatedCardboard,
		name = "Corrugated Cardboard",
		hardness = 2,
		color = Color3.fromRGB(180, 140, 90),
		material = Enum.Material.WoodPlanks,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "corrugated_cardboard", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.DarkCardboard] = {
		id = BlockType.DarkCardboard,
		name = "Dark Cardboard",
		hardness = 3,
		color = Color3.fromRGB(100, 70, 45),
		material = Enum.Material.WoodPlanks,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "dark_cardboard", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CopperGear] = {
		id = BlockType.CopperGear,
		name = "Copper Gear",
		hardness = 3,
		color = Color3.fromRGB(190, 130, 70),
		material = Enum.Material.Metal,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "copper_gear", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.BrassLeaf] = {
		id = BlockType.BrassLeaf,
		name = "Brass Leaf",
		hardness = 1,
		color = Color3.fromRGB(205, 175, 80),
		material = Enum.Material.Metal,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "brass_leaf", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Neon Reef biome (surface)
	-- Bioluminescent coral underwater feel
	-- ═══════════════════════════════════════════

	[BlockType.CoralPlate] = {
		id = BlockType.CoralPlate,
		name = "Coral Plate",
		hardness = 1,
		color = Color3.fromRGB(255, 50, 120),
		material = Enum.Material.Grass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "coral_plate", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.ReefRock] = {
		id = BlockType.ReefRock,
		name = "Reef Rock",
		hardness = 2,
		color = Color3.fromRGB(80, 20, 120),
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "reef_rock", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CoralFiller] = {
		id = BlockType.CoralFiller,
		name = "Coral Base",
		hardness = 2,
		color = Color3.fromRGB(15, 15, 60),
		material = Enum.Material.Basalt,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "coral_filler", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CoralTrunk] = {
		id = BlockType.CoralTrunk,
		name = "Coral Tower",
		hardness = 2,
		color = Color3.fromRGB(0, 220, 220),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "coral_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CoralCanopy] = {
		id = BlockType.CoralCanopy,
		name = "Coral Crown",
		hardness = 0.5,
		color = Color3.fromRGB(255, 50, 120),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "coral_canopy", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.OrangeAccent] = {
		id = BlockType.OrangeAccent,
		name = "Orange Coral",
		hardness = 1,
		color = Color3.fromRGB(255, 100, 0),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "orange_accent", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Crystal Bloom biome (surface)
	-- Gemstone garden
	-- ═══════════════════════════════════════════

	[BlockType.CrystalGround] = {
		id = BlockType.CrystalGround,
		name = "Crystal Ground",
		hardness = 1,
		color = Color3.fromRGB(140, 80, 180),
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "crystal_ground", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.RoseQuartz] = {
		id = BlockType.RoseQuartz,
		name = "Rose Quartz",
		hardness = 2,
		color = Color3.fromRGB(220, 150, 180),
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "rose_quartz", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CitrineTrunk] = {
		id = BlockType.CitrineTrunk,
		name = "Citrine Trunk",
		hardness = 2,
		color = Color3.fromRGB(220, 180, 50),
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "citrine_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.AquamarineCanopy] = {
		id = BlockType.AquamarineCanopy,
		name = "Aquamarine Canopy",
		hardness = 0.5,
		color = Color3.fromRGB(80, 200, 200),
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "aquamarine_canopy", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.DiamondAccent] = {
		id = BlockType.DiamondAccent,
		name = "Diamond Accent",
		hardness = 1,
		color = Color3.fromRGB(240, 240, 255),
		material = Enum.Material.Glass,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "diamond_accent", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Frozen Auroras biome (surface)
	-- Icy glaciers with aurora lights
	-- ═══════════════════════════════════════════

	[BlockType.GlacierIce] = {
		id = BlockType.GlacierIce,
		name = "Glacier Ice",
		hardness = 1,
		color = Color3.fromRGB(140, 200, 230),
		material = Enum.Material.Glacier,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "glacier_ice", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.MintFrost] = {
		id = BlockType.MintFrost,
		name = "Mint Frost",
		hardness = 2,
		color = Color3.fromRGB(150, 220, 180),
		material = Enum.Material.Glacier,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "mint_frost", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.IceWhiteTrunk] = {
		id = BlockType.IceWhiteTrunk,
		name = "Ice Spire",
		hardness = 2,
		color = Color3.fromRGB(230, 240, 250),
		material = Enum.Material.Glacier,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "ice_white_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.AuroraVioletCanopy] = {
		id = BlockType.AuroraVioletCanopy,
		name = "Aurora Crystal",
		hardness = 0.5,
		color = Color3.fromRGB(160, 80, 200),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "aurora_violet_canopy", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.DeepIndigo] = {
		id = BlockType.DeepIndigo,
		name = "Deep Indigo",
		hardness = 1,
		color = Color3.fromRGB(40, 30, 100),
		material = Enum.Material.Glacier,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "deep_indigo", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Confetti Carnival biome (surface)
	-- Colorful party theme
	-- ═══════════════════════════════════════════

	[BlockType.PartyPaper] = {
		id = BlockType.PartyPaper,
		name = "Party Paper",
		hardness = 1,
		color = Color3.fromRGB(255, 50, 150),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "party_paper", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.GoldPaper] = {
		id = BlockType.GoldPaper,
		name = "Gold Paper",
		hardness = 1,
		color = Color3.fromRGB(255, 200, 50),
		material = Enum.Material.Foil,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "gold_paper", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.PinataWood] = {
		id = BlockType.PinataWood,
		name = "Pinata Wood",
		hardness = 2,
		color = Color3.fromRGB(100, 255, 50),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "pinata_wood", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.PinataLeaves] = {
		id = BlockType.PinataLeaves,
		name = "Pinata Canopy",
		hardness = 0.5,
		color = Color3.fromRGB(50, 100, 255),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "pinata_leaves", count = 1, chance = 0.5 } },
		xp = 1,
	},
	[BlockType.ConfettiFiller] = {
		id = BlockType.ConfettiFiller,
		name = "Confetti Filler",
		hardness = 2,
		color = Color3.fromRGB(250, 250, 250),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "confetti_filler", count = 1, chance = 1 } },
		xp = 2,
	},

	-- ═══════════════════════════════════════════
	-- Ink River biome (surface)
	-- Calligraphy scroll landscape
	-- ═══════════════════════════════════════════

	[BlockType.ScrollParchment] = {
		id = BlockType.ScrollParchment,
		name = "Scroll Parchment",
		hardness = 1,
		color = Color3.fromRGB(245, 235, 200),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "scroll_parchment", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.AgedPaper] = {
		id = BlockType.AgedPaper,
		name = "Aged Paper",
		hardness = 1,
		color = Color3.fromRGB(220, 200, 150),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "aged_paper", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.InkBrushTrunk] = {
		id = BlockType.InkBrushTrunk,
		name = "Ink Brush",
		hardness = 2,
		color = Color3.fromRGB(30, 25, 35),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "ink_brush_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.InkSplatterLeaf] = {
		id = BlockType.InkSplatterLeaf,
		name = "Ink Splatter",
		hardness = 0.5,
		color = Color3.fromRGB(180, 30, 40),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "ink_splatter_leaf", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Paste Waterfalls biome (surface)
	-- Papier-mache cascades
	-- ═══════════════════════════════════════════

	[BlockType.PapierMache] = {
		id = BlockType.PapierMache,
		name = "Papier-Mache",
		hardness = 1,
		color = Color3.fromRGB(240, 230, 210),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "papier_mache", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.NewspaperGray] = {
		id = BlockType.NewspaperGray,
		name = "Newspaper",
		hardness = 1,
		color = Color3.fromRGB(180, 175, 170),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "newspaper_gray", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.PasteDripTrunk] = {
		id = BlockType.PasteDripTrunk,
		name = "Paste Column",
		hardness = 2,
		color = Color3.fromRGB(250, 245, 235),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "paste_drip_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.PasteDripLeaf] = {
		id = BlockType.PasteDripLeaf,
		name = "Paste Cap",
		hardness = 0.5,
		color = Color3.fromRGB(220, 190, 130),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "paste_drip_leaf", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Balloon Chambers biome (surface)
	-- Underground balloon caverns
	-- ═══════════════════════════════════════════

	[BlockType.BalloonRed] = {
		id = BlockType.BalloonRed,
		name = "Balloon Surface",
		hardness = 1,
		color = Color3.fromRGB(220, 40, 50),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "balloon_red", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.NewspaperLayer] = {
		id = BlockType.NewspaperLayer,
		name = "Newspaper Layer",
		hardness = 1,
		color = Color3.fromRGB(185, 180, 175),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "newspaper_layer", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.BalloonString] = {
		id = BlockType.BalloonString,
		name = "Balloon String",
		hardness = 2,
		color = Color3.fromRGB(50, 45, 40),
		material = Enum.Material.Fabric,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "balloon_string", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.BalloonTop] = {
		id = BlockType.BalloonTop,
		name = "Balloon Top",
		hardness = 0.5,
		color = Color3.fromRGB(60, 150, 255),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "balloon_top", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Ember Wastes biome (surface)
	-- Volcanic ash and molten terrain
	-- ═══════════════════════════════════════════

	[BlockType.VolcanicRock] = {
		id = BlockType.VolcanicRock,
		name = "Volcanic Rock",
		hardness = 1,
		color = Color3.fromRGB(35, 30, 30),
		material = Enum.Material.Basalt,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "volcanic_rock", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.AshStone] = {
		id = BlockType.AshStone,
		name = "Ash Stone",
		hardness = 2,
		color = Color3.fromRGB(120, 115, 110),
		material = Enum.Material.Slate,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "ash_stone", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.ScorchedBase] = {
		id = BlockType.ScorchedBase,
		name = "Scorched Base",
		hardness = 2,
		color = Color3.fromRGB(25, 20, 20),
		material = Enum.Material.Basalt,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "scorched_base", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.BasaltColumn] = {
		id = BlockType.BasaltColumn,
		name = "Basalt Column",
		hardness = 2,
		color = Color3.fromRGB(40, 35, 35),
		material = Enum.Material.Basalt,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "basalt_column", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.MoltenCap] = {
		id = BlockType.MoltenCap,
		name = "Molten Cap",
		hardness = 0.5,
		color = Color3.fromRGB(255, 140, 20),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "molten_cap", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.CrimsonVein] = {
		id = BlockType.CrimsonVein,
		name = "Crimson Vein",
		hardness = 1,
		color = Color3.fromRGB(140, 15, 15),
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "crimson_vein", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Pulp Nebula biome (surface)
	-- Cosmic paper void
	-- ═══════════════════════════════════════════

	[BlockType.CosmicPaper] = {
		id = BlockType.CosmicPaper,
		name = "Cosmic Paper",
		hardness = 1,
		color = Color3.fromRGB(20, 15, 60),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cosmic_paper", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.StellarDust] = {
		id = BlockType.StellarDust,
		name = "Stellar Dust",
		hardness = 1,
		color = Color3.fromRGB(100, 40, 160),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "stellar_dust", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.SatelliteTrunk] = {
		id = BlockType.SatelliteTrunk,
		name = "Satellite Spire",
		hardness = 2,
		color = Color3.fromRGB(190, 195, 200),
		material = Enum.Material.Metal,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "satellite_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CyanCanopy] = {
		id = BlockType.CyanCanopy,
		name = "Cyan Dish",
		hardness = 0.5,
		color = Color3.fromRGB(150, 220, 240),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cyan_canopy", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.NebulaFiller] = {
		id = BlockType.NebulaFiller,
		name = "Nebula Filler",
		hardness = 2,
		color = Color3.fromRGB(10, 10, 15),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "nebula_filler", count = 1, chance = 1 } },
		xp = 2,
	},

	-- ═══════════════════════════════════════════
	-- Mosaic Bazaar biome (surface)
	-- Tiled marketplace
	-- ═══════════════════════════════════════════

	[BlockType.TurquoiseTile] = {
		id = BlockType.TurquoiseTile,
		name = "Turquoise Tile",
		hardness = 1,
		color = Color3.fromRGB(60, 180, 170),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "turquoise_tile", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.TerracottaClay] = {
		id = BlockType.TerracottaClay,
		name = "Terracotta Clay",
		hardness = 1,
		color = Color3.fromRGB(190, 100, 60),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "terracotta_clay", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.SaffronTrunk] = {
		id = BlockType.SaffronTrunk,
		name = "Saffron Column",
		hardness = 2,
		color = Color3.fromRGB(240, 190, 50),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "saffron_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CobaltDome] = {
		id = BlockType.CobaltDome,
		name = "Cobalt Dome",
		hardness = 0.5,
		color = Color3.fromRGB(40, 70, 170),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cobalt_dome", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.MosaicSandstone] = {
		id = BlockType.MosaicSandstone,
		name = "Mosaic Sandstone",
		hardness = 1,
		color = Color3.fromRGB(210, 185, 140),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "mosaic_sandstone", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Washi Hot Springs biome (surface)
	-- Japanese paper & bamboo spa
	-- ═══════════════════════════════════════════

	[BlockType.WashiPaper] = {
		id = BlockType.WashiPaper,
		name = "Washi Paper",
		hardness = 1,
		color = Color3.fromRGB(245, 235, 215),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "washi_paper", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.CoralPaper] = {
		id = BlockType.CoralPaper,
		name = "Coral Paper",
		hardness = 1,
		color = Color3.fromRGB(220, 160, 150),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "coral_paper", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.BambooTrunk] = {
		id = BlockType.BambooTrunk,
		name = "Paper Bamboo",
		hardness = 2,
		color = Color3.fromRGB(100, 170, 120),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "bamboo_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.BambooTop] = {
		id = BlockType.BambooTop,
		name = "Bamboo Top",
		hardness = 0.5,
		color = Color3.fromRGB(60, 55, 50),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "bamboo_top", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.SteamFiller] = {
		id = BlockType.SteamFiller,
		name = "Steam Filler",
		hardness = 2,
		color = Color3.fromRGB(240, 240, 245),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "steam_filler", count = 1, chance = 1 } },
		xp = 2,
	},

	-- ═══════════════════════════════════════════
	-- Gazette Metropolis biome (surface)
	-- Newspaper cityscape
	-- ═══════════════════════════════════════════

	[BlockType.NewsprintSurface] = {
		id = BlockType.NewsprintSurface,
		name = "Newsprint",
		hardness = 1,
		color = Color3.fromRGB(235, 225, 200),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "newsprint_surface", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.InkSubsurface] = {
		id = BlockType.InkSubsurface,
		name = "Ink Layer",
		hardness = 1,
		color = Color3.fromRGB(30, 30, 35),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "ink_subsurface", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.SepiaTrunk] = {
		id = BlockType.SepiaTrunk,
		name = "Sepia Column",
		hardness = 2,
		color = Color3.fromRGB(160, 130, 90),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "sepia_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.DustyCanopy] = {
		id = BlockType.DustyCanopy,
		name = "Dusty Canopy",
		hardness = 0.5,
		color = Color3.fromRGB(150, 145, 140),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "dusty_canopy", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.RedHeadline] = {
		id = BlockType.RedHeadline,
		name = "Red Headline",
		hardness = 1,
		color = Color3.fromRGB(180, 30, 30),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "red_headline", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Crayon Savanna biome (surface)
	-- Waxy crayon grasslands
	-- ═══════════════════════════════════════════

	[BlockType.WaxySurface] = {
		id = BlockType.WaxySurface,
		name = "Waxy Surface",
		hardness = 1,
		color = Color3.fromRGB(240, 200, 60),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "waxy_surface", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.CrayonSubsurface] = {
		id = BlockType.CrayonSubsurface,
		name = "Crayon Layer",
		hardness = 1,
		color = Color3.fromRGB(160, 120, 70),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "crayon_subsurface", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.CrayonTrunk] = {
		id = BlockType.CrayonTrunk,
		name = "Crayon Trunk",
		hardness = 2,
		color = Color3.fromRGB(80, 180, 80),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "crayon_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.CrayonCanopy] = {
		id = BlockType.CrayonCanopy,
		name = "Crayon Canopy",
		hardness = 0.5,
		color = Color3.fromRGB(100, 170, 240),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "crayon_canopy", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.BurntOrange] = {
		id = BlockType.BurntOrange,
		name = "Burnt Orange",
		hardness = 1,
		color = Color3.fromRGB(230, 130, 50),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "burnt_orange", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Pastel Cloudtops biome (surface)
	-- Soft pastel sky islands
	-- ═══════════════════════════════════════════

	[BlockType.BabyBlueSurface] = {
		id = BlockType.BabyBlueSurface,
		name = "Baby Blue Cloud",
		hardness = 1,
		color = Color3.fromRGB(170, 210, 240),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "baby_blue_surface", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.LavenderSubsurface] = {
		id = BlockType.LavenderSubsurface,
		name = "Lavender Mist",
		hardness = 1,
		color = Color3.fromRGB(190, 170, 220),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "lavender_subsurface", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.CreamTrunk] = {
		id = BlockType.CreamTrunk,
		name = "Cream Pillar",
		hardness = 2,
		color = Color3.fromRGB(250, 245, 235),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "cream_trunk", count = 1, chance = 1 } },
		xp = 2,
	},
	[BlockType.RosePinkCanopy] = {
		id = BlockType.RosePinkCanopy,
		name = "Rose Pink Canopy",
		hardness = 0.5,
		color = Color3.fromRGB(230, 150, 170),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "rose_pink_canopy", count = 1, chance = 1 } },
		xp = 1,
	},
	[BlockType.SoftPeach] = {
		id = BlockType.SoftPeach,
		name = "Soft Peach",
		hardness = 1,
		color = Color3.fromRGB(240, 200, 180),
		material = Enum.Material.SmoothPlastic,
		mineable = true,
		minTier = 0,
		drops = { { itemId = "soft_peach", count = 1, chance = 1 } },
		xp = 1,
	},

	-- ═══════════════════════════════════════════
	-- Special
	-- ═══════════════════════════════════════════

	[BlockType.EggNode] = {
		id = BlockType.EggNode,
		name = "Egg Node",
		hardness = 10,
		color = Color3.fromRGB(255, 230, 180), -- warm egg glow
		material = Enum.Material.Neon,
		mineable = true,
		minTier = 1,
		drops = {
			{ itemId = "egg_fragment", count = 1, chance = 1 },
			{ itemId = "egg_fragment", count = 1, chance = 0.5 },
		},
		xp = 20,
	},

	[BlockType.Bedrock] = {
		id = BlockType.Bedrock,
		name = "Bedrock",
		hardness = math.huge,
		color = Color3.fromRGB(30, 30, 30),
		material = Enum.Material.Basalt,
		mineable = false,
		minTier = 999,
		xp = 0,
	},
}

function BlockRegistry.get(blockTypeId: number): BlockConfig?
	return blocks[blockTypeId]
end

function BlockRegistry.getHardness(blockTypeId: number): number
	local config = blocks[blockTypeId]
	if config then
		return config.hardness
	end
	return math.huge
end

function BlockRegistry.getColor(blockTypeId: number): Color3
	local config = blocks[blockTypeId]
	if config then
		return config.color
	end
	return Color3.fromRGB(255, 0, 255) -- magenta = missing
end

function BlockRegistry.getMaterial(blockTypeId: number): Enum.Material
	local config = blocks[blockTypeId]
	if config then
		return config.material
	end
	return Enum.Material.Plastic
end

function BlockRegistry.isMineable(blockTypeId: number): boolean
	local config = blocks[blockTypeId]
	if config then
		return config.mineable
	end
	return false
end

function BlockRegistry.isAir(blockTypeId: number): boolean
	return blockTypeId == BlockType.Air
end

return BlockRegistry
