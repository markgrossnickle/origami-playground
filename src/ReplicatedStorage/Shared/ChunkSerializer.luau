--!strict
-- ChunkSerializer: RLE compression for chunk block data + delta serialization

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local BLOCKS_PER_CHUNK = MiningConfig.BLOCKS_PER_CHUNK

local ChunkSerializer = {}

function ChunkSerializer.compress(blocks: buffer): buffer
	local runs = {}
	local runCount = 0
	local currentType = buffer.readu8(blocks, 0)
	local currentRun = 1

	for i = 1, BLOCKS_PER_CHUNK - 1 do
		local blockType = buffer.readu8(blocks, i)
		if blockType == currentType and currentRun < 65535 then
			currentRun += 1
		else
			runCount += 1
			runs[runCount] = { currentType, currentRun }
			currentType = blockType
			currentRun = 1
		end
	end
	runCount += 1
	runs[runCount] = { currentType, currentRun }

	local compressed = buffer.create(runCount * 3)
	for i = 1, runCount do
		local offset = (i - 1) * 3
		buffer.writeu8(compressed, offset, runs[i][1])
		buffer.writeu16(compressed, offset + 1, runs[i][2])
	end
	return compressed
end

function ChunkSerializer.decompress(compressed: buffer): buffer
	local blocks = buffer.create(BLOCKS_PER_CHUNK)
	local compressedLen = buffer.len(compressed)
	local writeOffset = 0
	local readOffset = 0

	while readOffset < compressedLen do
		local blockType = buffer.readu8(compressed, readOffset)
		local runLength = buffer.readu16(compressed, readOffset + 1)
		readOffset += 3
		for _ = 1, runLength do
			if writeOffset < BLOCKS_PER_CHUNK then
				buffer.writeu8(blocks, writeOffset, blockType)
				writeOffset += 1
			end
		end
	end
	return blocks
end

function ChunkSerializer.serializeDelta(delta: { [number]: number }): { [string]: number }
	local serialized = {}
	for index, blockType in delta do
		serialized[tostring(index)] = blockType
	end
	return serialized
end

function ChunkSerializer.deserializeDelta(data: { [string]: number }): { [number]: number }
	local delta = {}
	for indexStr, blockType in data do
		local index = tonumber(indexStr)
		if index then
			delta[index] = blockType
		end
	end
	return delta
end

return ChunkSerializer
