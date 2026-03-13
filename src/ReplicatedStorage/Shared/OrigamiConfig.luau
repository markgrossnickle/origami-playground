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
	{ key = "hat", display = "Hat", icon = "🎩" },
	{ key = "prop", display = "Prop", icon = "🎭" },
	{ key = "raw", display = "Raw", icon = "📝" },
	{ key = "animation", display = "Animate", icon = "🎬" },
}

-- AI models
OrigamiConfig.MODELS = {
	{ key = "haiku", display = "Haiku" },
	{ key = "sonnet", display = "Sonnet" },
	{ key = "opus", display = "Opus" },
	{ key = "flash_lite", display = "Flash" },
	{ key = "gpt4o_mini", display = "GPT4o" },
	{ key = "test", display = "Test All" },
}

-- Art styles
OrigamiConfig.STYLES = {
	{ key = "origami", display = "Origami" },
	{ key = "lowpoly", display = "Low Poly" },
	{ key = "voxel", display = "Voxel" },
	{ key = "balloon", display = "Balloon" },
	{ key = "wireframe", display = "Wireframe" },
	{ key = "crystal", display = "Crystal" },
	{ key = "plush", display = "Plush" },
	{ key = "steampunk", display = "Steampunk" },
	{ key = "pixel", display = "Pixel" },
	{ key = "neon", display = "Neon" },
	{ key = "freestyle", display = "Freestyle" },
}

-- DM (Dungeon Master) mode
OrigamiConfig.DM = {
	MAX_SCENE_ITEMS = 15,
	MAX_ACTIVE_CREATURES = 20,
	CREATURE_TICK_RATE = 0.05,
	SCENE_RADIUS = 60,
	DEFAULT_MODEL = "sonnet",
}

return OrigamiConfig
