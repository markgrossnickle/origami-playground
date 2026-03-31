--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local CHUNK_STUDS = ChunkUtil.CHUNK_STUDS
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK

local POOL_INITIAL = 3000
local POOL_MAX = 15000

-- XZ scale per depth (how many solid blocks are below)
local TERRACE_SCALES = { 1.0, 0.92, 0.84, 0.76 }
local MAX_DEPTH_CHECK = #TERRACE_SCALES - 1

local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

--[=[
	@class ChunkRenderController
	Terraced renderer: each exposed block's XZ size depends on how many
	solid blocks are below it, creating natural stepped/terraced formations
	like a paper-cut diorama. Invisible full-size collision parts handle
	raycasting and walking.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: BasePart } } = {}
local terraceParts: { [string]: { [number]: BasePart } } = {}
local collisionParts: { [string]: { [number]: BasePart } } = {}
local chunkBlocks: { [string]: buffer } = {}

local chunkContainer: Folder

-------------------------------------------------
-- Part pool
-------------------------------------------------

local function _createPart(): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	return part
end

local function _initPool()
	for _ = 1, POOL_INITIAL do
		table.insert(partPool, _createPart())
	end
end

local function _getPart(): BasePart
	local part: BasePart
	if #partPool > 0 then
		part = table.remove(partPool, #partPool) :: BasePart
	else
		part = _createPart()
	end
	activePartsCount += 1
	return part
end

local function _returnPart(part: BasePart)
	part.Parent = nil
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CanCollide = true
	part.Transparency = 0
	for _, child in part:GetChildren() do
		child:Destroy()
	end
	activePartsCount -= 1
	if #partPool < POOL_MAX then
		table.insert(partPool, part)
	else
		part:Destroy()
	end
end

-------------------------------------------------
-- Depth calculation for terrace sizing
-------------------------------------------------

local function _isTransparent(blockId: number): boolean
	return blockId == BlockType.Air
end

local function _getDepthBelow(blocks: buffer, lx: number, ly: number, lz: number): number
	local depth = 0
	for dy = 1, MAX_DEPTH_CHECK do
		local checkY = ly - dy
		if checkY < 0 then
			-- Treat below-chunk as solid (ground continues)
			depth += 1
		else
			local belowId = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, checkY, lz))
			if belowId == BlockType.Air then
				break
			end
			depth += 1
		end
	end
	return math.min(depth, MAX_DEPTH_CHECK)
end

-------------------------------------------------
-- Terraced block creation
-------------------------------------------------

local function _makeTerracePart(
	blockTypeId: number,
	blocks: buffer,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number
): BasePart
	local halfBlock = BLOCK_SIZE / 2
	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local px = baseX + lx * BLOCK_SIZE + halfBlock
	local py = baseY + ly * BLOCK_SIZE + halfBlock
	local pz = baseZ + lz * BLOCK_SIZE + halfBlock

	local depth = _getDepthBelow(blocks, lx, ly, lz)
	local scale = TERRACE_SCALES[depth + 1]
	local xzSize = BLOCK_SIZE * scale

	local part = _getPart()
	part.Color = BlockRegistry.getColor(blockTypeId)
	part.Material = BlockRegistry.getMaterial(blockTypeId)
	part.Size = Vector3.new(xzSize, BLOCK_SIZE, xzSize)
	part.CanCollide = false
	part.Transparency = 0
	part.Position = Vector3.new(px, py, pz)

	if blockTypeId == BlockType.EggNode then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 180)
		light.Brightness = 1
		light.Range = 15
		light.Parent = part
	end

	part.Parent = chunkContainer
	return part
end

-------------------------------------------------
-- Visibility checks
-------------------------------------------------

local function _isExposed(blocks: buffer, lx: number, ly: number, lz: number): boolean
	local blockId = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly, lz))
	if blockId == BlockType.Air then
		return false
	end
	if lx <= 0 or _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(lx - 1, ly, lz))) then
		return true
	end
	if lx >= CHUNK_SIZE - 1 or _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(lx + 1, ly, lz))) then
		return true
	end
	if ly <= 0 or _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly - 1, lz))) then
		return true
	end
	if ly >= CHUNK_SIZE - 1 or _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly + 1, lz))) then
		return true
	end
	if lz <= 0 or _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly, lz - 1))) then
		return true
	end
	if lz >= CHUNK_SIZE - 1 or _isTransparent(buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly, lz + 1))) then
		return true
	end
	return false
end

-------------------------------------------------
-- Chunk rendering
-------------------------------------------------

local function _renderChunk(chunkKey: string, blocks: buffer)
	local existingTerrace = terraceParts[chunkKey]
	if existingTerrace then
		for _, part in existingTerrace do
			_returnPart(part)
		end
	end

	local existingSpecial = renderedSpecialParts[chunkKey]
	if existingSpecial then
		for _, part in existingSpecial do
			_returnPart(part)
		end
	end

	local existingCollision = collisionParts[chunkKey]
	if existingCollision then
		for _, part in existingCollision do
			_returnPart(part)
		end
		collisionParts[chunkKey] = nil
	end

	chunkBlocks[chunkKey] = blocks
	renderedChunks[chunkKey] = true

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local specialParts: { [number]: BasePart } = {}
	renderedSpecialParts[chunkKey] = specialParts

	local tParts: { [number]: BasePart } = {}
	terraceParts[chunkKey] = tParts

	local cParts: { [number]: BasePart } = {}
	collisionParts[chunkKey] = cParts

	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)

				if blockTypeId == BlockType.Air then
					continue
				end

				if not _isExposed(blocks, lx, ly, lz) then
					continue
				end

				if _isSpecialBlock(blockTypeId) then
					specialParts[idx] = _makeTerracePart(blockTypeId, blocks, cx, cy, cz, lx, ly, lz)
				else
					tParts[idx] = _makeTerracePart(blockTypeId, blocks, cx, cy, cz, lx, ly, lz)
				end

				-- Invisible collision Part
				local collisionPart = _getPart()
				collisionPart.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
				collisionPart.Transparency = 1
				collisionPart.CanCollide = true
				collisionPart.CastShadow = false

				local halfBlock = BLOCK_SIZE / 2
				collisionPart.Position = Vector3.new(
					baseX + lx * BLOCK_SIZE + halfBlock,
					baseY + ly * BLOCK_SIZE + halfBlock,
					baseZ + lz * BLOCK_SIZE + halfBlock
				)
				collisionPart.Parent = chunkContainer
				cParts[idx] = collisionPart
			end
		end
		if ly % 4 == 3 then
			task.wait()
		end
	end
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil

	local tParts = terraceParts[chunkKey]
	if tParts then
		for _, part in tParts do
			_returnPart(part)
		end
		terraceParts[chunkKey] = nil
	end

	local cParts = collisionParts[chunkKey]
	if cParts then
		for _, part in cParts do
			_returnPart(part)
		end
		collisionParts[chunkKey] = nil
	end

	local specialParts = renderedSpecialParts[chunkKey]
	if specialParts then
		for _, part in specialParts do
			_returnPart(part)
		end
		renderedSpecialParts[chunkKey] = nil
	end

	chunkBlocks[chunkKey] = nil
end

-------------------------------------------------
-- Block update handling (surgical per-block)
-- Also re-checks up to 4 blocks above (their depth changed)
-------------------------------------------------

local function _refreshBlock(
	blocks: buffer,
	cx: number,
	cy: number,
	cz: number,
	nx: number,
	ny: number,
	nz: number,
	tParts: { [number]: BasePart },
	sParts: { [number]: BasePart },
	cParts: { [number]: BasePart }
)
	local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
	local nBlockType = buffer.readu8(blocks, nIdx)

	-- Remove existing visual + collision
	if tParts[nIdx] then
		_returnPart(tParts[nIdx])
		tParts[nIdx] = nil
	end
	if sParts[nIdx] then
		_returnPart(sParts[nIdx])
		sParts[nIdx] = nil
	end
	if cParts[nIdx] then
		_returnPart(cParts[nIdx])
		cParts[nIdx] = nil
	end

	if nBlockType ~= BlockType.Air and _isExposed(blocks, nx, ny, nz) then
		if _isSpecialBlock(nBlockType) then
			sParts[nIdx] = _makeTerracePart(nBlockType, blocks, cx, cy, cz, nx, ny, nz)
		else
			tParts[nIdx] = _makeTerracePart(nBlockType, blocks, cx, cy, cz, nx, ny, nz)
		end

		local halfBlock = BLOCK_SIZE / 2
		local cp = _getPart()
		cp.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		cp.Transparency = 1
		cp.CanCollide = true
		cp.CastShadow = false
		cp.Position = Vector3.new(
			cx * CHUNK_STUDS + nx * BLOCK_SIZE + halfBlock,
			cy * CHUNK_STUDS + ny * BLOCK_SIZE + halfBlock,
			cz * CHUNK_STUDS + nz * BLOCK_SIZE + halfBlock
		)
		cp.Parent = chunkContainer
		cParts[nIdx] = cp
	end
end

local function _handleBlockUpdate(chunkKey: string, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)

	local tParts = terraceParts[chunkKey]
	if not tParts then
		tParts = {}
		terraceParts[chunkKey] = tParts
	end

	local sParts = renderedSpecialParts[chunkKey]
	if not sParts then
		sParts = {}
		renderedSpecialParts[chunkKey] = sParts
	end

	local cParts = collisionParts[chunkKey]
	if not cParts then
		cParts = {}
		collisionParts[chunkKey] = cParts
	end

	-- Refresh the changed block itself
	_refreshBlock(blocks, cx, cy, cz, lx, ly, lz, tParts, sParts, cParts)

	-- Update 6 direct neighbors
	local dirs = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
	for _, dir in dirs do
		local nx, ny, nz = lx + dir[1], ly + dir[2], lz + dir[3]
		if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
			continue
		end
		_refreshBlock(blocks, cx, cy, cz, nx, ny, nz, tParts, sParts, cParts)
	end

	-- Also refresh up to 4 blocks above (their terrace depth changed)
	for dy = 1, MAX_DEPTH_CHECK do
		local aboveY = ly + dy
		if aboveY >= CHUNK_SIZE then
			break
		end
		local aboveId = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, aboveY, lz))
		if aboveId == BlockType.Air then
			break
		end
		_refreshBlock(blocks, cx, cy, cz, lx, aboveY, lz, tParts, sParts, cParts)
	end
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function ChunkRenderController:GetBlockAt(chunkKey: string, flatIndex: number): number
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return BlockType.Air
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end
	return buffer.readu8(blocks, flatIndex)
end

function ChunkRenderController:GetChunkBlocks(chunkKey: string): buffer?
	return chunkBlocks[chunkKey]
end

function ChunkRenderController:GetActivePartCount(): number
	return activePartsCount
end

function ChunkRenderController:GetPoolSize(): number
	return #partPool
end

-------------------------------------------------
-- Knit lifecycle
-------------------------------------------------

function ChunkRenderController:KnitInit()
	chunkContainer = Instance.new("Folder")
	chunkContainer.Name = "ChunkRender"
	chunkContainer.Parent = workspace

	_initPool()
end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	WorldService.ChunkData:Connect(function(chunkKey: string, compressedBuffer: buffer)
		local blocks = ChunkSerializer.decompress(compressedBuffer)
		_renderChunk(chunkKey, blocks)
	end)

	WorldService.ChunkUnload:Connect(function(chunkKey: string)
		_unrenderChunk(chunkKey)
	end)

	WorldService.BlockUpdate:Connect(function(chunkKey: string, flatIndex: number, blockTypeId: number)
		_handleBlockUpdate(chunkKey, flatIndex, blockTypeId)
	end)
end

return ChunkRenderController
