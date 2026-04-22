--!strict
--!native
--[=[
	@class MeshBuilder
	Face-culled voxel mesh builder. Takes a chunk buffer + LOD and emits
	per-material vertex / triangle / color arrays ready to be uploaded to an
	EditableMesh.

	No Roblox rendering side-effects here — this module is pure CPU work
	so it can be unit-tested and runs under `--!native` compilation.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local CHUNK_STUDS = ChunkUtil.CHUNK_STUDS

local MeshBuilder = {}

-- Neighbor offsets per face direction (for exposure test).
-- Index 1..6 corresponds to +X, -X, +Y, -Y, +Z, -Z.
local NEIGHBOR_DX = { 1, -1, 0, 0, 0, 0 }
local NEIGHBOR_DY = { 0, 0, 1, -1, 0, 0 }
local NEIGHBOR_DZ = { 0, 0, 0, 0, 1, -1 }

-- Face normals (module-level so no per-block allocation)
local NORMAL_PX = Vector3.new(1, 0, 0)
local NORMAL_NX = Vector3.new(-1, 0, 0)
local NORMAL_PY = Vector3.new(0, 1, 0)
local NORMAL_NY = Vector3.new(0, -1, 0)
local NORMAL_PZ = Vector3.new(0, 0, 1)
local NORMAL_NZ = Vector3.new(0, 0, -1)

-- LOD 0 (near) visual variation
local LOD0_MAX_OFFSET = 0.15
local LOD0_TINT_RANGE = 0.07

-- Fixed UVs (unused today, but set so materials that rely on UVs don't render black)
local UV_00 = Vector2.new(0, 0)
local UV_10 = Vector2.new(1, 0)
local UV_11 = Vector2.new(1, 1)
local UV_01 = Vector2.new(0, 1)

-- One material bucket's worth of geometry data, in flat SoA arrays so we can
-- loop `AddVertex` / `AddTriangle` without per-element table allocations.
export type MaterialBucket = {
	material: Enum.Material,
	positions: { Vector3 },
	normals: { Vector3 },
	colors: { Color3 },
	uvs: { Vector2 },
	-- Triangle indices reference the positions/normals/colors/uvs arrays (1-based).
	-- Each triangle is 3 consecutive ints.
	triangles: { number },
}

export type ChunkMeshData = {
	buckets: { [Enum.Material]: MaterialBucket },
	vertexCount: number,
	triangleCount: number,
	exposedFaceCount: number,
}

-- Simple deterministic hash (same shape the old renderer used for visual variation)
local function _hash(a: number, b: number, c: number, d: number): number
	local h = a * 7919 + b * 6271 + c * 4153 + d * 1009
	return (h % 65521) / 65521
end

-- Transparent = air for exposure purposes. In the future we could add
-- non-solid block types here (e.g. water).
local function _isTransparent(blockId: number): boolean
	return blockId == BlockType.Air
end

-- Neighbor lookup that tolerates out-of-chunk (returns nil — caller decides).
-- For now we emit faces at chunk boundaries (conservative; matches old _isExposed).
local function _isNeighborAir(blocks: buffer, nx: number, ny: number, nz: number): boolean
	if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
		return true -- treat out-of-chunk as air (render boundary face)
	end
	return _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(nx, ny, nz)))
end

-- Color tint helper — avoid per-vertex Color3.new when no tint is applied.
local function _tintColor(color: Color3, brightness: number): Color3
	local r = math.clamp(color.R * brightness, 0, 1)
	local g = math.clamp(color.G * brightness, 0, 1)
	local b = math.clamp(color.B * brightness, 0, 1)
	return Color3.new(r, g, b)
end

-- Emit one quad (two triangles) into a material bucket.
-- Corners are given in winding order such that the front face matches `normal`.
local function _emitFace(
	bucket: MaterialBucket,
	c1: Vector3,
	c2: Vector3,
	c3: Vector3,
	c4: Vector3,
	normal: Vector3,
	color: Color3
)
	local positions = bucket.positions
	local normals = bucket.normals
	local colors = bucket.colors
	local uvs = bucket.uvs
	local triangles = bucket.triangles

	local base = #positions

	positions[base + 1] = c1
	positions[base + 2] = c2
	positions[base + 3] = c3
	positions[base + 4] = c4

	normals[base + 1] = normal
	normals[base + 2] = normal
	normals[base + 3] = normal
	normals[base + 4] = normal

	colors[base + 1] = color
	colors[base + 2] = color
	colors[base + 3] = color
	colors[base + 4] = color

	uvs[base + 1] = UV_00
	uvs[base + 2] = UV_10
	uvs[base + 3] = UV_11
	uvs[base + 4] = UV_01

	-- Two triangles forming the quad (c1,c2,c3) and (c1,c3,c4), 1-based indices.
	local triBase = #triangles
	triangles[triBase + 1] = base + 1
	triangles[triBase + 2] = base + 2
	triangles[triBase + 3] = base + 3
	triangles[triBase + 4] = base + 1
	triangles[triBase + 5] = base + 3
	triangles[triBase + 6] = base + 4
end

-- Emit all 6 cube faces for a single block at world-position (wx, wy, wz) with
-- half-extent h, but only those whose neighbor is air. `color` and `material`
-- are pre-resolved.
--
-- Winding convention: CCW when viewed from the direction the normal points.
-- Roblox is right-handed (+X right, +Y up, +Z toward viewer); MeshParts cull
-- back-faces by default, so getting this wrong makes the face invisible.
-- TODO(verify-in-studio): if faces render inside-out, reverse quad winding.
local function _emitBlockFaces(
	blocks: buffer,
	lx: number,
	ly: number,
	lz: number,
	wx: number,
	wy: number,
	wz: number,
	color: Color3,
	bucket: MaterialBucket,
	h: number
)
	-- Cube corners: (-h,-h,-h) through (+h,+h,+h) around (wx,wy,wz).
	local x0, x1 = wx - h, wx + h
	local y0, y1 = wy - h, wy + h
	local z0, z1 = wz - h, wz + h

	-- +X face
	if _isNeighborAir(blocks, lx + 1, ly, lz) then
		_emitFace(
			bucket,
			Vector3.new(x1, y0, z0),
			Vector3.new(x1, y0, z1),
			Vector3.new(x1, y1, z1),
			Vector3.new(x1, y1, z0),
			NORMAL_PX,
			color
		)
	end

	-- -X face
	if _isNeighborAir(blocks, lx - 1, ly, lz) then
		_emitFace(
			bucket,
			Vector3.new(x0, y0, z1),
			Vector3.new(x0, y0, z0),
			Vector3.new(x0, y1, z0),
			Vector3.new(x0, y1, z1),
			NORMAL_NX,
			color
		)
	end

	-- +Y face (top)
	if _isNeighborAir(blocks, lx, ly + 1, lz) then
		_emitFace(
			bucket,
			Vector3.new(x0, y1, z0),
			Vector3.new(x1, y1, z0),
			Vector3.new(x1, y1, z1),
			Vector3.new(x0, y1, z1),
			NORMAL_PY,
			color
		)
	end

	-- -Y face (bottom)
	if _isNeighborAir(blocks, lx, ly - 1, lz) then
		_emitFace(
			bucket,
			Vector3.new(x0, y0, z1),
			Vector3.new(x1, y0, z1),
			Vector3.new(x1, y0, z0),
			Vector3.new(x0, y0, z0),
			NORMAL_NY,
			color
		)
	end

	-- +Z face
	if _isNeighborAir(blocks, lx, ly, lz + 1) then
		_emitFace(
			bucket,
			Vector3.new(x0, y0, z1),
			Vector3.new(x1, y0, z1),
			Vector3.new(x1, y1, z1),
			Vector3.new(x0, y1, z1),
			NORMAL_PZ,
			color
		)
	end

	-- -Z face
	if _isNeighborAir(blocks, lx, ly, lz - 1) then
		_emitFace(
			bucket,
			Vector3.new(x1, y0, z0),
			Vector3.new(x0, y0, z0),
			Vector3.new(x0, y1, z0),
			Vector3.new(x1, y1, z0),
			NORMAL_NZ,
			color
		)
	end
end

-- Get-or-create a material bucket.
local function _getBucket(buckets: { [Enum.Material]: MaterialBucket }, material: Enum.Material): MaterialBucket
	local b = buckets[material]
	if b then
		return b
	end
	local newBucket: MaterialBucket = {
		material = material,
		positions = {},
		normals = {},
		colors = {},
		uvs = {},
		triangles = {},
	}
	buckets[material] = newBucket
	return newBucket
end

--[=[
	Build a chunk mesh.
	`blocks`  — chunk buffer (4096 u8)
	`cx/cy/cz` — chunk coordinates
	`lod`     — 0 for near (with per-block offset/tint), 1 for far (flat cubes)

	Returns ChunkMeshData with per-material buckets.
]=]
function MeshBuilder.buildChunkMesh(blocks: buffer, cx: number, cy: number, cz: number, lod: number): ChunkMeshData
	local buckets: { [Enum.Material]: MaterialBucket } = {}
	local halfBlock = BLOCK_SIZE / 2
	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local exposedFaceCount = 0

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)
				if blockTypeId == BlockType.Air then
					continue
				end

				-- Check if any face is exposed (cheap early-out)
				local anyExposed = false
				for f = 1, 6 do
					if _isNeighborAir(blocks, lx + NEIGHBOR_DX[f], ly + NEIGHBOR_DY[f], lz + NEIGHBOR_DZ[f]) then
						anyExposed = true
						break
					end
				end
				if not anyExposed then
					continue
				end

				local baseColor = BlockRegistry.getColor(blockTypeId)
				local material = BlockRegistry.getMaterial(blockTypeId)

				local wx = baseX + lx * BLOCK_SIZE + halfBlock
				local wy = baseY + ly * BLOCK_SIZE + halfBlock
				local wz = baseZ + lz * BLOCK_SIZE + halfBlock

				local color = baseColor
				if lod == 0 then
					-- Per-block tint and position jitter for organic look
					local seed = lx * 7919 + ly * 6271 + lz * 4153 + cx * 31 + cy * 13 + cz * 17
					local tint = 1.0 + (_hash(seed, 5, 0, 0) - 0.5) * 2 * LOD0_TINT_RANGE
					color = _tintColor(baseColor, tint)
					local ox = (_hash(seed, 1, 0, 0) - 0.5) * 2 * LOD0_MAX_OFFSET
					local oz = (_hash(seed, 2, 0, 0) - 0.5) * 2 * LOD0_MAX_OFFSET
					wx += ox
					wz += oz
				end

				local bucket = _getBucket(buckets, material)
				local faceCountBefore = #bucket.triangles
				_emitBlockFaces(blocks, lx, ly, lz, wx, wy, wz, color, bucket, halfBlock)
				local faceCountAfter = #bucket.triangles
				-- 6 indices per face (2 triangles × 3 verts)
				exposedFaceCount += (faceCountAfter - faceCountBefore) // 6
			end
		end
	end

	-- Aggregate counts across buckets
	local vertexCount = 0
	local triangleCount = 0
	for _, bucket in buckets do
		vertexCount += #bucket.positions
		-- 3 indices per triangle
		triangleCount += #bucket.triangles // 3
	end

	return {
		buckets = buckets,
		vertexCount = vertexCount,
		triangleCount = triangleCount,
		exposedFaceCount = exposedFaceCount,
	}
end

-- Utility: fingerprint list of bouncy block locations found in the chunk, so
-- the caller can attach .Touched collision parts to them. Returns world-space
-- positions aligned to block centers.
export type BouncyBlock = {
	position: Vector3,
	blockTypeId: number,
	flatIndex: number,
}

function MeshBuilder.findBouncyBlocks(
	blocks: buffer,
	cx: number,
	cy: number,
	cz: number,
	bouncySet: { [number]: boolean }
): { BouncyBlock }
	local result: { BouncyBlock } = {}
	local halfBlock = BLOCK_SIZE / 2
	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)
				if bouncySet[blockTypeId] then
					table.insert(result, {
						position = Vector3.new(
							baseX + lx * BLOCK_SIZE + halfBlock,
							baseY + ly * BLOCK_SIZE + halfBlock,
							baseZ + lz * BLOCK_SIZE + halfBlock
						),
						blockTypeId = blockTypeId,
						flatIndex = idx,
					})
				end
			end
		end
	end

	return result
end

return MeshBuilder
