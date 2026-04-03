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

local POOL_INITIAL = 6000
local POOL_MAX = 25000

local LAYERS_PER_BLOCK = 3
local LAYER_HEIGHT = BLOCK_SIZE / LAYERS_PER_BLOCK * 0.9
local LAYER_GAP = BLOCK_SIZE / LAYERS_PER_BLOCK
local MAX_OFFSET = 0.15
local MAX_TILT = math.rad(8)

local LAYER_BRIGHTNESS = { 0.92, 1.0, 1.08 }

-- CFrame-to-infinity: move parts far away instead of reparenting
local FAR_AWAY = CFrame.new(0, -1e6, 0)

-- Frame budget for chunk rendering (seconds per yield slice)
local FRAME_BUDGET = 0.008

-- Hoisted neighbor directions for block update checks
local NEIGHBOR_DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

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
	Paper-crystal renderer: each exposed block is 3 thin slabs with
	crystal-like random tilt and slight elongation, merging paper-layers
	and crystal-shards aesthetics. No grass — surface starts cream/white.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local renderedSpecialParts: { [string]: { [number]: { BasePart } } } = {}
local layerParts: { [string]: { [number]: { BasePart } } } = {}
local collisionParts: { [string]: { [number]: BasePart } } = {}
local chunkBlocks: { [string]: buffer } = {}

local chunkContainer: Folder

-- Render queue: process one chunk at a time to prevent burst freezes
local renderQueue: { { key: string, blocks: buffer } } = {}
local isProcessingQueue = false

-------------------------------------------------
-- Debug HUD (visible on mobile)
-------------------------------------------------
local debugLabel: TextLabel? = nil

local function _initDebugHUD()
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ChunkDebugHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	gui.Parent = player.PlayerGui

	debugLabel = Instance.new("TextLabel")
	debugLabel.Size = UDim2.new(1, 0, 0, 80)
	debugLabel.Position = UDim2.new(0, 0, 0, 100)
	debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	debugLabel.BackgroundTransparency = 0.5
	debugLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	debugLabel.Font = Enum.Font.RobotoMono
	debugLabel.TextSize = 14
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextYAlignment = Enum.TextYAlignment.Top
	debugLabel.Text = "Debug HUD loading..."
	debugLabel.TextWrapped = true
	debugLabel.Parent = gui
end

local _lastOp = "idle"
local _lastOpStart = 0
local _lastDuration = 0

local function _debugLog(op: string)
	-- Close previous op
	if _lastOpStart > 0 then
		_lastDuration = (os.clock() - _lastOpStart) * 1000
	end
	_lastOp = op
	_lastOpStart = os.clock()

	if debugLabel then
		debugLabel.Text = string.format(
			"OP: %s | Last: %.0fms\nPool: %d | Active: %d | Queue: %d\nChunks rendered: %d",
			op,
			_lastDuration,
			#partPool,
			activePartsCount,
			#renderQueue,
			0 -- placeholder, counted below
		)
		local count = 0
		for _ in renderedChunks do
			count += 1
		end
		debugLabel.Text = string.format(
			"OP: %s | Last: %.0fms\nPool: %d | Active: %d | Queue: %d\nChunks: %d",
			op,
			_lastDuration,
			#partPool,
			activePartsCount,
			#renderQueue,
			count
		)
	end
end

local function _debugEnd()
	if _lastOpStart > 0 then
		_lastDuration = (os.clock() - _lastOpStart) * 1000
		_lastOpStart = 0
	end
	_debugLog("idle")
end

-------------------------------------------------
-- Part pool (CFrame-to-infinity pattern)
-------------------------------------------------

local function _createPart(): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CFrame = FAR_AWAY
	-- Parent once at creation, never change (avoids expensive replication)
	if chunkContainer then
		part.Parent = chunkContainer
	end
	return part
end

local function _initPool()
	_debugLog("initPool " .. POOL_INITIAL)
	for i = 1, POOL_INITIAL do
		table.insert(partPool, _createPart())
		-- Yield every 500 parts to prevent stall
		if i % 500 == 0 then
			_debugLog("initPool " .. i .. "/" .. POOL_INITIAL)
			task.wait()
		end
	end
	_debugEnd()
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
	-- Move far away instead of reparenting (CFrame-to-infinity)
	part.CFrame = FAR_AWAY
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CanCollide = true
	part.CanQuery = true
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
-- BulkMoveTo batch arrays
-------------------------------------------------

local _batchParts: { BasePart } = {}
local _batchCFrames: { CFrame } = {}

local function _flushBatch()
	if #_batchParts > 0 then
		workspace:BulkMoveTo(_batchParts, _batchCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(_batchParts)
		table.clear(_batchCFrames)
	end
end

-------------------------------------------------
-- Deterministic hash
-------------------------------------------------

local function _hash(a: number, b: number, c: number, d: number): number
	local h = a * 7919 + b * 6271 + c * 4153 + d * 1009
	return (h % 65521) / 65521
end

local function _tintColor(color: Color3, brightness: number): Color3
	local r = math.clamp(color.R * brightness, 0, 1)
	local g = math.clamp(color.G * brightness, 0, 1)
	local b = math.clamp(color.B * brightness, 0, 1)
	return Color3.new(r, g, b)
end

-------------------------------------------------
-- Paper-crystal slab creation
-------------------------------------------------

-- Creates visual layer parts. If batched=true, defers CFrame via BulkMoveTo arrays.
local function _makeLayerParts(
	blockTypeId: number,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number,
	batched: boolean?
): { BasePart }
	local halfBlock = BLOCK_SIZE / 2
	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local px = baseX + lx * BLOCK_SIZE + halfBlock
	local blockBottom = baseY + ly * BLOCK_SIZE
	local pz = baseZ + lz * BLOCK_SIZE + halfBlock

	local baseColor = _getColor(blockTypeId)
	local mat = _getMaterial(blockTypeId)

	local seed = lx * 7919 + ly * 6271 + lz * 4153 + cx * 31 + cy * 13 + cz * 17

	local parts: { BasePart } = {}
	for i = 1, LAYERS_PER_BLOCK do
		local layerSeed = seed + i * 1009

		local ox = (_hash(layerSeed, 1, 0, 0) - 0.5) * 2 * MAX_OFFSET
		local oz = (_hash(layerSeed, 2, 0, 0) - 0.5) * 2 * MAX_OFFSET
		local layerY = blockBottom + (i - 0.5) * LAYER_GAP

		local tiltX = (_hash(layerSeed, 3, 0, 0) - 0.5) * 2 * MAX_TILT
		local tiltZ = (_hash(layerSeed, 4, 0, 0) - 0.5) * 2 * MAX_TILT

		local stretchAxis = layerSeed % 2
		local sx, sz
		if stretchAxis == 0 then
			sx = BLOCK_SIZE * 1.08
			sz = BLOCK_SIZE * 0.92
		else
			sx = BLOCK_SIZE * 0.92
			sz = BLOCK_SIZE * 1.08
		end

		local part = _getPart()
		part.Color = _tintColor(baseColor, LAYER_BRIGHTNESS[i])
		part.Material = mat
		part.Size = Vector3.new(sx, LAYER_HEIGHT, sz)
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 0

		local targetCFrame = CFrame.new(px + ox, layerY, pz + oz) * CFrame.Angles(tiltX, 0, tiltZ)

		if batched then
			table.insert(_batchParts, part)
			table.insert(_batchCFrames, targetCFrame)
		else
			part.CFrame = targetCFrame
		end

		if blockTypeId == BlockType.EggNode and i == 2 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 230, 180)
			light.Brightness = 1
			light.Range = 15
			light.Parent = part
		end

		table.insert(parts, part)
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

local function _returnLayerGroup(group: { BasePart })
	for _, part in group do
		_returnPart(part)
	end
end

local function _renderChunk(chunkKey: string, blocks: buffer)
	_debugLog("render " .. chunkKey)
	local existingLayers = layerParts[chunkKey]
	if existingLayers then
		for _, group in existingLayers do
			_returnLayerGroup(group)
		end
	end

	local existingSpecial = renderedSpecialParts[chunkKey]
	if existingSpecial then
		for _, group in existingSpecial do
			_returnLayerGroup(group)
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
	local specialParts: { [number]: { BasePart } } = {}
	renderedSpecialParts[chunkKey] = specialParts

	local lParts: { [number]: { BasePart } } = {}
	layerParts[chunkKey] = lParts

	local cParts: { [number]: BasePart } = {}
	collisionParts[chunkKey] = cParts

	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local renderStart = os.clock()

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

				-- Visual layers (batched CFrame via BulkMoveTo)
				local group = _makeLayerParts(blockTypeId, cx, cy, cz, lx, ly, lz, true)
				if _isSpecialBlock(blockTypeId) then
					specialParts[idx] = group
				else
					lParts[idx] = group
				end

				-- Collision part (also batched)
				local collisionPart = _getPart()
				collisionPart.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
				collisionPart.Transparency = 1
				collisionPart.CanCollide = true
				collisionPart.CastShadow = false

				local halfBlock = BLOCK_SIZE / 2
				local collisionCFrame = CFrame.new(
					baseX + lx * BLOCK_SIZE + halfBlock,
					baseY + ly * BLOCK_SIZE + halfBlock,
					baseZ + lz * BLOCK_SIZE + halfBlock
				)
				table.insert(_batchParts, collisionPart)
				table.insert(_batchCFrames, collisionCFrame)
				cParts[idx] = collisionPart
			end
		end
		-- Frame budget: yield when we've used our time slice
		if os.clock() - renderStart > FRAME_BUDGET then
			_flushBatch()
			task.wait()
			renderStart = os.clock()
		end
	end

	-- Flush any remaining batched parts
	_flushBatch()
	_debugEnd()
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil

	local lParts = layerParts[chunkKey]
	if lParts then
		for _, group in lParts do
			_returnLayerGroup(group)
		end
		layerParts[chunkKey] = nil
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
			_returnLayerGroup(group)
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

	local lParts = layerParts[chunkKey]
	if not lParts then
		lParts = {}
		layerParts[chunkKey] = lParts
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

	if lParts[flatIndex] then
		_returnLayerGroup(lParts[flatIndex])
		lParts[flatIndex] = nil
	end
	if sParts[flatIndex] then
		_returnLayerGroup(sParts[flatIndex])
		sParts[flatIndex] = nil
	end
	if cParts[flatIndex] then
		_returnPart(cParts[flatIndex])
		cParts[flatIndex] = nil
	end

	if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
		-- Surgical update: set CFrame directly (not batched)
		local group = _makeLayerParts(blockTypeId, cx, cy, cz, lx, ly, lz, false)
		if _isSpecialBlock(blockTypeId) then
			sParts[flatIndex] = group
		else
			lParts[flatIndex] = group
		end

		local halfBlock = BLOCK_SIZE / 2
		local collisionPart = _getPart()
		collisionPart.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		collisionPart.Transparency = 1
		collisionPart.CanCollide = true
		collisionPart.CastShadow = false
		collisionPart.CFrame = CFrame.new(
			cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock,
			cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock,
			cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock
		)
		cParts[flatIndex] = collisionPart
	end

	-- Update 6 direct neighbors (using hoisted NEIGHBOR_DIRS)
	for _, dir in NEIGHBOR_DIRS do
		local nx, ny, nz = lx + dir[1], ly + dir[2], lz + dir[3]
		if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
			continue
		end

		local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
		local nBlockType = buffer.readu8(blocks, nIdx)

		if nBlockType == BlockType.Air or _isSpecialBlock(nBlockType) then
			continue
		end

		local hasLayer = lParts[nIdx] ~= nil
		local shouldRender = _isExposed(blocks, nx, ny, nz)

		if shouldRender and not hasLayer then
			lParts[nIdx] = _makeLayerParts(nBlockType, cx, cy, cz, nx, ny, nz, false)
			local halfBlock = BLOCK_SIZE / 2
			local cp = _getPart()
			cp.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
			cp.Transparency = 1
			cp.CanCollide = true
			cp.CastShadow = false
			cp.CFrame = CFrame.new(
				cx * CHUNK_STUDS + nx * BLOCK_SIZE + halfBlock,
				cy * CHUNK_STUDS + ny * BLOCK_SIZE + halfBlock,
				cz * CHUNK_STUDS + nz * BLOCK_SIZE + halfBlock
			)
			cParts[nIdx] = cp
		elseif not shouldRender and hasLayer then
			_returnLayerGroup(lParts[nIdx])
			lParts[nIdx] = nil
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

	_initDebugHUD()
	_initPool()
end

local function _processRenderQueue()
	if isProcessingQueue then
		return
	end
	isProcessingQueue = true
	while #renderQueue > 0 do
		local item = table.remove(renderQueue, 1)
		_renderChunk(item.key, item.blocks)
	end
	isProcessingQueue = false
end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	WorldService.ChunkData:Connect(function(chunkKey: string, compressedBuffer: buffer)
		_debugLog("decompress " .. chunkKey)
		local blocks = ChunkSerializer.decompress(compressedBuffer)
		table.insert(renderQueue, { key = chunkKey, blocks = blocks })
		_debugLog("queued " .. chunkKey .. " (q=" .. #renderQueue .. ")")
		_processRenderQueue()
	end)

	WorldService.ChunkUnload:Connect(function(chunkKey: string)
		_unrenderChunk(chunkKey)
	end)

	WorldService.BlockUpdate:Connect(function(chunkKey: string, flatIndex: number, blockTypeId: number)
		_handleBlockUpdate(chunkKey, flatIndex, blockTypeId)
	end)
end

return ChunkRenderController
