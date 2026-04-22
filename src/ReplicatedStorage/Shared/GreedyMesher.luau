--!strict
--!native

local ChunkUtil = require(script.Parent.ChunkUtil)
local BlockType = require(script.Parent.Enums.BlockType)

local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local flatIndex = ChunkUtil.flatIndex

--[=[
	@class GreedyMesher

	Greedy-meshing sweep for chunk rendering. Takes a chunk's block buffer and
	returns a list of merged regions. Adjacent same-type exposed blocks collapse
	into a single region along X then Z. Y extension is intentionally skipped
	(see docs/GREEDY_PARTS_DESIGN.md for the rationale).

	Region fields are inclusive on both ends. A single exposed block becomes a
	region with minLx == maxLx etc.

	Exception list: `MushroomCap`, `ShelfBracket`, and `WillowVine` are always
	emitted as 1x1x1 regions so the renderer can keep their per-block behavior
	(bouncy `.Touched` handlers and depth-based vine taper).
]=]

export type Region = {
	blockTypeId: number,
	minLx: number,
	minLy: number,
	minLz: number,
	maxLx: number,
	maxLy: number,
	maxLz: number,
}

local GreedyMesher = {}

-- Blocks that are never merged (must stay per-block in the renderer).
local NON_MERGEABLE: { [number]: boolean } = {
	[BlockType.MushroomCap] = true,
	[BlockType.ShelfBracket] = true,
	[BlockType.WillowVine] = true,
}

GreedyMesher.NON_MERGEABLE = NON_MERGEABLE

-- Exposure: a non-air block is exposed if any of its 6 neighbors is air or
-- out-of-chunk (out-of-chunk counts as exposed so chunk-boundary faces render).
local function isExposedAt(blocks: buffer, lx: number, ly: number, lz: number): boolean
	local id = buffer.readu8(blocks, flatIndex(lx, ly, lz))
	if id == BlockType.Air then
		return false
	end

	if lx <= 0 or buffer.readu8(blocks, flatIndex(lx - 1, ly, lz)) == BlockType.Air then
		return true
	end
	if lx >= CHUNK_SIZE - 1 or buffer.readu8(blocks, flatIndex(lx + 1, ly, lz)) == BlockType.Air then
		return true
	end
	if ly <= 0 or buffer.readu8(blocks, flatIndex(lx, ly - 1, lz)) == BlockType.Air then
		return true
	end
	if ly >= CHUNK_SIZE - 1 or buffer.readu8(blocks, flatIndex(lx, ly + 1, lz)) == BlockType.Air then
		return true
	end
	if lz <= 0 or buffer.readu8(blocks, flatIndex(lx, ly, lz - 1)) == BlockType.Air then
		return true
	end
	if lz >= CHUNK_SIZE - 1 or buffer.readu8(blocks, flatIndex(lx, ly, lz + 1)) == BlockType.Air then
		return true
	end
	return false
end

GreedyMesher.isExposed = isExposedAt

-- Exposure table: precompute a bitfield (one byte per block, 1 = exposed,
-- 0 = not) so the sweep avoids re-reading neighbors per candidate extension.
local function buildExposureTable(
	blocks: buffer,
	minLx: number,
	minLy: number,
	minLz: number,
	maxLx: number,
	maxLy: number,
	maxLz: number
): buffer
	local exposure = buffer.create(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
	for ly = minLy, maxLy do
		for lz = minLz, maxLz do
			for lx = minLx, maxLx do
				if isExposedAt(blocks, lx, ly, lz) then
					buffer.writeu8(exposure, flatIndex(lx, ly, lz), 1)
				end
			end
		end
	end
	return exposure
end

-- Core sweep. `regions` is an optional pre-allocated output array to append
-- into; this lets callers amortize allocations across re-meshes.
local function sweepBox(
	blocks: buffer,
	minLx: number,
	minLy: number,
	minLz: number,
	maxLx: number,
	maxLy: number,
	maxLz: number,
	regions: { Region }
): { Region }
	local exposure = buildExposureTable(blocks, minLx, minLy, minLz, maxLx, maxLy, maxLz)

	-- visited bitmap: reuse the same buffer type. 1 = already emitted into a region
	-- (or is not a candidate). Scoped to the full chunk to keep indexing trivial.
	local visited = buffer.create(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)

	for ly = minLy, maxLy do
		for lz = minLz, maxLz do
			for lx = minLx, maxLx do
				local idx = flatIndex(lx, ly, lz)
				if buffer.readu8(visited, idx) == 1 then
					continue
				end

				local id = buffer.readu8(blocks, idx)
				if id == BlockType.Air or buffer.readu8(exposure, idx) == 0 then
					buffer.writeu8(visited, idx, 1)
					continue
				end

				-- Non-mergeable blocks: emit a 1x1x1 region immediately.
				if NON_MERGEABLE[id] then
					buffer.writeu8(visited, idx, 1)
					table.insert(regions, {
						blockTypeId = id,
						minLx = lx,
						minLy = ly,
						minLz = lz,
						maxLx = lx,
						maxLy = ly,
						maxLz = lz,
					})
					continue
				end

				-- Extend along +X: same id, exposed, not visited, and not out of box.
				local xEnd = lx
				while xEnd + 1 <= maxLx do
					local nIdx = flatIndex(xEnd + 1, ly, lz)
					if
						buffer.readu8(visited, nIdx) == 1
						or buffer.readu8(blocks, nIdx) ~= id
						or buffer.readu8(exposure, nIdx) == 0
					then
						break
					end
					xEnd += 1
				end

				-- Extend along +Z: each candidate row must match entirely.
				local zEnd = lz
				while zEnd + 1 <= maxLz do
					local rowOk = true
					for x = lx, xEnd do
						local rIdx = flatIndex(x, ly, zEnd + 1)
						if
							buffer.readu8(visited, rIdx) == 1
							or buffer.readu8(blocks, rIdx) ~= id
							or buffer.readu8(exposure, rIdx) == 0
						then
							rowOk = false
							break
						end
					end
					if not rowOk then
						break
					end
					zEnd += 1
				end

				-- Mark all covered cells as visited.
				for z = lz, zEnd do
					for x = lx, xEnd do
						buffer.writeu8(visited, flatIndex(x, ly, z), 1)
					end
				end

				table.insert(regions, {
					blockTypeId = id,
					minLx = lx,
					minLy = ly,
					minLz = lz,
					maxLx = xEnd,
					maxLy = ly,
					maxLz = zEnd,
				})
			end
		end
	end

	return regions
end

--[=[
	Mesh an entire chunk. Returns a freshly allocated list of regions.
]=]
function GreedyMesher.meshChunk(blocks: buffer): { Region }
	local regions: { Region } = {}
	sweepBox(blocks, 0, 0, 0, CHUNK_SIZE - 1, CHUNK_SIZE - 1, CHUNK_SIZE - 1, regions)
	return regions
end

--[=[
	Mesh a sub-box of a chunk. Used for mining-split re-meshes. The caller
	specifies the local-block bounding box (clamped by the mesher to chunk
	bounds). Appends into an existing `regions` array if one is supplied,
	otherwise allocates.
]=]
function GreedyMesher.meshBox(
	blocks: buffer,
	minLx: number,
	minLy: number,
	minLz: number,
	maxLx: number,
	maxLy: number,
	maxLz: number,
	regions: { Region }?
): { Region }
	-- Clamp to chunk bounds.
	if minLx < 0 then
		minLx = 0
	end
	if minLy < 0 then
		minLy = 0
	end
	if minLz < 0 then
		minLz = 0
	end
	if maxLx > CHUNK_SIZE - 1 then
		maxLx = CHUNK_SIZE - 1
	end
	if maxLy > CHUNK_SIZE - 1 then
		maxLy = CHUNK_SIZE - 1
	end
	if maxLz > CHUNK_SIZE - 1 then
		maxLz = CHUNK_SIZE - 1
	end

	local out = regions or ({} :: { Region })
	sweepBox(blocks, minLx, minLy, minLz, maxLx, maxLy, maxLz, out)
	return out
end

return GreedyMesher
