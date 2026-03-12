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

return OrigamiConfig
