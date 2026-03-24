--!strict
-- ChunkSerializer: RLE compression and delta serialization for chunk data

local ChunkSerializer = {}

-- RLE compress a block buffer (4096 u8 values) into a compact buffer
-- Format: repeated [u8 blockType][u16 runLength] triples
function ChunkSerializer.compress(blocks: buffer): buffer
	local size = buffer.len(blocks)
	local temp = buffer.create(size * 3)
	local writePos = 0

	local i = 0
	while i < size do
		local blockType = buffer.readu8(blocks, i)
		local runLength = 1
		while i + runLength < size and buffer.readu8(blocks, i + runLength) == blockType and runLength < 65535 do
			runLength = runLength + 1
		end

		buffer.writeu8(temp, writePos, blockType)
		buffer.writeu16(temp, writePos + 1, runLength)
		writePos = writePos + 3
		i = i + runLength
	end

	local result = buffer.create(writePos)
	buffer.copy(result, 0, temp, 0, writePos)
	return result
end

-- Decompress RLE buffer back to 4096-entry block buffer
function ChunkSerializer.decompress(compressed: buffer): buffer
	local blocks = buffer.create(4096)
	local readPos = 0
	local writePos = 0
	local compLen = buffer.len(compressed)

	while readPos < compLen do
		local blockType = buffer.readu8(compressed, readPos)
		local runLength = buffer.readu16(compressed, readPos + 1)
		readPos = readPos + 3

		for _ = 1, runLength do
			if writePos < 4096 then
				buffer.writeu8(blocks, writePos, blockType)
				writePos = writePos + 1
			end
		end
	end

	return blocks
end

-- Serialize delta for DataStore persistence
function ChunkSerializer.serializeDelta(delta: { [number]: number }): { [string]: number }
	local result = {}
	for index, blockType in pairs(delta) do
		result[tostring(index)] = blockType
	end
	return result
end

-- Deserialize delta from DataStore format
function ChunkSerializer.deserializeDelta(data: { [string]: number }): { [number]: number }
	local result = {}
	for indexStr, blockType in pairs(data) do
		local index = tonumber(indexStr)
		if index then
			result[index] = blockType
		end
	end
	return result
end

return ChunkSerializer
