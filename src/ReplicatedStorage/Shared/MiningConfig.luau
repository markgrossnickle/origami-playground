--!strict
-- MiningConfig: Constants for the mining world

local MiningConfig = {}

-- Chunk dimensions
MiningConfig.CHUNK_SIZE = 16
MiningConfig.BLOCK_SIZE = 4
MiningConfig.CHUNK_STUDS = 64 -- CHUNK_SIZE * BLOCK_SIZE
MiningConfig.BLOCKS_PER_CHUNK = 4096 -- CHUNK_SIZE ^ 3

-- Streaming
MiningConfig.STREAM_RADIUS_H = 3 -- reduced from 4: wedge pairs double part count
MiningConfig.STREAM_RADIUS_V = 2
MiningConfig.MAX_CHUNKS_PER_FRAME = 3

-- World bounds
MiningConfig.WORLD_OFFSET = Vector3.new(10000, 0, 0)
MiningConfig.WORLD_HEIGHT_CHUNKS = 4
MiningConfig.WORLD_WIDTH_CHUNKS = 24

-- Mining
MiningConfig.REACH_TOLERANCE = 10
MiningConfig.MINE_TICK_RATE = 0.2 -- seconds between mine requests

-- Tool tiers (paper-themed)
MiningConfig.TOOL_TIERS = {
	{
		tier = 1,
		name = "Paper Scissors",
		power = 1,
		speed = 1.0,
		color = Color3.fromRGB(220, 220, 220),
	},
	{
		tier = 2,
		name = "Cardboard Cutter",
		power = 2,
		speed = 1.2,
		color = Color3.fromRGB(180, 140, 90),
	},
	{
		tier = 3,
		name = "Metal Shears",
		power = 4,
		speed = 1.5,
		color = Color3.fromRGB(160, 160, 175),
	},
	{
		tier = 4,
		name = "Foil Blade",
		power = 8,
		speed = 1.8,
		color = Color3.fromRGB(200, 180, 60),
	},
	{
		tier = 5,
		name = "Crystal Pick",
		power = 16,
		speed = 2.0,
		color = Color3.fromRGB(120, 200, 255),
	},
}

return MiningConfig
