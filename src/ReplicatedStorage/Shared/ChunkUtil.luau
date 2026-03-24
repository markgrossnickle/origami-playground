--!strict
-- ChunkUtil: Coordinate conversion utilities for chunk-based world

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local ChunkUtil = {}

local CHUNK_SIZE = MiningConfig.CHUNK_SIZE
local BLOCK_SIZE = MiningConfig.BLOCK_SIZE
local CHUNK_STUDS = MiningConfig.CHUNK_STUDS

function ChunkUtil.worldToChunk(worldX: number, worldY: number, worldZ: number): (number, number, number)
	return math.floor(worldX / CHUNK_STUDS), math.floor(worldY / CHUNK_STUDS), math.floor(worldZ / CHUNK_STUDS)
end

function ChunkUtil.chunkToWorld(cx: number, cy: number, cz: number): (number, number, number)
	return cx * CHUNK_STUDS, cy * CHUNK_STUDS, cz * CHUNK_STUDS
end

function ChunkUtil.worldToLocalBlock(worldX: number, worldY: number, worldZ: number): (number, number, number)
	local lx = math.floor(worldX / BLOCK_SIZE) % CHUNK_SIZE
	local ly = math.floor(worldY / BLOCK_SIZE) % CHUNK_SIZE
	local lz = math.floor(worldZ / BLOCK_SIZE) % CHUNK_SIZE
	if lx < 0 then
		lx = lx + CHUNK_SIZE
	end
	if ly < 0 then
		ly = ly + CHUNK_SIZE
	end
	if lz < 0 then
		lz = lz + CHUNK_SIZE
	end
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
	return cx .. "," .. cy .. "," .. cz
end

function ChunkUtil.parseChunkKey(key: string): (number, number, number)
	local parts = string.split(key, ",")
	return tonumber(parts[1]) :: number, tonumber(parts[2]) :: number, tonumber(parts[3]) :: number
end

function ChunkUtil.blockWorldPosition(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number): Vector3
	local wx = cx * CHUNK_STUDS + lx * BLOCK_SIZE + BLOCK_SIZE / 2
	local wy = cy * CHUNK_STUDS + ly * BLOCK_SIZE + BLOCK_SIZE / 2
	local wz = cz * CHUNK_STUDS + lz * BLOCK_SIZE + BLOCK_SIZE / 2
	return Vector3.new(wx, wy, wz)
end

function ChunkUtil.regionKey(cx: number, cy: number, cz: number): string
	local rx = math.floor(cx / 4)
	local ry = math.floor(cy / 4)
	local rz = math.floor(cz / 4)
	return rx .. "," .. ry .. "," .. rz
end

function ChunkUtil.worldPosToChunk(worldPos: Vector3): (number, number, number)
	local offset = MiningConfig.WORLD_OFFSET
	local wx = worldPos.X - offset.X
	local wy = worldPos.Y - offset.Y
	local wz = worldPos.Z - offset.Z
	return ChunkUtil.worldToChunk(wx, wy, wz)
end

return ChunkUtil
