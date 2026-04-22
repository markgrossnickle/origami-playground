--!strict
--[=[
	@class ChunkRenderController

	EditableMesh-based chunk renderer. One MeshPart per (chunk, material)
	bucket replaces the old 1–3 Parts/block approach.

	See `docs/EDITABLE_MESH_DESIGN.md` for the design rationale and
	`MeshBuilder` / `ChunkMeshPool` submodules for the implementation.

	Public API (preserved from the previous renderer):
	  GetBlockAt(chunkKey, flatIndex) → blockTypeId
	  GetChunkBlocks(chunkKey) → buffer?
	  GetActivePartCount() → number (now: active draw units = MeshParts + bouncy parts)
	  GetPoolSize() → number (kept for compatibility — reports 0; no pool in the mesh renderer)
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local MeshBuilder = require(script.MeshBuilder)
local ChunkMeshPool = require(script.ChunkMeshPool)

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK

-- LOD thresholds (chunk-space squared distance)
local LOD_NEAR_DIST2 = 2
local RENDER_MAX_DIST2 = 18

-- Render frame budget: don't spend more than this per heartbeat building chunks.
local BUILD_FRAME_BUDGET = 0.006

-- LOD re-evaluation interval (seconds)
local LOD_CHECK_INTERVAL = 2.0

-- Bouncy block configuration (preserved from the old renderer)
local BOUNCY_BLOCKS: { [number]: boolean } = {
	[BlockType.MushroomCap] = true,
	[BlockType.ShelfBracket] = true,
}
local BOUNCE_VEL_MIN = 60
local BOUNCE_VEL_MAX = 80
local BOUNCE_MULTIPLIER = 1.2
local BOUNCE_DEBOUNCE = 0.2
local FLASH_DURATION = 0.3
local MUSHROOM_FLASH_COLORS = {
	Color3.fromRGB(255, 0, 200),
	Color3.fromRGB(0, 220, 255),
	Color3.fromRGB(255, 230, 0),
	Color3.fromRGB(0, 255, 100),
	Color3.fromRGB(255, 140, 0),
}

-- Tiny thin collision part size for bouncy blocks. They sit at the block
-- center and pick up .Touched for the bounce physics — the main chunk mesh
-- renders their visual.
local BOUNCY_PART_SIZE = Vector3.new(BLOCK_SIZE * 0.9, BLOCK_SIZE * 0.35, BLOCK_SIZE * 0.9)

local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

-- State ----------------------------------------------------------------------

-- chunkKey → decompressed block buffer (kept for mining/block-update even when
-- the chunk is too far to render)
local chunkBlocks: { [number]: buffer } = {}

-- chunkKey → current LOD (0 or 1). Missing entry means unrendered.
local chunkLOD: { [number]: number } = {}

-- Dirty set — chunk keys awaiting (re)build. Heartbeat processes these within
-- the frame budget.
local dirtyChunks: { [number]: boolean } = {}

-- Folder parent for all chunk mesh parts and bouncy parts.
local chunkContainer: Folder

-- Bouncy block bookkeeping (per-player debounce)
local lastBounceTime: { [Player]: number } = {}

-- LOD re-evaluation throttling
local lastLODCheck = 0
local _lastLODPlayerCx: number? = nil
local _lastLODPlayerCy: number? = nil
local _lastLODPlayerCz: number? = nil

-- Character-ready gate
local characterReady = false
local pendingChunkData: { { key: number, blocks: buffer } } = {}

-- Player position helpers ----------------------------------------------------

local function _getPlayerChunkPos(): (number?, number?, number?)
	local player = Players.LocalPlayer
	if not player or not player.Character then
		return nil, nil, nil
	end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil, nil, nil
	end
	local pos = hrp.Position
	return ChunkUtil.worldToChunk(pos.X, pos.Y, pos.Z)
end

local function _getChunkLOD(cx: number, cy: number, cz: number): number
	local pcx, pcy, pcz = _getPlayerChunkPos()
	if not pcx or not pcy or not pcz then
		return -1
	end
	local dx = cx - pcx
	local dy = cy - pcy
	local dz = cz - pcz
	local dist2 = dx * dx + dy * dy + dz * dz
	if dist2 > RENDER_MAX_DIST2 then
		return -1
	end
	if dist2 <= LOD_NEAR_DIST2 then
		return 0
	end
	return 1
end

-- Bouncy block handling ------------------------------------------------------

local function _setupBouncyConnection(part: BasePart, blockTypeId: number)
	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local rootPart = humanoid.RootPart
		if not rootPart then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y > -5 then
			return
		end

		local now = os.clock()
		if lastBounceTime[player] and now - lastBounceTime[player] < BOUNCE_DEBOUNCE then
			return
		end
		lastBounceTime[player] = now

		local bounceY = math.min(BOUNCE_VEL_MAX, math.max(BOUNCE_VEL_MIN, -vel.Y * BOUNCE_MULTIPLIER))
		rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, bounceY, vel.Z)

		-- Flash the collision part (visual on the mesh is static — this at
		-- least signals hit to players looking at the bouncy block directly).
		local flashColor = MUSHROOM_FLASH_COLORS[math.random(1, #MUSHROOM_FLASH_COLORS)]
		local origColor = part.Color
		local origTransparency = part.Transparency
		part.Color = flashColor
		part.Transparency = 0.5
		task.delay(FLASH_DURATION, function()
			if part.Parent then
				part.Color = origColor
				part.Transparency = origTransparency
			end
		end)

		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
		sound.Volume = 0.5
		sound.Parent = part
		sound:Play()
		task.delay(1, function()
			sound:Destroy()
		end)
	end)
	-- Silence the unused-variable warning on blockTypeId; we ignore it but
	-- keep the signature so future per-type bounce tuning is easy.
	local _ = blockTypeId
end

local function _createBouncyPart(blockTypeId: number, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = string.format("Bouncy_%d", blockTypeId)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1 -- invisible; the chunk mesh renders the visual
	part.Size = BOUNCY_PART_SIZE
	part.Color = BlockRegistry.getColor(blockTypeId)
	part.Material = BlockRegistry.getMaterial(blockTypeId)
	part.Position = position
	if chunkContainer then
		part.Parent = chunkContainer
	end
	_setupBouncyConnection(part, blockTypeId)
	return part
end

-- Chunk rendering ------------------------------------------------------------

local function _buildChunkNow(chunkKey: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lod = _getChunkLOD(cx, cy, cz)
	chunkLOD[chunkKey] = lod

	if lod == -1 then
		-- Too far to render — just make sure any old mesh is gone.
		ChunkMeshPool.unrender(chunkKey)
		return
	end

	local meshData = MeshBuilder.buildChunkMesh(blocks, cx, cy, cz, lod)
	local bouncy = MeshBuilder.findBouncyBlocks(blocks, cx, cy, cz, BOUNCY_BLOCKS)

	ChunkMeshPool.render(chunkKey, meshData, bouncy, _createBouncyPart)

	local materialCount = 0
	for _ in meshData.buckets do
		materialCount += 1
	end

	print(
		string.format(
			"[ChunkRenderer] built chunk %d (LOD %d): %d vertices, %d triangles, %d exposed faces, %d materials, %d bouncy",
			chunkKey,
			lod,
			meshData.vertexCount,
			meshData.triangleCount,
			meshData.exposedFaceCount,
			materialCount,
			#bouncy
		)
	)
end

local function _markDirty(chunkKey: number)
	dirtyChunks[chunkKey] = true
end

local function _processDirtyChunks()
	if not next(dirtyChunks) then
		return
	end
	local start = os.clock()

	-- Sort dirty keys by distance to player (closest first) so the player sees
	-- updates to chunks nearest them within the frame budget.
	local pcx, pcy, pcz = _getPlayerChunkPos()

	local keys: { number } = {}
	for k in dirtyChunks do
		table.insert(keys, k)
	end
	if pcx and pcy and pcz then
		table.sort(keys, function(a, b)
			local acx, acy, acz = ChunkUtil.parseChunkKey(a)
			local bcx, bcy, bcz = ChunkUtil.parseChunkKey(b)
			local aDist = (acx - pcx) ^ 2 + (acy - pcy) ^ 2 + (acz - pcz) ^ 2
			local bDist = (bcx - pcx) ^ 2 + (bcy - pcy) ^ 2 + (bcz - pcz) ^ 2
			return aDist < bDist
		end)
	end

	for _, key in keys do
		dirtyChunks[key] = nil
		_buildChunkNow(key)
		if os.clock() - start > BUILD_FRAME_BUDGET then
			break
		end
	end
end

local function _unrenderChunk(chunkKey: number)
	ChunkMeshPool.unrender(chunkKey)
	chunkLOD[chunkKey] = nil
	chunkBlocks[chunkKey] = nil
	dirtyChunks[chunkKey] = nil
end

-- Block update handler -------------------------------------------------------
-- When a single block changes we rebuild the owning chunk. If the block is on
-- a chunk boundary, we also rebuild the adjacent chunk(s) because their face
-- exposure on that boundary depends on this chunk's data.
local BOUNDARY_DX = { 1, -1, 0, 0, 0, 0 }
local BOUNDARY_DY = { 0, 0, 1, -1, 0, 0 }
local BOUNDARY_DZ = { 0, 0, 0, 0, 1, -1 }

local function _markBoundaryNeighbors(chunkKey: number, lx: number, ly: number, lz: number)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	-- For each axis, if the block is on a boundary, the neighbor chunk in that
	-- direction might be affected.
	for f = 1, 6 do
		local dx, dy, dz = BOUNDARY_DX[f], BOUNDARY_DY[f], BOUNDARY_DZ[f]
		local nlx, nly, nlz = lx + dx, ly + dy, lz + dz
		if nlx < 0 or nlx >= CHUNK_SIZE or nly < 0 or nly >= CHUNK_SIZE or nlz < 0 or nlz >= CHUNK_SIZE then
			local neighborKey = ChunkUtil.chunkKey(cx + dx, cy + dy, cz + dz)
			if chunkBlocks[neighborKey] then
				_markDirty(neighborKey)
			end
		end
	end
end

local function _handleBlockUpdate(chunkKey: number, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	-- Mark this chunk dirty; Heartbeat will rebuild.
	_markDirty(chunkKey)

	-- Boundary neighbors too.
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	_markBoundaryNeighbors(chunkKey, lx, ly, lz)

	print(
		string.format(
			"[ChunkRenderer] block updated chunk=%d idx=%d type=%d -> scheduled rebuild",
			chunkKey,
			flatIndex,
			blockTypeId
		)
	)
end

-- LOD re-evaluation ----------------------------------------------------------

local function _reevaluateLODs()
	if not characterReady then
		return
	end
	local now = os.clock()
	if now - lastLODCheck < LOD_CHECK_INTERVAL then
		return
	end

	local pcx, pcy, pcz = _getPlayerChunkPos()
	if not pcx or not pcy or not pcz then
		return
	end
	if pcx == _lastLODPlayerCx and pcy == _lastLODPlayerCy and pcz == _lastLODPlayerCz then
		lastLODCheck = now
		return
	end
	_lastLODPlayerCx = pcx
	_lastLODPlayerCy = pcy
	_lastLODPlayerCz = pcz
	lastLODCheck = now

	for chunkKey, currentLod in chunkLOD do
		local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
		local newLod = _getChunkLOD(cx, cy, cz)
		if newLod ~= currentLod then
			_markDirty(chunkKey)
		end
	end
end

-- Public API -----------------------------------------------------------------

function ChunkRenderController:GetBlockAt(chunkKey: number, flatIndex: number): number
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return BlockType.Air
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end
	return buffer.readu8(blocks, flatIndex)
end

function ChunkRenderController:GetChunkBlocks(chunkKey: number): buffer?
	return chunkBlocks[chunkKey]
end

function ChunkRenderController:GetActivePartCount(): number
	return ChunkMeshPool.getActiveDrawUnitCount()
end

function ChunkRenderController:GetPoolSize(): number
	-- No Part pool exists in the mesh renderer. Kept for API compatibility.
	return 0
end

-- Knit lifecycle -------------------------------------------------------------

function ChunkRenderController:KnitInit()
	chunkContainer = Instance.new("Folder")
	chunkContainer.Name = "ChunkRender"
	chunkContainer.Parent = workspace

	ChunkMeshPool.setContainer(chunkContainer)

	print("[ChunkRenderer] initialized EditableMesh renderer")
end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")
	local player = Players.LocalPlayer

	local function _onCharacterReady()
		if characterReady then
			return
		end
		characterReady = true

		-- Flush pending chunks into the dirty set so Heartbeat builds them.
		for _, item in pendingChunkData do
			chunkBlocks[item.key] = item.blocks
			_markDirty(item.key)
		end
		table.clear(pendingChunkData)
	end

	if player then
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			_onCharacterReady()
		end
		if not characterReady then
			player.CharacterAdded:Connect(function(char: Model)
				local hrp = char:WaitForChild("HumanoidRootPart", 10)
				if hrp then
					_onCharacterReady()
				end
			end)
		end
	end

	WorldService.ChunkData:Connect(function(chunkKey: number, compressedBuffer: buffer)
		local blocks = ChunkSerializer.decompress(compressedBuffer)

		if not characterReady then
			table.insert(pendingChunkData, { key = chunkKey, blocks = blocks })
			return
		end

		chunkBlocks[chunkKey] = blocks
		_markDirty(chunkKey)
	end)

	WorldService.ChunkUnload:Connect(function(chunkKey: number)
		_unrenderChunk(chunkKey)
	end)

	WorldService.BlockUpdate:Connect(function(chunkKey: number, flatIndex: number, blockTypeId: number)
		_handleBlockUpdate(chunkKey, flatIndex, blockTypeId)
	end)

	-- Heartbeat: drain dirty chunks within the frame budget, then re-eval LOD.
	RunService.Heartbeat:Connect(function(_dt: number)
		_processDirtyChunks()
		_reevaluateLODs()
	end)
end

return ChunkRenderController
