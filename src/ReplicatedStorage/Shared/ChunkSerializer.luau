--!strict
--!native

local ChunkUtil = require(script.Parent.ChunkUtil)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK

local ChunkSerializer = {}

-- RLE compress a chunk buffer into a smaller buffer
-- Format: [blockType: u8][runLength: u16] repeated
-- Single-pass: writes directly to buffer, no temp table allocations
function ChunkSerializer.compress(blocks: buffer): buffer
	local maxSize = BLOCKS_PER_CHUNK * 3
	local temp = buffer.create(maxSize)
	local offset = 0

	local currentType = buffer.readu8(blocks, 0)
	local currentCount = 1

	for i = 1, BLOCKS_PER_CHUNK - 1 do
		local blockType = buffer.readu8(blocks, i)
		if blockType == currentType and currentCount < 65535 then
			currentCount += 1
		else
			buffer.writeu8(temp, offset, currentType)
			buffer.writeu16(temp, offset + 1, currentCount)
			offset += 3
			currentType = blockType
			currentCount = 1
		end
	end
	buffer.writeu8(temp, offset, currentType)
	buffer.writeu16(temp, offset + 1, currentCount)
	offset += 3

	local compressed = buffer.create(offset)
	buffer.copy(compressed, 0, temp, 0, offset)
	return compressed
end

-- Decompress RLE buffer back to full chunk buffer
-- Uses buffer.fill for bulk writes instead of byte-by-byte
function ChunkSerializer.decompress(compressed: buffer): buffer
	local blocks = buffer.create(BLOCKS_PER_CHUNK)
	local readOffset = 0
	local writeOffset = 0
	local compressedLen = buffer.len(compressed)

	while readOffset < compressedLen and writeOffset < BLOCKS_PER_CHUNK do
		local blockType = buffer.readu8(compressed, readOffset)
		local runLength = buffer.readu16(compressed, readOffset + 1)
		readOffset += 3

		local count = math.min(runLength, BLOCKS_PER_CHUNK - writeOffset)
		buffer.fill(blocks, writeOffset, blockType, count)
		writeOffset += count
	end

	return blocks
end

-- Encode a chunk delta (sparse changes) into a compact buffer
-- Avoids temp table allocation by counting first, then writing directly
function ChunkSerializer.encodeDelta(delta: { [number]: number }): buffer
	local count = 0
	for _ in delta do
		count += 1
	end

	local buf = buffer.create(2 + count * 3)
	buffer.writeu16(buf, 0, count)

	local offset = 2
	for flatIndex, blockType in delta do
		buffer.writeu16(buf, offset, flatIndex)
		buffer.writeu8(buf, offset + 2, blockType)
		offset += 3
	end

	return buf
end

-- Decode delta buffer back to table
function ChunkSerializer.decodeDelta(buf: buffer): { [number]: number }
	local delta: { [number]: number } = {}
	local count = buffer.readu16(buf, 0)
	local offset = 2

	for _ = 1, count do
		local flatIndex = buffer.readu16(buf, offset)
		local blockType = buffer.readu8(buf, offset + 2)
		delta[flatIndex] = blockType
		offset += 3
	end

	return delta
end

-- Convert a full chunk buffer to a string for DataStore storage
function ChunkSerializer.bufferToString(buf: buffer): string
	local compressed = ChunkSerializer.compress(buf)
	local len = buffer.len(compressed)
	local chars = table.create(len)
	for i = 0, len - 1 do
		chars[i + 1] = string.char(buffer.readu8(compressed, i))
	end
	return table.concat(chars)
end

-- Convert a DataStore string back to a full chunk buffer
function ChunkSerializer.stringToBuffer(str: string): buffer
	local len = #str
	local compressed = buffer.create(len)
	for i = 1, len do
		buffer.writeu8(compressed, i - 1, string.byte(str, i))
	end
	return ChunkSerializer.decompress(compressed)
end

-- Serialize delta table for DataStore (JSON-compatible)
function ChunkSerializer.serializeDelta(delta: { [number]: number }): { [string]: number }
	local result: { [string]: number } = {}
	for flatIndex, blockType in delta do
		result[tostring(flatIndex)] = blockType
	end
	return result
end

-- Deserialize delta from DataStore
function ChunkSerializer.deserializeDelta(data: { [string]: number }): { [number]: number }
	local delta: { [number]: number } = {}
	for flatIndexStr, blockType in data do
		local flatIndex = tonumber(flatIndexStr)
		if flatIndex then
			delta[flatIndex] = blockType
		end
	end
	return delta
end

return ChunkSerializer
