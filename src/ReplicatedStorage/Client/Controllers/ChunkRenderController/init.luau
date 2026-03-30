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

local PART_POOL_INITIAL = 2000
local PART_POOL_MAX = 8000
local WEDGE_POOL_INITIAL = 4000
local WEDGE_POOL_MAX = 16000

local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

--[=[
	@class ChunkRenderController
	Wedge/triangle renderer: blocks rendered as pairs of WedgeParts creating
	diagonal fold seams for a low-poly origami paper-fold aesthetic.
	Merges along X axis for performance while preserving fold detail per row.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local wedgePool: { WedgePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: BasePart } } = {}
local renderedWedges: { [string]: { Instance } } = {}
local collisionParts: { [string]: { [number]: BasePart } } = {}
local chunkBlocks: { [string]: buffer } = {}

local chunkContainer: Folder

-------------------------------------------------
-- Part pool (for special blocks + collision)
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
	if #partPool < PART_POOL_MAX then
		table.insert(partPool, part)
	else
		part:Destroy()
	end
end

-------------------------------------------------
-- Wedge pool
-------------------------------------------------

local function _createWedge(): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = true
	w.CastShadow = false
	return w
end

local function _getWedge(): WedgePart
	local w: WedgePart
	if #wedgePool > 0 then
		w = table.remove(wedgePool, #wedgePool) :: WedgePart
	else
		w = _createWedge()
	end
	activePartsCount += 1
	return w
end

local function _returnWedge(w: WedgePart)
	w.Parent = nil
	w.CanCollide = true
	w.Transparency = 0
	activePartsCount -= 1
	if #wedgePool < WEDGE_POOL_MAX then
		table.insert(wedgePool, w)
	else
		w:Destroy()
	end
end

local function _returnInstance(inst: Instance)
	if inst:IsA("WedgePart") then
		_returnWedge(inst :: WedgePart)
	elseif inst:IsA("BasePart") then
		_returnPart(inst :: BasePart)
	end
end

local function _initPool()
	for _ = 1, PART_POOL_INITIAL do
		table.insert(partPool, _createPart())
	end
	for _ = 1, WEDGE_POOL_INITIAL do
		table.insert(wedgePool, _createWedge())
	end
end

-------------------------------------------------
-- Special block Part creation
-------------------------------------------------

local function _makeSpecialPart(
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
-- Wedge meshing: merge along X, 2 WedgeParts per strip
-- Creates diagonal fold seams for origami aesthetic
-------------------------------------------------

-- CFrame to flip a wedge 180° around Z, filling the complementary
-- half of the block volume (upper triangle of Y-Z cross-section)
local FLIP_CF = CFrame.Angles(0, 0, math.pi)
-- CFrame to rotate 180° around Y for alternating fold direction
local ROTATE_Y = CFrame.Angles(0, math.pi, 0)

local function _wedgeMeshLayer(
	blocks: buffer,
	ly: number,
	cx: number,
	cy: number,
	cz: number
): { Instance }
	local result: { Instance } = {}

	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS
	local halfBlock = BLOCK_SIZE / 2

	for lz = 0, CHUNK_SIZE - 1 do
		local lx = 0
		while lx < CHUNK_SIZE do
			local idx = ChunkUtil.flatIndex(lx, ly, lz)
			local blockTypeId = buffer.readu8(blocks, idx)

			if blockTypeId == BlockType.Air or _isSpecialBlock(blockTypeId) then
				lx += 1
				continue
			end

			-- Merge same-type blocks along X
			local width = 1
			while lx + width < CHUNK_SIZE do
				local nIdx = ChunkUtil.flatIndex(lx + width, ly, lz)
				if buffer.readu8(blocks, nIdx) ~= blockTypeId then
					break
				end
				width += 1
			end

			local color = BlockRegistry.getColor(blockTypeId)
			local material = BlockRegistry.getMaterial(blockTypeId)
			local sizeW = width * BLOCK_SIZE

			local px = baseX + lx * BLOCK_SIZE + sizeW / 2
			local py = baseY + ly * BLOCK_SIZE + halfBlock
			local pz = baseZ + lz * BLOCK_SIZE + halfBlock

			-- Alternate fold direction by Z row for tessellated pattern
			local baseCF: CFrame
			if lz % 2 == 0 then
				baseCF = CFrame.new(px, py, pz)
			else
				baseCF = CFrame.new(px, py, pz) * ROTATE_Y
			end

			-- Primary wedge (lower triangle of Y-Z cross-section)
			local w1 = _getWedge()
			w1.Size = Vector3.new(sizeW, BLOCK_SIZE, BLOCK_SIZE)
			w1.Color = color
			w1.Material = material
			w1.CFrame = baseCF
			w1.Parent = chunkContainer
			table.insert(result, w1)

			-- Complement wedge (upper triangle, slightly smaller to prevent Z-fight)
			local w2 = _getWedge()
			w2.Size = Vector3.new(sizeW - 0.02, BLOCK_SIZE - 0.02, BLOCK_SIZE - 0.02)
			w2.Color = color
			w2.Material = material
			w2.CFrame = baseCF * FLIP_CF
			w2.Parent = chunkContainer
			table.insert(result, w2)

			lx += width
		end
	end

	return result
end

-------------------------------------------------
-- Chunk rendering
-------------------------------------------------

local function _renderChunk(chunkKey: string, blocks: buffer)
	-- Clear existing wedges
	local existingWedges = renderedWedges[chunkKey]
	if existingWedges then
		for _, inst in existingWedges do
			_returnInstance(inst)
		end
	end

	local existingParts = renderedSpecialParts[chunkKey]
	if existingParts then
		for _, part in existingParts do
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

	-- Collect special blocks
	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)
				if _isSpecialBlock(blockTypeId) then
					specialParts[idx] = _makeSpecialPart(blockTypeId, cx, cy, cz, lx, ly, lz)
				end
			end
		end
	end

	-- Wedge mesh per Y-layer
	local allWedges: { Instance } = {}
	renderedWedges[chunkKey] = allWedges

	for ly = 0, CHUNK_SIZE - 1 do
		local layerParts = _wedgeMeshLayer(blocks, ly, cx, cy, cz)
		for _, inst in layerParts do
			table.insert(allWedges, inst)
		end
		if ly % 4 == 3 then
			task.wait()
		end
	end

	-- Collision parts for raycast targeting (invisible, per exposed block)
	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS
	local cParts: { [number]: BasePart } = {}
	collisionParts[chunkKey] = cParts

	local collisionCount = 0
	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				if _isExposed(blocks, lx, ly, lz) then
					local idx = ChunkUtil.flatIndex(lx, ly, lz)
					local part = _getPart()
					part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
					part.Transparency = 1
					part.CanCollide = false
					part.CastShadow = false

					local halfBlock = BLOCK_SIZE / 2
					part.Position = Vector3.new(
						baseX + lx * BLOCK_SIZE + halfBlock,
						baseY + ly * BLOCK_SIZE + halfBlock,
						baseZ + lz * BLOCK_SIZE + halfBlock
					)
					part.Parent = chunkContainer

					cParts[idx] = part
					collisionCount += 1
				end
			end
		end
		if collisionCount > 200 then
			task.wait()
			collisionCount = 0
		end
	end
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil

	local wedges = renderedWedges[chunkKey]
	if wedges then
		for _, inst in wedges do
			_returnInstance(inst)
		end
		renderedWedges[chunkKey] = nil
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
-- Block update handling (re-render affected chunk)
-------------------------------------------------

local function _handleBlockUpdate(chunkKey: string, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	-- Re-render entire chunk (wedge strips need full pass)
	local savedBlocks = blocks
	_unrenderChunk(chunkKey)
	_renderChunk(chunkKey, savedBlocks)
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
	return #partPool + #wedgePool
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
