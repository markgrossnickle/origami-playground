--!strict

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local TerrainMaterialMap = require(script.TerrainMaterialMap)

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local CHUNK_STUDS = ChunkUtil.CHUNK_STUDS
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK

local POOL_INITIAL = 2000
local POOL_MAX = 8000

-- Special blocks rendered as individual Parts (not terrain)
local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

--[=[
	@class ChunkRenderController
	Receives chunk data from server, renders terrain using Roblox's Terrain system.
	Special blocks (wood, leaves, egg nodes) rendered as individual Parts.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: BasePart } } = {}
local collisionParts: { [string]: { [number]: BasePart } } = {}
local chunkBlocks: { [string]: buffer } = {}

local chunkContainer: Folder
local terrain: Terrain

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

	local centerX = baseX + lx * BLOCK_SIZE + halfBlock
	local centerY = baseY + ly * BLOCK_SIZE + halfBlock
	local centerZ = baseZ + lz * BLOCK_SIZE + halfBlock

	local part = _getPart()
	part.Color = BlockRegistry.getColor(blockTypeId)
	part.Material = BlockRegistry.getMaterial(blockTypeId)
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CanCollide = true
	part.Transparency = 0
	part.Position = Vector3.new(centerX, centerY, centerZ)

	-- Egg nodes get a subtle glow
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
-- Terrain fill helpers
-------------------------------------------------

local function _getBlockWorldCenter(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number): Vector3
	local halfBlock = BLOCK_SIZE / 2
	return Vector3.new(
		cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock,
		cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock,
		cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock
	)
end

local blockFillSize = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)

local function _fillTerrainBlock(worldCenter: Vector3, material: Enum.Material)
	terrain:FillBlock(CFrame.new(worldCenter), blockFillSize, material)
end

local function _clearTerrainBlock(worldCenter: Vector3)
	terrain:FillBlock(CFrame.new(worldCenter), blockFillSize, Enum.Material.Air)
end

-------------------------------------------------
-- Visibility checks for collision Parts
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

local function _renderChunk(chunkKey: string, blocks: buffer)
	if renderedChunks[chunkKey] then
		local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
		local chunkOrigin = Vector3.new(cx * CHUNK_STUDS, cy * CHUNK_STUDS, cz * CHUNK_STUDS)
		local chunkEnd = chunkOrigin + Vector3.new(CHUNK_STUDS, CHUNK_STUDS, CHUNK_STUDS)
		local region = Region3.new(chunkOrigin, chunkEnd):ExpandToGrid(4)
		terrain:FillRegion(region, 4, Enum.Material.Air)
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
	local parts: { [number]: BasePart } = {}
	renderedSpecialParts[chunkKey] = parts

	-- Pass 1: Batch terrain fills by material (one FillRegion per Y-layer per material)
	-- and collect special blocks
	local terrainBatch: { [Enum.Material]: { Vector3 } } = {}

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)

				if blockTypeId == BlockType.Air then
					continue
				end

				if _isSpecialBlock(blockTypeId) then
					parts[idx] = _makeSpecialPart(blockTypeId, cx, cy, cz, lx, ly, lz)
				else
					local terrainMat = TerrainMaterialMap.getMaterial(blockTypeId)
					if terrainMat then
						local center = _getBlockWorldCenter(cx, cy, cz, lx, ly, lz)
						if not terrainBatch[terrainMat] then
							terrainBatch[terrainMat] = {}
						end
						table.insert(terrainBatch[terrainMat], center)
					end
				end
			end
		end
	end

	-- Fill terrain in batches — yield once per material type instead of every 512 blocks
	for mat, positions in pairs(terrainBatch) do
		for _, center in ipairs(positions) do
			_fillTerrainBlock(center, mat)
		end
		task.wait()
	end

	-- Pass 2: Create invisible collision Parts only for exposed blocks
	-- (blocks with at least one air neighbor visible from surface)
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
					local px = baseX + lx * BLOCK_SIZE + halfBlock
					local py = baseY + ly * BLOCK_SIZE + halfBlock
					local pz = baseZ + lz * BLOCK_SIZE + halfBlock
					part.Position = Vector3.new(px, py, pz)
					part.Parent = chunkContainer

					cParts[idx] = part
					collisionCount += 1
				end
			end
		end
		-- Yield once per Y-layer for collision parts instead of never
		if collisionCount > 200 then
			task.wait()
			collisionCount = 0
		end
	end
end

local function _unrenderChunk(chunkKey: string)
	if renderedChunks[chunkKey] then
		local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
		local chunkOrigin = Vector3.new(cx * CHUNK_STUDS, cy * CHUNK_STUDS, cz * CHUNK_STUDS)
		local chunkEnd = chunkOrigin + Vector3.new(CHUNK_STUDS, CHUNK_STUDS, CHUNK_STUDS)
		local region = Region3.new(chunkOrigin, chunkEnd):ExpandToGrid(4)
		terrain:FillRegion(region, 4, Enum.Material.Air)
		renderedChunks[chunkKey] = nil
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
-- Block update handling
-------------------------------------------------

local function _handleBlockUpdate(chunkKey: string, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	local oldBlockTypeId = buffer.readu8(blocks, flatIndex)
	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)

	-- Clear and re-fill 3x3x3 neighborhood
	for dy = -1, 1 do
		for dz = -1, 1 do
			for dx = -1, 1 do
				local nx, ny, nz = lx + dx, ly + dy, lz + dz
				local ncx, ncy, ncz = cx, cy, cz
				local nlx, nly, nlz = nx, ny, nz

				if nx < 0 then
					ncx -= 1
					nlx = CHUNK_SIZE - 1
				elseif nx >= CHUNK_SIZE then
					ncx += 1
					nlx = 0
				end
				if ny < 0 then
					ncy -= 1
					nly = CHUNK_SIZE - 1
				elseif ny >= CHUNK_SIZE then
					ncy += 1
					nly = 0
				end
				if nz < 0 then
					ncz -= 1
					nlz = CHUNK_SIZE - 1
				elseif nz >= CHUNK_SIZE then
					ncz += 1
					nlz = 0
				end

				local nCenter = _getBlockWorldCenter(ncx, ncy, ncz, nlx, nly, nlz)
				_clearTerrainBlock(nCenter)
			end
		end
	end

	-- Re-fill solid blocks in neighborhood
	for dy = -1, 1 do
		for dz = -1, 1 do
			for dx = -1, 1 do
				local nx, ny, nz = lx + dx, ly + dy, lz + dz
				local ncx, ncy, ncz = cx, cy, cz
				local nlx, nly, nlz = nx, ny, nz

				if nx < 0 then
					ncx -= 1
					nlx = CHUNK_SIZE - 1
				elseif nx >= CHUNK_SIZE then
					ncx += 1
					nlx = 0
				end
				if ny < 0 then
					ncy -= 1
					nly = CHUNK_SIZE - 1
				elseif ny >= CHUNK_SIZE then
					ncy += 1
					nly = 0
				end
				if nz < 0 then
					ncz -= 1
					nlz = CHUNK_SIZE - 1
				elseif nz >= CHUNK_SIZE then
					ncz += 1
					nlz = 0
				end

				local neighborKey = ChunkUtil.chunkKey(ncx, ncy, ncz)
				local neighborBlocks = chunkBlocks[neighborKey]
				if neighborBlocks then
					local nIdx = ChunkUtil.flatIndex(nlx, nly, nlz)
					local nBlockType = buffer.readu8(neighborBlocks, nIdx)
					if nBlockType ~= BlockType.Air and not _isSpecialBlock(nBlockType) then
						local nMat = TerrainMaterialMap.getMaterial(nBlockType)
						if nMat then
							local nCenter = _getBlockWorldCenter(ncx, ncy, ncz, nlx, nly, nlz)
							_fillTerrainBlock(nCenter, nMat)
						end
					end
				end
			end
		end
	end

	-- Handle special block Parts
	local parts = renderedSpecialParts[chunkKey]
	if not parts then
		parts = {}
		renderedSpecialParts[chunkKey] = parts
	end

	if _isSpecialBlock(oldBlockTypeId) and parts[flatIndex] then
		_returnPart(parts[flatIndex])
		parts[flatIndex] = nil
	end

	if _isSpecialBlock(blockTypeId) then
		parts[flatIndex] = _makeSpecialPart(blockTypeId, cx, cy, cz, lx, ly, lz)
	end

	-- Update collision Parts
	local cParts = collisionParts[chunkKey]
	if not cParts then
		cParts = {}
		collisionParts[chunkKey] = cParts
	end

	local existingCollisionPart = cParts[flatIndex]
	if existingCollisionPart then
		_returnPart(existingCollisionPart)
		cParts[flatIndex] = nil
	end

	if blockTypeId ~= BlockType.Air and not _isSpecialBlock(blockTypeId) and _isExposed(blocks, lx, ly, lz) then
		local part = _getPart()
		part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		part.Transparency = 1
		part.CanCollide = false
		part.CastShadow = false
		local halfBlock = BLOCK_SIZE / 2
		part.Position = Vector3.new(
			cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock,
			cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock,
			cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock
		)
		part.Parent = chunkContainer
		cParts[flatIndex] = part
	end

	-- Update neighbors' collision Parts
	for dy = -1, 1 do
		for dz = -1, 1 do
			for dx = -1, 1 do
				if dx == 0 and dy == 0 and dz == 0 then
					continue
				end
				local manhattan = math.abs(dx) + math.abs(dy) + math.abs(dz)
				if manhattan ~= 1 then
					continue
				end

				local nx, ny, nz = lx + dx, ly + dy, lz + dz
				if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
					continue
				end

				local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
				local nBlockType = buffer.readu8(blocks, nIdx)

				local existingNPart = cParts[nIdx]
				local shouldBeVisible = nBlockType ~= BlockType.Air
					and not _isSpecialBlock(nBlockType)
					and _isExposed(blocks, nx, ny, nz)

				if shouldBeVisible and not existingNPart then
					local part = _getPart()
					part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
					part.Transparency = 1
					part.CanCollide = false
					part.CastShadow = false
					local halfBlock = BLOCK_SIZE / 2
					part.Position = Vector3.new(
						cx * CHUNK_STUDS + nx * BLOCK_SIZE + halfBlock,
						cy * CHUNK_STUDS + ny * BLOCK_SIZE + halfBlock,
						cz * CHUNK_STUDS + nz * BLOCK_SIZE + halfBlock
					)
					part.Parent = chunkContainer
					cParts[nIdx] = part
				elseif not shouldBeVisible and existingNPart then
					_returnPart(existingNPart)
					cParts[nIdx] = nil
				end
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
	return #partPool
end

-------------------------------------------------
-- Knit lifecycle
-------------------------------------------------

function ChunkRenderController:KnitInit()
	chunkContainer = Instance.new("Folder")
	chunkContainer.Name = "ChunkRender"
	chunkContainer.Parent = workspace

	terrain = workspace.Terrain

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
