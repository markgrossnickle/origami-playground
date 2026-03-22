local OrigamiConfig = {}

-- API endpoint (set via Attribute on OrigamiService in Studio, or override here)
OrigamiConfig.API_URL = ""

-- API key (set via Attribute on OrigamiService in Studio)
OrigamiConfig.API_KEY = ""

-- Rate limiting
OrigamiConfig.COOLDOWN_SECONDS = 10

-- Model constraints
OrigamiConfig.MAX_PARTS_PER_MODEL = 50

-- Placement
OrigamiConfig.PLACEMENT_DISTANCE = 10

-- Categories
OrigamiConfig.CATEGORIES = {
	{ key = "creature", display = "Creature", icon = "🐉" },
	{ key = "avatar", display = "Avatar", icon = "🧑" },
	{ key = "vehicle", display = "Vehicle", icon = "🚗" },
	{ key = "tool", display = "Tool", icon = "🔧" },
	{ key = "accessory", display = "Accessory", icon = "🎩" },
	{ key = "prop", display = "Prop", icon = "🎭" },
	{ key = "animation", display = "Animate", icon = "🎬" },
}

-- Catalog types (for filtering/browsing)
OrigamiConfig.TYPES = {
	{ key = "all", display = "All" },
	{ key = "tower", display = "Tower" },
	{ key = "minion", display = "Minion" },
	{ key = "battler", display = "Battler" },
	{ key = "card", display = "Card" },
	{ key = "creature", display = "Creature" },
	{ key = "avatar", display = "Avatar" },
	{ key = "vehicle", display = "Vehicle" },
	{ key = "tool", display = "Tool" },
	{ key = "accessory", display = "Accessory" },
	{ key = "prop", display = "Prop" },
}

-- AI models (cheapest → most expensive)
OrigamiConfig.MODELS = {
	{ key = "flash25_lite", display = "FL 2.5 Lite" },
	{ key = "flash3", display = "Gem 3 Flash" },
	{ key = "gemini_pro", display = "Gem 3.1 Pro" },
	{ key = "opus", display = "Opus 4.6" },
	{ key = "test", display = "Test All" },
}

-- Art styles
OrigamiConfig.STYLES = {
	{ key = "lowpoly", display = "Low Poly" },
	{ key = "voxel", display = "Voxel" },
	{ key = "balloon", display = "Balloon" },
	{ key = "chibi", display = "Chibi" },
	{ key = "lego", display = "Lego" },
	{ key = "plastic", display = "Plastic" },
	{ key = "scifi", display = "Sci-Fi" },
	{ key = "spooky", display = "Spooky" },
	{ key = "candy", display = "Candy" },
	{ key = "freestyle", display = "Freestyle" },
}

-- Crane costs per model (new LLM generations)
-- Actual API costs: Lite ~$0.001, Flash ~$0.05, Pro ~$0.20, Opus ~$0.40
OrigamiConfig.CRANE_COSTS = {
	flash25_lite = 1,
	flash3 = 5,
	gemini_pro = 20,
	opus = 40,
	test = 10,
}

-- Emote generation cost
OrigamiConfig.CRANE_COSTS.emote_generation = 1

-- Breeding cost (Cranes per player)
OrigamiConfig.BREEDING_COST = 2

-- Folds cost to spawn a cached catalog item
OrigamiConfig.CACHED_ITEM_COST = 10

-- Shop costs
OrigamiConfig.PAPER_COST_PER_CREATION = 1 -- Paper Tokens for Workshop (FL 2.5 Lite)
OrigamiConfig.PRO_CREATION_PRODUCT_ID = 0 -- DevProduct ID for Atelier (Gem 3.1 Pro) — set to real ID when ready

return OrigamiConfig
