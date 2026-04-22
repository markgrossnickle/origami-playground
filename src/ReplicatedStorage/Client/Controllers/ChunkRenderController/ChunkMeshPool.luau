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

-- Convert our flat triangle index list (1-based into positions[]) into the
-- EditableMesh vertex IDs (which are assigned when AddVertex is called).
local function _uploadBucketToEditableMesh(bucket: MaterialBucket, em: EditableMesh): ()
	local positions = bucket.positions
	local colors = bucket.colors
	local normals = bucket.normals
	local uvs = bucket.uvs
	local triangles = bucket.triangles

	local vertexCount = #positions

	-- Map our 1-based array index → EditableMesh vertex ID.
	local vertexIds: { number } = table.create(vertexCount)

	for i = 1, vertexCount do
		local vid = em:AddVertex(positions[i])
		vertexIds[i] = vid
		em:SetVertexNormal(vid, normals[i])
		em:SetVertexColor(vid, colors[i])
		em:SetVertexUV(vid, uvs[i])
	end

	local triCount = #triangles
	local t = 1
	while t <= triCount do
		local a = vertexIds[triangles[t]]
		local b = vertexIds[triangles[t + 1]]
		local c = vertexIds[triangles[t + 2]]
		em:AddTriangle(a, b, c)
		t += 3
	end
end

-- Build a single MeshPart from a material bucket. Returns nil if the bucket is
-- empty (no vertices). This yields because CreateMeshPartAsync is async.
local function _buildMeshPartForBucket(bucket: MaterialBucket, chunkKey: number): MeshPart?
	if #bucket.positions == 0 then
		return nil
	end

	local em = AssetService:CreateEditableMesh()
	_uploadBucketToEditableMesh(bucket, em)

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
	-- Mesh vertices already live in world space, so the MeshPart sits at origin.
	meshPart.CFrame = CFrame.new(0, 0, 0)
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
