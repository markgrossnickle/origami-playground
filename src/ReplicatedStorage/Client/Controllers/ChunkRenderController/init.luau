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
local POOL_MAX = 12000

local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

--[=[
	@class ChunkRenderController
	Greedy-mesh renderer: merges adjacent same-type blocks into larger Parts.
	Much fewer instances than per-block, crisp blocky aesthetic with custom colors.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: BasePart } } = {}
local renderedMeshParts: { [string]: { BasePart } } = {}
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
	-- Clear any children (lights on egg nodes)
	for _, child in ipairs(part:GetChildren()) do
		if not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	activePartsCount -= 1
	if #partPool < POOL_MAX then
		table.insert(partPool, part)
	else
		part:Destroy()
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
-- Greedy meshing: merge same-type blocks per Y layer
-------------------------------------------------

local function _greedyMeshLayer(
	blocks: buffer,
	ly: number,
	cx: number,
	cy: number,
	cz: number
): { BasePart }
	local visited = {} :: { [number]: boolean }
	local meshParts: { BasePart } = {}

	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS
	local halfBlock = BLOCK_SIZE / 2

	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			local key = lz * CHUNK_SIZE + lx
			if visited[key] then
				continue
			end

			local idx = ChunkUtil.flatIndex(lx, ly, lz)
			local blockTypeId = buffer.readu8(blocks, idx)

			if blockTypeId == BlockType.Air or _isSpecialBlock(blockTypeId) then
				continue
			end

			-- Expand width (along X)
			local width = 1
			while lx + width < CHUNK_SIZE do
				local nKey = lz * CHUNK_SIZE + (lx + width)
				if visited[nKey] then
					break
				end
				local nIdx = ChunkUtil.flatIndex(lx + width, ly, lz)
				local nType = buffer.readu8(blocks, nIdx)
				if nType ~= blockTypeId then
					break
				end
				width += 1
			end

			-- Expand depth (along Z)
			local depth = 1
			while lz + depth < CHUNK_SIZE do
				local rowMatch = true
				for dx = 0, width - 1 do
					local nKey = (lz + depth) * CHUNK_SIZE + (lx + dx)
					if visited[nKey] then
						rowMatch = false
						break
					end
					local nIdx = ChunkUtil.flatIndex(lx + dx, ly, lz + depth)
					local nType = buffer.readu8(blocks, nIdx)
					if nType ~= blockTypeId then
						rowMatch = false
						break
					end
				end
				if not rowMatch then
					break
				end
				depth += 1
			end

			-- Mark visited
			for dz = 0, depth - 1 do
				for dx = 0, width - 1 do
					visited[(lz + dz) * CHUNK_SIZE + (lx + dx)] = true
				end
			end

			-- Create merged Part
			local part = _getPart()
			part.Size = Vector3.new(width * BLOCK_SIZE, BLOCK_SIZE, depth * BLOCK_SIZE)
			part.Color = BlockRegistry.getColor(blockTypeId)
			part.Material = BlockRegistry.getMaterial(blockTypeId)
			part.CanCollide = true
			part.Transparency = 0
			part.CastShadow = false

			-- Position at center of merged rectangle
			local px = baseX + lx * BLOCK_SIZE + (width * BLOCK_SIZE) / 2
			local py = baseY + ly * BLOCK_SIZE + halfBlock
			local pz = baseZ + lz * BLOCK_SIZE + (depth * BLOCK_SIZE) / 2
			part.Position = Vector3.new(px, py, pz)
			part.Parent = chunkContainer

			table.insert(meshParts, part)
		end
	end

	return meshParts
end

-------------------------------------------------
-- Chunk rendering
-------------------------------------------------

local function _renderChunk(chunkKey: string, blocks: buffer)
	-- Clear existing mesh parts
	local existingMesh = renderedMeshParts[chunkKey]
	if existingMesh then
		for _, part in existingMesh do
			_returnPart(part)
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

	local allMeshParts: { BasePart } = {}
	renderedMeshParts[chunkKey] = allMeshParts

	-- Collect special blocks first
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

	-- Greedy mesh per Y layer
	for ly = 0, CHUNK_SIZE - 1 do
		local layerParts = _greedyMeshLayer(blocks, ly, cx, cy, cz)
		for _, part in ipairs(layerParts) do
			table.insert(allMeshParts, part)
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

	local meshParts = renderedMeshParts[chunkKey]
	if meshParts then
		for _, part in meshParts do
			_returnPart(part)
		end
		renderedMeshParts[chunkKey] = nil
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

	-- Re-render the entire chunk (greedy mesh needs full pass)
	-- Save blocks reference since _unrenderChunk clears it
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
