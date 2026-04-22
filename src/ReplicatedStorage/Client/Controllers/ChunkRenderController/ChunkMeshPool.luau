--!strict
--[=[
	@class ChunkMeshPool
	Creates and manages one or more `MeshPart`s per chunk, backed by
	`EditableMesh` geometry from `MeshBuilder`. One MeshPart is created per
	(chunkKey, material) bucket. All MeshParts live in `workspace.ChunkRender`
	so the existing mining raycast keeps working unchanged.
]=]

local AssetService = game:GetService("AssetService")

local MeshBuilder = require(script.Parent.MeshBuilder)

type MaterialBucket = MeshBuilder.MaterialBucket
type ChunkMeshData = MeshBuilder.ChunkMeshData

export type ChunkMeshEntry = {
	meshParts: { MeshPart },
	bouncyParts: { BasePart },
}

local ChunkMeshPool = {}

-- Mapping of chunkKey → entry.
local entries: { [number]: ChunkMeshEntry } = {}

-- Parent folder for all chunk mesh parts; MiningController raycasts against this.
local container: Folder? = nil

function ChunkMeshPool.setContainer(folder: Folder)
	container = folder
end

-- Convert our flat SoA bucket into EditableMesh geometry. The current (2025+)
-- EditableMesh API stores normals/colors/UVs in separate attribute pools and
-- binds them to faces (per-face-vertex), NOT to vertices directly. The old
-- SetVertexNormal / SetVertexColor / SetVertexUV methods were removed.
--
-- Flow:
--   1. AddVertex / AddNormal / AddColor / AddUV → one ID each, keyed by our
--      1-based bucket index.
--   2. AddTriangle → face ID, then SetFaceNormals/Colors/UVs with the three
--      per-corner attribute IDs.
local function _uploadBucketToEditableMesh(bucket: MaterialBucket, em: EditableMesh): ()
	local positions = bucket.positions
	local colors = bucket.colors
	local normals = bucket.normals
	local uvs = bucket.uvs
	local triangles = bucket.triangles

	local vertexCount = #positions

	local vertexIds: { number } = table.create(vertexCount)
	local normalIds: { number } = table.create(vertexCount)
	local colorIds: { number } = table.create(vertexCount)
	local uvIds: { number } = table.create(vertexCount)

	for i = 1, vertexCount do
		vertexIds[i] = em:AddVertex(positions[i])
		normalIds[i] = em:AddNormal(normals[i])
		colorIds[i] = em:AddColor(colors[i], 1)
		uvIds[i] = em:AddUV(uvs[i])
	end

	local triCount = #triangles
	local t = 1
	-- Reused tuples so we don't allocate a fresh array per triangle. Roblox
	-- copies the value immediately on Set*, so reusing is safe.
	local nTriple = table.create(3)
	local cTriple = table.create(3)
	local uTriple = table.create(3)
	while t <= triCount do
		local i1 = triangles[t]
		local i2 = triangles[t + 1]
		local i3 = triangles[t + 2]
		local faceId = em:AddTriangle(vertexIds[i1], vertexIds[i2], vertexIds[i3])
		nTriple[1] = normalIds[i1]
		nTriple[2] = normalIds[i2]
		nTriple[3] = normalIds[i3]
		em:SetFaceNormals(faceId, nTriple)
		cTriple[1] = colorIds[i1]
		cTriple[2] = colorIds[i2]
		cTriple[3] = colorIds[i3]
		em:SetFaceColors(faceId, cTriple)
		uTriple[1] = uvIds[i1]
		uTriple[2] = uvIds[i2]
		uTriple[3] = uvIds[i3]
		em:SetFaceUVs(faceId, uTriple)
		t += 3
	end
end

-- Build a single MeshPart from a material bucket. Returns nil if the bucket is
-- empty (no vertices). This yields because CreateMeshPartAsync is async.
--
-- Memory note: EditableMesh instances share a per-experience memory budget
-- (~100MB client-side). Each CreateEditableMesh allocates against that budget.
-- We MUST call :Destroy() on the source EditableMesh once the MeshPart is
-- created — otherwise budget exhausts within seconds of chunk streaming and
-- every subsequent CreateEditableMesh returns nil ("attempt to index nil with
-- 'AddVertex'" on the next line).
local function _buildMeshPartForBucket(bucket: MaterialBucket, chunkKey: number): MeshPart?
	if #bucket.positions == 0 then
		return nil
	end

	-- Compute the authored bounding-box center. CreateMeshPartAsync normalizes
	-- the mesh so its center sits at the MeshPart's CFrame origin, so we need
	-- this center in world space to position the MeshPart correctly.
	local positions = bucket.positions
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for i = 1, #positions do
		local p = positions[i]
		local px, py, pz = p.X, p.Y, p.Z
		if px < minX then
			minX = px
		end
		if py < minY then
			minY = py
		end
		if pz < minZ then
			minZ = pz
		end
		if px > maxX then
			maxX = px
		end
		if py > maxY then
			maxY = py
		end
		if pz > maxZ then
			maxZ = pz
		end
	end
	local centerX = (minX + maxX) * 0.5
	local centerY = (minY + maxY) * 0.5
	local centerZ = (minZ + maxZ) * 0.5

	local em = AssetService:CreateEditableMesh()
	if not em then
		warn(
			string.format(
				"[ChunkRenderer] CreateEditableMesh returned nil for chunk %d (%s) — likely EditableMesh memory budget exhausted",
				chunkKey,
				tostring(bucket.material)
			)
		)
		return nil
	end

	local uploadOk, uploadErr = pcall(_uploadBucketToEditableMesh, bucket, em)
	if not uploadOk then
		em:Destroy()
		warn(
			string.format(
				"[ChunkRenderer] mesh upload failed for chunk %d (%s): %s",
				chunkKey,
				tostring(bucket.material),
				tostring(uploadErr)
			)
		)
		return nil
	end

	-- Wrap the editable mesh in content-addressable form and create a MeshPart.
	-- CollisionFidelity = PreciseConvexDecomposition gives accurate voxel
	-- raycast hits; Default can merge cube faces into hulls that lose per-block
	-- fidelity. TODO(verify-in-studio): may need to fall back to Default if the
	-- async build time for precise fidelity is too slow.
	local content = Content.fromObject(em)
	local ok, meshPart = pcall(function()
		return AssetService:CreateMeshPartAsync(content, {
			CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
		})
	end)

	-- Free the EditableMesh's slot in the memory budget. The MeshPart has its
	-- own internal copy of the geometry by this point, so this is safe.
	em:Destroy()

	if not ok or not meshPart then
		warn(
			string.format(
				"[ChunkRenderer] CreateMeshPartAsync failed for chunk %d (%s)",
				chunkKey,
				tostring(bucket.material)
			)
		)
		return nil
	end

	meshPart.Anchored = true
	meshPart.CanCollide = true
	meshPart.CanQuery = true
	meshPart.CanTouch = false
	meshPart.CastShadow = false
	meshPart.Material = bucket.material
	meshPart.Name = string.format("Chunk_%d_%s", chunkKey, tostring(bucket.material.Name))
	-- CreateMeshPartAsync stores the mesh so its bounding-box center sits at
	-- local (0,0,0). Position the MeshPart at that center (computed above in
	-- world space) so the mesh renders back at its authored world location.
	meshPart.CFrame = CFrame.new(centerX, centerY, centerZ)
	if container then
		meshPart.Parent = container
	end

	return meshPart
end

-- Destroy an existing chunk's mesh parts + bouncy parts.
function ChunkMeshPool.unrender(chunkKey: number): ()
	local entry = entries[chunkKey]
	if not entry then
		return
	end
	for _, mp in entry.meshParts do
		mp:Destroy()
	end
	for _, bp in entry.bouncyParts do
		bp:Destroy()
	end
	entries[chunkKey] = nil
end

-- Render (or re-render) a chunk from the given mesh data + bouncy block list.
-- The caller is responsible for providing `bouncyFactory(blockTypeId, position)`
-- which creates the Part and returns it (touch-handler setup is the caller's job).
function ChunkMeshPool.render(
	chunkKey: number,
	meshData: ChunkMeshData,
	bouncyBlocks: { MeshBuilder.BouncyBlock },
	bouncyFactory: (blockTypeId: number, position: Vector3) -> BasePart
): ChunkMeshEntry
	-- Destroy the old entry first.
	ChunkMeshPool.unrender(chunkKey)

	local meshParts: { MeshPart } = {}
	for _, bucket in meshData.buckets do
		local mp = _buildMeshPartForBucket(bucket, chunkKey)
		if mp then
			table.insert(meshParts, mp)
		end
	end

	local bouncyParts: { BasePart } = {}
	for _, bouncy in bouncyBlocks do
		local part = bouncyFactory(bouncy.blockTypeId, bouncy.position)
		table.insert(bouncyParts, part)
	end

	local entry: ChunkMeshEntry = {
		meshParts = meshParts,
		bouncyParts = bouncyParts,
	}
	entries[chunkKey] = entry
	return entry
end

-- Retrieve the active entry for a chunk (or nil if not rendered).
function ChunkMeshPool.getEntry(chunkKey: number): ChunkMeshEntry?
	return entries[chunkKey]
end

-- Total count of active MeshParts + bouncy parts across all chunks.
function ChunkMeshPool.getActiveDrawUnitCount(): number
	local n = 0
	for _, entry in entries do
		n += #entry.meshParts + #entry.bouncyParts
	end
	return n
end

-- Count of chunks currently rendered.
function ChunkMeshPool.getRenderedChunkCount(): number
	local n = 0
	for _ in entries do
		n += 1
	end
	return n
end

return ChunkMeshPool
