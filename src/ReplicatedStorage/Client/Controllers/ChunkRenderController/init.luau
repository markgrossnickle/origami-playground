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

local WEDGE_POOL_INITIAL = 12000
local WEDGE_POOL_MAX = 30000
local PART_POOL_INITIAL = 4000
local PART_POOL_MAX = 15000

local HALF = BLOCK_SIZE / 2
local QUARTER = BLOCK_SIZE / 4
local WEDGE_SIZE = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, HALF)

-- Precompute CFrame offsets for pyramid wedge faces
local PI = math.pi

local UP_CFRAMES = {
	CFrame.new(0, 0, QUARTER), -- front
	CFrame.new(0, 0, -QUARTER) * CFrame.Angles(0, PI, 0), -- back
	CFrame.new(QUARTER, 0, 0) * CFrame.Angles(0, -PI / 2, 0), -- right
	CFrame.new(-QUARTER, 0, 0) * CFrame.Angles(0, PI / 2, 0), -- left
}

local FLIP_Z = CFrame.Angles(0, 0, PI)
local DOWN_CFRAMES = {
	CFrame.new(0, 0, QUARTER) * FLIP_Z,
	CFrame.new(0, 0, -QUARTER) * CFrame.Angles(0, PI, 0) * FLIP_Z,
	CFrame.new(QUARTER, 0, 0) * CFrame.Angles(0, -PI / 2, 0) * FLIP_Z,
	CFrame.new(-QUARTER, 0, 0) * CFrame.Angles(0, PI / 2, 0) * FLIP_Z,
}

-- Override: PaperGrass renders as cream Paper visually
local GRASS_COLOR = Color3.fromRGB(245, 235, 220)
local GRASS_MATERIAL = Enum.Material.SmoothPlastic

local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

local function _getColor(blockTypeId: number): Color3
	if blockTypeId == BlockType.PaperGrass then
		return GRASS_COLOR
	end
	return BlockRegistry.getColor(blockTypeId)
end

local function _getMaterial(blockTypeId: number): Enum.Material
	if blockTypeId == BlockType.PaperGrass then
		return GRASS_MATERIAL
	end
	return BlockRegistry.getMaterial(blockTypeId)
end

--[=[
	@class ChunkRenderController
	Pyramid renderer: each exposed block is a 4-sided pyramid built from
	4 WedgeParts. Checkerboard pattern alternates up/down pyramids.
	No grass — surface starts cream/white.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local wedgePool: { WedgePart } = {}
local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: { WedgePart } } } = {}
local pyramidParts: { [string]: { [number]: { WedgePart } } } = {}
local collisionParts: { [string]: { [number]: BasePart } } = {}
local chunkBlocks: { [string]: buffer } = {}

local chunkContainer: Folder

-------------------------------------------------
-- Wedge pool (visual pyramid faces)
-------------------------------------------------

local function _createWedge(): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CastShadow = false
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Size = WEDGE_SIZE
	return wedge
end

local function _initWedgePool()
	for _ = 1, WEDGE_POOL_INITIAL do
		table.insert(wedgePool, _createWedge())
	end
end

local function _getWedge(): WedgePart
	local wedge: WedgePart
	if #wedgePool > 0 then
		wedge = table.remove(wedgePool, #wedgePool) :: WedgePart
	else
		wedge = _createWedge()
	end
	activePartsCount += 1
	return wedge
end

local function _returnWedge(wedge: WedgePart)
	wedge.Parent = nil
	wedge.Size = WEDGE_SIZE
	wedge.CanCollide = false
	wedge.Transparency = 0
	for _, child in wedge:GetChildren() do
		child:Destroy()
	end
	activePartsCount -= 1
	if #wedgePool < WEDGE_POOL_MAX then
		table.insert(wedgePool, wedge)
	else
		wedge:Destroy()
	end
end

-------------------------------------------------
-- Part pool (collision boxes)
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

local function _initPartPool()
	for _ = 1, PART_POOL_INITIAL do
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
	activePartsCount -= 1
	if #partPool < PART_POOL_MAX then
		table.insert(partPool, part)
	else
		part:Destroy()
	end
end

-------------------------------------------------
-- Pyramid creation (4 wedges per block)
-------------------------------------------------

local function _makePyramidParts(
	blockTypeId: number,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number
): { WedgePart }
	local halfBlock = BLOCK_SIZE / 2
	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local px = baseX + lx * BLOCK_SIZE + halfBlock
	local py = baseY + ly * BLOCK_SIZE + halfBlock
	local pz = baseZ + lz * BLOCK_SIZE + halfBlock

	local color = _getColor(blockTypeId)
	local mat = _getMaterial(blockTypeId)

	-- Checkerboard: alternate up/down pyramids
	local isUp = (lx + lz) % 2 == 0
	local cframes = if isUp then UP_CFRAMES else DOWN_CFRAMES
	local blockCF = CFrame.new(px, py, pz)

	local parts: { WedgePart } = {}
	for i = 1, 4 do
		local wedge = _getWedge()
		wedge.Color = color
		wedge.Material = mat
		wedge.Size = WEDGE_SIZE
		wedge.CanCollide = false
		wedge.Transparency = 0
		wedge.CFrame = blockCF * cframes[i]

		if blockTypeId == BlockType.EggNode and i == 1 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 230, 180)
			light.Brightness = 1
			light.Range = 15
			light.Parent = wedge
		end

		wedge.Parent = chunkContainer
		table.insert(parts, wedge)
	end

	return parts
end

-------------------------------------------------
-- Visibility checks
-------------------------------------------------

local function _isTransparent(blockId: number): boolean
	return blockId == BlockType.Air
end

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

local function _returnWedgeGroup(group: { WedgePart })
	for _, wedge in group do
		_returnWedge(wedge)
	end
end

local function _renderChunk(chunkKey: string, blocks: buffer)
	local existingPyramids = pyramidParts[chunkKey]
	if existingPyramids then
		for _, group in existingPyramids do
			_returnWedgeGroup(group)
		end
	end

	local existingSpecial = renderedSpecialParts[chunkKey]
	if existingSpecial then
		for _, group in existingSpecial do
			_returnWedgeGroup(group)
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
	local specialParts: { [number]: { WedgePart } } = {}
	renderedSpecialParts[chunkKey] = specialParts

	local pParts: { [number]: { WedgePart } } = {}
	pyramidParts[chunkKey] = pParts

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

				local group = _makePyramidParts(blockTypeId, cx, cy, cz, lx, ly, lz)
				if _isSpecialBlock(blockTypeId) then
					specialParts[idx] = group
				else
					pParts[idx] = group
				end

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
		if ly % 2 == 1 then
			task.wait()
		end
	end
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil

	local pParts = pyramidParts[chunkKey]
	if pParts then
		for _, group in pParts do
			_returnWedgeGroup(group)
		end
		pyramidParts[chunkKey] = nil
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
		for _, group in specialParts do
			_returnWedgeGroup(group)
		end
		renderedSpecialParts[chunkKey] = nil
	end

	chunkBlocks[chunkKey] = nil
end

-------------------------------------------------
-- Block update handling (surgical per-block)
-------------------------------------------------

local function _handleBlockUpdate(chunkKey: string, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)

	local pParts = pyramidParts[chunkKey]
	if not pParts then
		pParts = {}
		pyramidParts[chunkKey] = pParts
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

	if pParts[flatIndex] then
		_returnWedgeGroup(pParts[flatIndex])
		pParts[flatIndex] = nil
	end
	if sParts[flatIndex] then
		_returnWedgeGroup(sParts[flatIndex])
		sParts[flatIndex] = nil
	end
	if cParts[flatIndex] then
		_returnPart(cParts[flatIndex])
		cParts[flatIndex] = nil
	end

	if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
		local group = _makePyramidParts(blockTypeId, cx, cy, cz, lx, ly, lz)
		if _isSpecialBlock(blockTypeId) then
			sParts[flatIndex] = group
		else
			pParts[flatIndex] = group
		end

		local halfBlock = BLOCK_SIZE / 2
		local collisionPart = _getPart()
		collisionPart.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		collisionPart.Transparency = 1
		collisionPart.CanCollide = true
		collisionPart.CastShadow = false
		collisionPart.Position = Vector3.new(
			cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock,
			cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock,
			cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock
		)
		collisionPart.Parent = chunkContainer
		cParts[flatIndex] = collisionPart
	end

	local dirs = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
	for _, dir in dirs do
		local nx, ny, nz = lx + dir[1], ly + dir[2], lz + dir[3]
		if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
			continue
		end

		local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
		local nBlockType = buffer.readu8(blocks, nIdx)

		if nBlockType == BlockType.Air or _isSpecialBlock(nBlockType) then
			continue
		end

		local hasPyramid = pParts[nIdx] ~= nil
		local shouldRender = _isExposed(blocks, nx, ny, nz)

		if shouldRender and not hasPyramid then
			pParts[nIdx] = _makePyramidParts(nBlockType, cx, cy, cz, nx, ny, nz)
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
		elseif not shouldRender and hasPyramid then
			_returnWedgeGroup(pParts[nIdx])
			pParts[nIdx] = nil
			if cParts[nIdx] then
				_returnPart(cParts[nIdx])
				cParts[nIdx] = nil
			end
		end
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
	return #wedgePool + #partPool
end

-------------------------------------------------
-- Knit lifecycle
-------------------------------------------------

function ChunkRenderController:KnitInit()
	chunkContainer = Instance.new("Folder")
	chunkContainer.Name = "ChunkRender"
	chunkContainer.Parent = workspace

	_initWedgePool()
	_initPartPool()
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
