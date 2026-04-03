--!strict
--!native

local ChunkUtil = {}

ChunkUtil.CHUNK_SIZE = 16
ChunkUtil.BLOCK_SIZE = 5
ChunkUtil.CHUNK_STUDS = ChunkUtil.CHUNK_SIZE * ChunkUtil.BLOCK_SIZE -- 80
ChunkUtil.BLOCKS_PER_CHUNK = ChunkUtil.CHUNK_SIZE ^ 3 -- 4096

ChunkUtil.MINE_EXTENT_X = 32 -- chunks (island world radius * 2)
ChunkUtil.MINE_EXTENT_Z = 32 -- chunks

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

function ChunkUtil.chunkKey(cx: number, cy: number, cz: number): string
	return string.format("%d,%d,%d", cx, cy, cz)
end

function ChunkUtil.parseChunkKey(key: string): (number, number, number)
	local parts = string.split(key, ",")
	return tonumber(parts[1]) :: number, tonumber(parts[2]) :: number, tonumber(parts[3]) :: number
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
