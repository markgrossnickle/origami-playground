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
local WEDGE_POOL_MAX = 200

local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

--[=[
	@class ChunkRenderController
	Wedge-cut renderer: each exposed block is a colored Part. When mining
	reaches 50%, the block is replaced with a WedgePart showing a diagonal
	cut based on the mining direction — like slicing origami paper.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local wedgePool: { WedgePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: BasePart } } = {}
local blockParts: { [string]: { [number]: BasePart } } = {}
local halfMinedWedges: { [string]: { [number]: WedgePart } } = {}
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
-- Wedge pool (small — only used for active mining)
-------------------------------------------------

local function _getWedge(): WedgePart
	local w: WedgePart
	if #wedgePool > 0 then
		w = table.remove(wedgePool, #wedgePool) :: WedgePart
	else
		w = Instance.new("WedgePart")
		w.Anchored = true
		w.CastShadow = false
	end
	w.CanCollide = true
	w.Transparency = 0
	activePartsCount += 1
	return w
end

local function _returnWedge(w: WedgePart)
	w.Parent = nil
	activePartsCount -= 1
	if #wedgePool < WEDGE_POOL_MAX then
		table.insert(wedgePool, w)
	else
		w:Destroy()
	end
end

-------------------------------------------------
-- Block Part creation
-------------------------------------------------

local function _makeBlockPart(
	blockTypeId: number,
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

	local part = _getPart()
	part.Color = BlockRegistry.getColor(blockTypeId)
	part.Material = BlockRegistry.getMaterial(blockTypeId)
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CanCollide = true
	part.Transparency = 0
	part.Position = Vector3.new(
		baseX + lx * BLOCK_SIZE + halfBlock,
		baseY + ly * BLOCK_SIZE + halfBlock,
		baseZ + lz * BLOCK_SIZE + halfBlock
	)

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
-- Wedge-cut orientation from hit normal
-------------------------------------------------

-- Default WedgePart slope goes from top-back (-Z) to bottom-front (+Z).
-- We rotate so the slope faces the mining direction (hit normal).
local function _getWedgeCFrame(position: Vector3, normal: Vector3): CFrame
	local baseCF = CFrame.new(position)
	local ax, ay, az = math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)

	if az >= ax and az >= ay then
		if normal.Z > 0 then
			return baseCF
		else
			return baseCF * CFrame.Angles(0, math.pi, 0)
		end
	elseif ax >= ay then
		if normal.X > 0 then
			return baseCF * CFrame.Angles(0, -math.pi / 2, 0)
		else
			return baseCF * CFrame.Angles(0, math.pi / 2, 0)
		end
	else
		if normal.Y > 0 then
			return baseCF * CFrame.Angles(math.pi / 2, 0, 0)
		else
			return baseCF * CFrame.Angles(-math.pi / 2, 0, 0)
		end
	end
end

-------------------------------------------------
-- Chunk rendering
-------------------------------------------------

local function _renderChunk(chunkKey: string, blocks: buffer)
	local existingBlocks = blockParts[chunkKey]
	if existingBlocks then
		for _, part in existingBlocks do
			_returnPart(part)
		end
	end

	local existingSpecial = renderedSpecialParts[chunkKey]
	if existingSpecial then
		for _, part in existingSpecial do
			_returnPart(part)
		end
	end

	-- Clean up any half-mined wedges
	local existingWedges = halfMinedWedges[chunkKey]
	if existingWedges then
		for _, w in existingWedges do
			_returnWedge(w)
		end
		halfMinedWedges[chunkKey] = nil
	end

	chunkBlocks[chunkKey] = blocks
	renderedChunks[chunkKey] = true

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local specialParts: { [number]: BasePart } = {}
	renderedSpecialParts[chunkKey] = specialParts

	local bParts: { [number]: BasePart } = {}
	blockParts[chunkKey] = bParts

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)

				if blockTypeId == BlockType.Air then
					continue
				end

				if _isSpecialBlock(blockTypeId) then
					specialParts[idx] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz)
				elseif _isExposed(blocks, lx, ly, lz) then
					bParts[idx] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz)
				end
			end
		end
		if ly % 4 == 3 then
			task.wait()
		end
	end
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil

	local bParts = blockParts[chunkKey]
	if bParts then
		for _, part in bParts do
			_returnPart(part)
		end
		blockParts[chunkKey] = nil
	end

	local specialParts = renderedSpecialParts[chunkKey]
	if specialParts then
		for _, part in specialParts do
			_returnPart(part)
		end
		renderedSpecialParts[chunkKey] = nil
	end

	local wedges = halfMinedWedges[chunkKey]
	if wedges then
		for _, w in wedges do
			_returnWedge(w)
		end
		halfMinedWedges[chunkKey] = nil
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

	-- Clean up half-mined wedge if present
	local wedges = halfMinedWedges[chunkKey]
	if wedges and wedges[flatIndex] then
		_returnWedge(wedges[flatIndex])
		wedges[flatIndex] = nil
	end

	local bParts = blockParts[chunkKey]
	if not bParts then
		bParts = {}
		blockParts[chunkKey] = bParts
	end

	local sParts = renderedSpecialParts[chunkKey]
	if not sParts then
		sParts = {}
		renderedSpecialParts[chunkKey] = sParts
	end

	if bParts[flatIndex] then
		_returnPart(bParts[flatIndex])
		bParts[flatIndex] = nil
	end
	if sParts[flatIndex] then
		_returnPart(sParts[flatIndex])
		sParts[flatIndex] = nil
	end

	if blockTypeId ~= BlockType.Air then
		if _isSpecialBlock(blockTypeId) then
			sParts[flatIndex] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz)
		elseif _isExposed(blocks, lx, ly, lz) then
			bParts[flatIndex] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz)
		end
	end

	-- Update 6 direct neighbors
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

		local hasBlockPart = bParts[nIdx] ~= nil
		local shouldRender = _isExposed(blocks, nx, ny, nz)

		if shouldRender and not hasBlockPart then
			bParts[nIdx] = _makeBlockPart(nBlockType, cx, cy, cz, nx, ny, nz)
		elseif not shouldRender and hasBlockPart then
			_returnPart(bParts[nIdx])
			bParts[nIdx] = nil
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
	return #partPool
end

-- Replace a block Part with a WedgePart showing a diagonal cut.
-- Called by MiningController at 50% mining progress.
function ChunkRenderController:HalfMineBlock(chunkKey: string, flatIndex: number, normalX: number, normalY: number, normalZ: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	local blockTypeId = buffer.readu8(blocks, flatIndex)
	if blockTypeId == BlockType.Air or _isSpecialBlock(blockTypeId) then
		return
	end

	-- Already half-mined
	local wedges = halfMinedWedges[chunkKey]
	if wedges and wedges[flatIndex] then
		return
	end

	-- Remove the full block Part
	local bParts = blockParts[chunkKey]
	if bParts and bParts[flatIndex] then
		_returnPart(bParts[flatIndex])
		bParts[flatIndex] = nil
	end

	-- Create wedge in its place
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local halfBlock = BLOCK_SIZE / 2
	local position = Vector3.new(
		cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock,
		cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock,
		cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock
	)

	local wedge = _getWedge()
	wedge.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	wedge.Color = BlockRegistry.getColor(blockTypeId)
	wedge.Material = BlockRegistry.getMaterial(blockTypeId)
	wedge.CFrame = _getWedgeCFrame(position, Vector3.new(normalX, normalY, normalZ))
	wedge.Parent = chunkContainer

	if not wedges then
		wedges = {}
		halfMinedWedges[chunkKey] = wedges
	end
	wedges[flatIndex] = wedge
end

-- Restore a half-mined block to its full Part (when mining stops/target changes).
function ChunkRenderController:ClearHalfMine(chunkKey: string, flatIndex: number)
	local wedges = halfMinedWedges[chunkKey]
	if not wedges or not wedges[flatIndex] then
		return
	end

	_returnWedge(wedges[flatIndex])
	wedges[flatIndex] = nil

	-- Restore the full block Part if still solid
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	local blockTypeId = buffer.readu8(blocks, flatIndex)
	if blockTypeId == BlockType.Air or _isSpecialBlock(blockTypeId) then
		return
	end

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	if not _isExposed(blocks, lx, ly, lz) then
		return
	end

	local bParts = blockParts[chunkKey]
	if not bParts then
		bParts = {}
		blockParts[chunkKey] = bParts
	end

	if not bParts[flatIndex] then
		local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
		bParts[flatIndex] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz)
	end
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
