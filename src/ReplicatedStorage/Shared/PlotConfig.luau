--[[
	DEPRECATED in Phase 2 (Zone System / GDD lock).

	Live consumers have moved to:
		* PlaceableBlocks  (placeable items + visual metadata)
		* RegionConfig     (slot geometry, ring layout)

	This module is kept only for the deprecated PlotService in
	Services/_deprecated/. Do NOT add new requires. Delete after one
	full live cycle confirms no callers remain.
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
	paper = { color = { 255, 250, 235 }, material = "SmoothPlastic", name = "Paper" },
	pulp = { color = { 160, 140, 110 }, material = "Ground", name = "Pulp" },
	folded_stone = { color = { 140, 145, 155 }, material = "Slate", name = "Folded Stone" },
	origami_rock = { color = { 120, 100, 130 }, material = "Granite", name = "Origami Rock" },
	crystal = { color = { 150, 200, 255 }, material = "Glass", name = "Crystal" },
	void_stone = { color = { 25, 15, 40 }, material = "Basalt", name = "Void Stone" },
	prismatic_block = { color = { 255, 200, 255 }, material = "Neon", name = "Prismatic Block" },
	wood = { color = { 140, 100, 60 }, material = "Wood", name = "Wood" },
}

-- Compute the world origin of a plot from its grid index (0-based).
function PlotConfig.getPlotOrigin(plotIndex: number): Vector3
	local col = plotIndex % PlotConfig.GRID_COLUMNS
	local row = math.floor(plotIndex / PlotConfig.GRID_COLUMNS)
	local x = PlotConfig.GRID_ORIGIN_X + col * PlotConfig.GRID_SPACING
	local z = PlotConfig.GRID_ORIGIN_Z + row * PlotConfig.GRID_SPACING
	return Vector3.new(x, PlotConfig.GROUND_Y, z)
end

-- Convert a local block coordinate (0-based) to world position (center of block).
function PlotConfig.localToWorld(plotOrigin: Vector3, lx: number, ly: number, lz: number): Vector3
	return plotOrigin
		+ Vector3.new(
			lx * PlotConfig.BLOCK_SIZE + PlotConfig.BLOCK_SIZE / 2,
			ly * PlotConfig.BLOCK_SIZE + PlotConfig.BLOCK_SIZE / 2,
			lz * PlotConfig.BLOCK_SIZE + PlotConfig.BLOCK_SIZE / 2
		)
end

-- Convert world position to local block coordinate (floored).
function PlotConfig.worldToLocal(plotOrigin: Vector3, worldPos: Vector3): (number, number, number)
	local rel = worldPos - plotOrigin
	local lx = math.floor(rel.X / PlotConfig.BLOCK_SIZE)
	local ly = math.floor(rel.Y / PlotConfig.BLOCK_SIZE)
	local lz = math.floor(rel.Z / PlotConfig.BLOCK_SIZE)
	return lx, ly, lz
end

-- Check if local coordinates are within plot bounds.
function PlotConfig.isInBounds(lx: number, ly: number, lz: number): boolean
	return lx >= 0
		and lx < PlotConfig.PLOT_SIZE_BLOCKS
		and ly >= 0
		and ly < PlotConfig.PLOT_HEIGHT_BLOCKS
		and lz >= 0
		and lz < PlotConfig.PLOT_SIZE_BLOCKS
end

return PlotConfig
