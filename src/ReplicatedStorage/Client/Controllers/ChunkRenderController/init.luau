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

local MAX_TILT = math.rad(15)

local function _isSpecialBlock(blockTypeId: number): boolean
	return blockTypeId == BlockType.Wood
		or blockTypeId == BlockType.Leaves
		or blockTypeId == BlockType.EggNode
end

--[=[
	@class ChunkRenderController
	Crystal-shards renderer: each exposed block is an elongated Part with
	deterministic random rotation, creating a jagged crystal cave aesthetic.
	Invisible axis-aligned collision parts handle raycasting and walking.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: BasePart } } = {}
local crystalParts: { [string]: { [number]: BasePart } } = {}
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
-- Deterministic crystal geometry
-------------------------------------------------

local function _hash(a: number, b: number, c: number, d: number): number
	local h = a * 7919 + b * 6271 + c * 4153 + d * 1009
	return (h % 65521) / 65521 -- 0..1
end

local function _getCrystalGeometry(
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number
): (Vector3, CFrame)
	local seed = lx * 7919 + ly * 6271 + lz * 4153 + cx * 31 + cy * 13 + cz * 17

	-- Pick elongation axis (0=X, 1=Y, 2=Z)
	local axisChoice = seed % 3
	local stretch = 1.3
	local shrink = 0.75

	local sx, sy, sz
	if axisChoice == 0 then
		sx = BLOCK_SIZE * stretch
		sy = BLOCK_SIZE * shrink
		sz = BLOCK_SIZE * shrink
	elseif axisChoice == 1 then
		sx = BLOCK_SIZE * shrink
		sy = BLOCK_SIZE * stretch
		sz = BLOCK_SIZE * shrink
	else
		sx = BLOCK_SIZE * shrink
		sy = BLOCK_SIZE * shrink
		sz = BLOCK_SIZE * stretch
	end

	-- Random rotation
	local tiltX = (_hash(seed, 1, 0, 0) - 0.5) * 2 * MAX_TILT
	local rotY = _hash(seed, 2, 0, 0) * math.pi * 2
	local tiltZ = (_hash(seed, 3, 0, 0) - 0.5) * 2 * MAX_TILT

	return Vector3.new(sx, sy, sz), CFrame.Angles(tiltX, rotY, tiltZ)
end

-------------------------------------------------
-- Crystal shard block creation
-------------------------------------------------

local function _makeCrystalPart(
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

	local px = baseX + lx * BLOCK_SIZE + halfBlock
	local py = baseY + ly * BLOCK_SIZE + halfBlock
	local pz = baseZ + lz * BLOCK_SIZE + halfBlock

	local size, rotation = _getCrystalGeometry(cx, cy, cz, lx, ly, lz)

	local part = _getPart()
	part.Color = BlockRegistry.getColor(blockTypeId)
	part.Material = BlockRegistry.getMaterial(blockTypeId)
	part.Size = size
	part.CanCollide = false
	part.Transparency = 0
	part.CFrame = CFrame.new(px, py, pz) * rotation

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
-- Chunk rendering
-------------------------------------------------

local function _renderChunk(chunkKey: string, blocks: buffer)
	local existingCrystals = crystalParts[chunkKey]
	if existingCrystals then
		for _, part in existingCrystals do
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

	local crParts: { [number]: BasePart } = {}
	crystalParts[chunkKey] = crParts

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
					specialParts[idx] = _makeCrystalPart(blockTypeId, cx, cy, cz, lx, ly, lz)
				else
					crParts[idx] = _makeCrystalPart(blockTypeId, cx, cy, cz, lx, ly, lz)
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

	local crParts = crystalParts[chunkKey]
	if crParts then
		for _, part in crParts do
			_returnPart(part)
		end
		crystalParts[chunkKey] = nil
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
-------------------------------------------------

local function _handleBlockUpdate(chunkKey: string, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)

	local crParts = crystalParts[chunkKey]
	if not crParts then
		crParts = {}
		crystalParts[chunkKey] = crParts
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

	-- Remove old parts
	if crParts[flatIndex] then
		_returnPart(crParts[flatIndex])
		crParts[flatIndex] = nil
	end
	if sParts[flatIndex] then
		_returnPart(sParts[flatIndex])
		sParts[flatIndex] = nil
	end
	if cParts[flatIndex] then
		_returnPart(cParts[flatIndex])
		cParts[flatIndex] = nil
	end

	-- Add new parts if non-air and exposed
	if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
		if _isSpecialBlock(blockTypeId) then
			sParts[flatIndex] = _makeCrystalPart(blockTypeId, cx, cy, cz, lx, ly, lz)
		else
			crParts[flatIndex] = _makeCrystalPart(blockTypeId, cx, cy, cz, lx, ly, lz)
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

		local hasCrystal = crParts[nIdx] ~= nil
		local shouldRender = _isExposed(blocks, nx, ny, nz)

		if shouldRender and not hasCrystal then
			crParts[nIdx] = _makeCrystalPart(nBlockType, cx, cy, cz, nx, ny, nz)
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
		elseif not shouldRender and hasCrystal then
			_returnPart(crParts[nIdx])
			crParts[nIdx] = nil
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
