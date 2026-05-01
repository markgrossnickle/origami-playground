--!strict
--!native

local ChunkUtil = {}

ChunkUtil.CHUNK_SIZE = 16
ChunkUtil.BLOCK_SIZE = 5
ChunkUtil.CHUNK_STUDS = ChunkUtil.CHUNK_SIZE * ChunkUtil.BLOCK_SIZE -- 80
ChunkUtil.BLOCKS_PER_CHUNK = ChunkUtil.CHUNK_SIZE ^ 3 -- 4096

-- Streaming bounds (in chunks). MUST equal worldRadiusChunks * 2 in
-- WorldGenModule, otherwise outer chunks won't stream and players in
-- regions / outer Wilds will see empty space.
ChunkUtil.MINE_EXTENT_X = 140 -- chunks (matches WorldGenModule.worldRadiusChunks=70)
ChunkUtil.MINE_EXTENT_Z = 140 -- chunks

function ChunkUtil.worldToChunk(worldX: number, worldY: number, worldZ: number): (number, number, number)
	local cx = math.floor(worldX / ChunkUtil.CHUNK_STUDS)
	local cy = math.floor(worldY / ChunkUtil.CHUNK_STUDS)
	local cz = math.floor(worldZ / ChunkUtil.CHUNK_STUDS)
	return cx, cy, cz
end

function ChunkUtil.chunkToWorld(cx: number, cy: number, cz: number): Vector3
	return Vector3.new(cx * ChunkUtil.CHUNK_STUDS, cy * ChunkUtil.CHUNK_STUDS, cz * ChunkUtil.CHUNK_STUDS)
end

function ChunkUtil.chunkCenter(cx: number, cy: number, cz: number): Vector3
	local half = ChunkUtil.CHUNK_STUDS / 2
	return Vector3.new(
		cx * ChunkUtil.CHUNK_STUDS + half,
		cy * ChunkUtil.CHUNK_STUDS + half,
		cz * ChunkUtil.CHUNK_STUDS + half
	)
end

function ChunkUtil.worldToLocalBlock(worldX: number, worldY: number, worldZ: number): (number, number, number)
	local lx = math.floor(worldX / ChunkUtil.BLOCK_SIZE) % ChunkUtil.CHUNK_SIZE
	local ly = math.floor(worldY / ChunkUtil.BLOCK_SIZE) % ChunkUtil.CHUNK_SIZE
	local lz = math.floor(worldZ / ChunkUtil.BLOCK_SIZE) % ChunkUtil.CHUNK_SIZE
	return lx, ly, lz
end

function ChunkUtil.flatIndex(lx: number, ly: number, lz: number): number
	return ly * 256 + lz * 16 + lx
end

function ChunkUtil.fromFlatIndex(index: number): (number, number, number)
	local ly = math.floor(index / 256)
	local remainder = index % 256
	local lz = math.floor(remainder / 16)
	local lx = remainder % 16
	return lx, ly, lz
end

-- Chunk keys are packed as a single number for cheap hashtable lookups and to
-- avoid per-call string allocations in hot paths (mining raycast, chunk stream
-- polling, LOD re-eval). Biased so the full signed range is non-negative.
-- Axis range: ±32768 chunks, enough for any conceivable world size.
local CHUNK_KEY_BIAS = 32768
local CHUNK_KEY_AXIS = 65536 -- 2^16
local CHUNK_KEY_SCALE_Y = CHUNK_KEY_AXIS
local CHUNK_KEY_SCALE_X = CHUNK_KEY_AXIS * CHUNK_KEY_AXIS -- 2^32, safely under 2^53

function ChunkUtil.chunkKey(cx: number, cy: number, cz: number): number
	return (cx + CHUNK_KEY_BIAS) * CHUNK_KEY_SCALE_X + (cy + CHUNK_KEY_BIAS) * CHUNK_KEY_SCALE_Y + (cz + CHUNK_KEY_BIAS)
end

function ChunkUtil.parseChunkKey(key: number): (number, number, number)
	local biasedZ = key % CHUNK_KEY_AXIS
	local key2 = (key - biasedZ) / CHUNK_KEY_AXIS
	local biasedY = key2 % CHUNK_KEY_AXIS
	local biasedX = (key2 - biasedY) / CHUNK_KEY_AXIS
	return biasedX - CHUNK_KEY_BIAS, biasedY - CHUNK_KEY_BIAS, biasedZ - CHUNK_KEY_BIAS
end

-- Convert a legacy "cx,cy,cz" string (as stored in DataStore) to a packed key.
-- Returns nil if the string is malformed.
function ChunkUtil.chunkKeyFromString(s: string): number?
	local parts = string.split(s, ",")
	if #parts ~= 3 then
		return nil
	end
	local cx = tonumber(parts[1])
	local cy = tonumber(parts[2])
	local cz = tonumber(parts[3])
	if not cx or not cy or not cz then
		return nil
	end
	return ChunkUtil.chunkKey(cx, cy, cz)
end

-- Convert a packed key back to "cx,cy,cz" string for DataStore persistence.
function ChunkUtil.chunkKeyToString(key: number): string
	local cx, cy, cz = ChunkUtil.parseChunkKey(key)
	return string.format("%d,%d,%d", cx, cy, cz)
end

function ChunkUtil.worldToFlatIndex(worldX: number, worldY: number, worldZ: number): number
	local lx, ly, lz = ChunkUtil.worldToLocalBlock(worldX, worldY, worldZ)
	return ChunkUtil.flatIndex(lx, ly, lz)
end

function ChunkUtil.blockWorldPosition(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number): Vector3
	local baseX = cx * ChunkUtil.CHUNK_STUDS
	local baseY = cy * ChunkUtil.CHUNK_STUDS
	local baseZ = cz * ChunkUtil.CHUNK_STUDS
	local halfBlock = ChunkUtil.BLOCK_SIZE / 2
	return Vector3.new(
		baseX + lx * ChunkUtil.BLOCK_SIZE + halfBlock,
		baseY + ly * ChunkUtil.BLOCK_SIZE + halfBlock,
		baseZ + lz * ChunkUtil.BLOCK_SIZE + halfBlock
	)
end

function ChunkUtil.isInMineBounds(cx: number, cz: number): boolean
	local halfX = ChunkUtil.MINE_EXTENT_X / 2
	local halfZ = ChunkUtil.MINE_EXTENT_Z / 2
	return cx >= -halfX and cx < halfX and cz >= -halfZ and cz < halfZ
end

function ChunkUtil.depthFromWorldY(worldY: number): number
	return -worldY
end

function ChunkUtil.regionKey(cx: number, cy: number, cz: number): string
	local rx = math.floor(cx / 8)
	local ry = math.floor(cy / 8)
	local rz = math.floor(cz / 8)
	return string.format("WorldDeltas_region_%d,%d,%d", rx, ry, rz)
end

return ChunkUtil
