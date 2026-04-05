--[[
	PlotConfig — surface plot configuration.
	32x32 block grid (160x160 studs), 16 blocks tall, 500 max blocks, 5 max creatures.
	Plots positioned far from mine area on a grid.
]]

local PlotConfig = {}

-- Plot dimensions
PlotConfig.PLOT_SIZE_BLOCKS = 32 -- width/depth in blocks
PlotConfig.PLOT_HEIGHT_BLOCKS = 16 -- max height in blocks
PlotConfig.BLOCK_SIZE = 5 -- studs per block (matches mining grid)
PlotConfig.PLOT_SIZE_STUDS = PlotConfig.PLOT_SIZE_BLOCKS * PlotConfig.BLOCK_SIZE -- 160
PlotConfig.PLOT_HEIGHT_STUDS = PlotConfig.PLOT_HEIGHT_BLOCKS * PlotConfig.BLOCK_SIZE -- 80

-- Limits
PlotConfig.MAX_BLOCKS = 500
PlotConfig.MAX_CREATURES = 5

-- Grid placement (far from mine area at origin)
PlotConfig.GRID_ORIGIN_X = -80 -- near spawn
PlotConfig.GRID_ORIGIN_Z = -80
PlotConfig.GRID_SPACING = 200 -- studs between plot centers
PlotConfig.GRID_COLUMNS = 20 -- plots per row before wrapping

-- Ground level for plots
PlotConfig.GROUND_Y = 5

-- Placeable blocks: mining material itemId → visual config
-- Players can place blocks using materials from their MiningInventory
PlotConfig.PLACEABLE_BLOCKS = {
	paper_scrap = { color = { 245, 240, 230 }, material = "SmoothPlastic", name = "Paper" },
	cardboard = { color = { 180, 140, 90 }, material = "SmoothPlastic", name = "Cardboard" },
	wood = { color = { 140, 100, 60 }, material = "Wood", name = "Wood" },
	dried_pulp = { color = { 200, 180, 150 }, material = "SmoothPlastic", name = "Dried Pulp" },
	compressed_pulp = { color = { 160, 140, 110 }, material = "SmoothPlastic", name = "Compressed Pulp" },
	clay_chunk = { color = { 180, 160, 140 }, material = "Slate", name = "Clay" },
	folded_stone = { color = { 140, 140, 160 }, material = "Slate", name = "Folded Stone" },
	quartz_shard = { color = { 220, 220, 240 }, material = "Glass", name = "Quartz" },
	paper_crystal = { color = { 200, 230, 255 }, material = "Neon", name = "Paper Crystal" },
	ink_stone = { color = { 40, 40, 60 }, material = "Slate", name = "Ink Stone" },
	origami_rock = { color = { 100, 120, 100 }, material = "Slate", name = "Origami Rock" },
	gem_fragment = { color = { 180, 80, 255 }, material = "Neon", name = "Gem" },
	foil_ore = { color = { 200, 200, 210 }, material = "Metal", name = "Foil" },
	ruby_paper = { color = { 220, 50, 50 }, material = "Neon", name = "Ruby Paper" },
	crystal_shard = { color = { 100, 200, 255 }, material = "Glass", name = "Crystal" },
	foil_sheet = { color = { 210, 210, 220 }, material = "Metal", name = "Foil Sheet" },
	metal_origami = { color = { 170, 170, 180 }, material = "Metal", name = "Metal Origami" },
	sapphire_crystal = { color = { 60, 100, 255 }, material = "Neon", name = "Sapphire" },
	void_stone = { color = { 30, 20, 50 }, material = "Slate", name = "Void Stone" },
	dark_paper = { color = { 50, 40, 60 }, material = "SmoothPlastic", name = "Dark Paper" },
	shadow_fold = { color = { 40, 30, 70 }, material = "SmoothPlastic", name = "Shadow Fold" },
	void_crystal = { color = { 80, 40, 120 }, material = "Neon", name = "Void Crystal" },
	prismatic_shard = { color = { 255, 200, 255 }, material = "Neon", name = "Prismatic" },
	core_fragment = { color = { 255, 160, 60 }, material = "Neon", name = "Core Fragment" },
	rainbow_paper = { color = { 255, 180, 200 }, material = "Neon", name = "Rainbow Paper" },
}

--- Compute the world origin of a plot from its grid index (0-based).
function PlotConfig.getPlotOrigin(plotIndex: number): Vector3
	local col = plotIndex % PlotConfig.GRID_COLUMNS
	local row = math.floor(plotIndex / PlotConfig.GRID_COLUMNS)
	local x = PlotConfig.GRID_ORIGIN_X + col * PlotConfig.GRID_SPACING
	local z = PlotConfig.GRID_ORIGIN_Z + row * PlotConfig.GRID_SPACING
	return Vector3.new(x, PlotConfig.GROUND_Y, z)
end

--- Convert a local block coordinate (0-based) to world position (center of block).
function PlotConfig.localToWorld(plotOrigin: Vector3, lx: number, ly: number, lz: number): Vector3
	return plotOrigin + Vector3.new(
		lx * PlotConfig.BLOCK_SIZE + PlotConfig.BLOCK_SIZE / 2,
		ly * PlotConfig.BLOCK_SIZE + PlotConfig.BLOCK_SIZE / 2,
		lz * PlotConfig.BLOCK_SIZE + PlotConfig.BLOCK_SIZE / 2
	)
end

--- Convert world position to local block coordinate (floored).
function PlotConfig.worldToLocal(plotOrigin: Vector3, worldPos: Vector3): (number, number, number)
	local rel = worldPos - plotOrigin
	local lx = math.floor(rel.X / PlotConfig.BLOCK_SIZE)
	local ly = math.floor(rel.Y / PlotConfig.BLOCK_SIZE)
	local lz = math.floor(rel.Z / PlotConfig.BLOCK_SIZE)
	return lx, ly, lz
end

--- Check if local coordinates are within plot bounds.
function PlotConfig.isInBounds(lx: number, ly: number, lz: number): boolean
	return lx >= 0 and lx < PlotConfig.PLOT_SIZE_BLOCKS
		and ly >= 0 and ly < PlotConfig.PLOT_HEIGHT_BLOCKS
		and lz >= 0 and lz < PlotConfig.PLOT_SIZE_BLOCKS
end

return PlotConfig
