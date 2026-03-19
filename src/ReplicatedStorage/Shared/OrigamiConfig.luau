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
	{ key = "building", display = "Building", icon = "🏠" },
	{ key = "tool", display = "Tool", icon = "🔧" },
	{ key = "accessory", display = "Accessory", icon = "🎩" },
	{ key = "prop", display = "Prop", icon = "🎭" },
	{ key = "raw", display = "Raw", icon = "📝" },
	{ key = "animation", display = "Animate", icon = "🎬" },
	{ key = "emote", display = "Emote", icon = "💃" },
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

-- AI models
OrigamiConfig.MODELS = {
	{ key = "opus", display = "Opus" },
	{ key = "flash_lite", display = "Flash" },
	{ key = "gpt4o_mini", display = "GPT4o" },
	{ key = "gpt_nano", display = "Nano" },
	{ key = "gpt_mini", display = "Mini" },
	{ key = "test", display = "Test All" },
}

-- Art styles
OrigamiConfig.STYLES = {
	{ key = "origami", display = "Origami" },
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
OrigamiConfig.CRANE_COSTS = {
	opus = 5,
	flash_lite = 1,
	gpt4o_mini = 1,
	gpt_nano = 1,
	gpt_mini = 1,
	test = 3, -- sum of the 3 test models
}

-- Emote generation cost
OrigamiConfig.CRANE_COSTS.emote_generation = 1

-- Breeding cost (Cranes per player)
OrigamiConfig.BREEDING_COST = 2

-- Folds cost to spawn a cached catalog item
OrigamiConfig.CACHED_ITEM_COST = 10

return OrigamiConfig
