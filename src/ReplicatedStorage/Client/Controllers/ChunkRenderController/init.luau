--!strict

local Players = game:GetService("Players")
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

-- Part pool: no pre-allocation, parts created on demand and recycled
local POOL_MAX = 20000

-- Frame budget: 4ms per yield slice (conservative for mobile)
local FRAME_BUDGET = 0.004
-- Yield check frequency: every N blocks processed
local YIELD_CHECK_INTERVAL = 32

-- Single-part visual parameters (paper-crystal feel with minimal tilt)
local MAX_OFFSET = 0.08
local MAX_TILT = math.rad(3)
local TINT_RANGE = 0.08

-- CFrame-to-infinity: move parts far away instead of reparenting
local FAR_AWAY = CFrame.new(0, -1e6, 0)

-- BulkMoveTo batch size
local BATCH_FLUSH_SIZE = 64

-- Hoisted neighbor directions
local NEIGHBOR_DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

-- Override: PaperGrass renders as cream Paper visually
local GRASS_COLOR = Color3.fromRGB(245, 235, 220)
local GRASS_MATERIAL = Enum.Material.SmoothPlastic

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
	Single-part-per-block renderer with paper-crystal aesthetic.
	Each exposed block is one slightly tilted, color-varied part.
	75% fewer parts than the 3-layer system.
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local chunkParts: { [string]: { [number]: BasePart } } = {}
local chunkBlocks: { [string]: buffer } = {}

local chunkContainer: Folder

-- Render queue: process one chunk at a time with yields between
local renderQueue: { { key: string, blocks: buffer } } = {}
local isProcessingQueue = false

-------------------------------------------------
-- Debug HUD (visible on mobile)
-------------------------------------------------
local debugLabel: TextLabel? = nil
local topLabel: TextLabel? = nil
local DEBUG_MAX_LINES = 16
local debugLines: { string } = {}
local debugFrozen = false
local MIN_DURATION_MS = 1

-- Top 5 longest operations ever seen
local TOP_COUNT = 5
local topOps: { { ms: number, name: string } } = {}

local function _updateTopOps(ms: number, name: string)
	-- Insert if qualifies for top 5
	if #topOps < TOP_COUNT or ms > topOps[#topOps].ms then
		table.insert(topOps, { ms = ms, name = name })
		table.sort(topOps, function(a, b)
			return a.ms > b.ms
		end)
		if #topOps > TOP_COUNT then
			table.remove(topOps, #topOps + 1)
		end
	end
end

local function _refreshTopLabel()
	if debugFrozen or not topLabel then
		return
	end
	local lines = { "TOP 5 SLOWEST:" }
	for i, entry in topOps do
		table.insert(lines, string.format("%d. %.0fms %s", i, entry.ms, entry.name))
	end
	topLabel.Text = table.concat(lines, "\n")
end

local function _refreshDebugLabel()
	if debugFrozen or not debugLabel then
		return
	end
	local count = 0
	for _ in renderedChunks do
		count += 1
	end
	local header = string.format("P:%d A:%d Q:%d C:%d", #partPool, activePartsCount, #renderQueue, count)
	debugLabel.Text = header .. "\n" .. table.concat(debugLines, "\n")
end

local function _initDebugHUD()
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

	-- Recent log: right side, below top panel
	debugLabel = Instance.new("TextLabel")
	debugLabel.Size = UDim2.new(0.5, 0, 0, DEBUG_MAX_LINES * 16 + 4)
	debugLabel.Position = UDim2.new(1, -4, 0, 150)
	debugLabel.AnchorPoint = Vector2.new(1, 0)
	debugLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	debugLabel.BackgroundTransparency = 0.6
	debugLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
	debugLabel.Font = Enum.Font.RobotoMono
	debugLabel.TextSize = 14
	debugLabel.TextXAlignment = Enum.TextXAlignment.Left
	debugLabel.TextYAlignment = Enum.TextYAlignment.Top
	debugLabel.Text = ""
	debugLabel.TextWrapped = true
	debugLabel.Active = false
	debugLabel.Parent = gui

	-- Top 5 slowest: top-right corner
	topLabel = Instance.new("TextLabel")
	topLabel.Size = UDim2.new(0.4, 0, 0, 6 * 16 + 4)
	topLabel.Position = UDim2.new(1, -4, 0, 40)
	topLabel.AnchorPoint = Vector2.new(1, 0)
	topLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	topLabel.BackgroundTransparency = 0.5
	topLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
	topLabel.Font = Enum.Font.RobotoMono
	topLabel.TextSize = 14
	topLabel.TextXAlignment = Enum.TextXAlignment.Left
	topLabel.TextYAlignment = Enum.TextYAlignment.Top
	topLabel.Text = "TOP 5 SLOWEST:"
	topLabel.TextWrapped = true
	topLabel.Active = false
	topLabel.Parent = gui

	-- Freeze button
	local freezeBtn = Instance.new("TextButton")
	freezeBtn.Size = UDim2.new(0, 50, 0, 22)
	freezeBtn.Position = UDim2.new(1, -4, 0, 16)
	freezeBtn.AnchorPoint = Vector2.new(1, 0)
	freezeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	freezeBtn.BackgroundTransparency = 0.3
	freezeBtn.TextColor3 = Color3.fromRGB(255, 255, 0)
	freezeBtn.Font = Enum.Font.RobotoMono
	freezeBtn.TextSize = 12
	freezeBtn.Text = "FREEZE"
	freezeBtn.ZIndex = 10
	freezeBtn.Parent = gui

	freezeBtn.Activated:Connect(function()
		debugFrozen = not debugFrozen
		if debugFrozen then
			freezeBtn.Text = "GO"
			freezeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
		else
			freezeBtn.Text = "FREEZE"
			freezeBtn.TextColor3 = Color3.fromRGB(255, 255, 0)
			-- Refresh both panels on unfreeze
			_refreshDebugLabel()
			_refreshTopLabel()
		end
	end)
end

local _currentOp = "idle"
local _lastOpStart = 0

local function _finishCurrentOp()
	if _lastOpStart <= 0 then
		return
	end
	local duration = (os.clock() - _lastOpStart) * 1000
	_lastOpStart = 0

	if duration >= MIN_DURATION_MS then
		local line = string.format("%.0fms %s", duration, _currentOp)
		table.insert(debugLines, line)
		while #debugLines > DEBUG_MAX_LINES do
			table.remove(debugLines, 1)
		end
		_updateTopOps(duration, _currentOp)
	end
end

local function _debugLog(op: string)
	-- Close and log the previous operation with its correct name
	_finishCurrentOp()

	-- Start timing the new operation
	_currentOp = op
	_lastOpStart = os.clock()

	_refreshDebugLabel()
	_refreshTopLabel()
end

-- Yielding version: updates HUD then waits one frame so text is visible before heavy work
local function _debugLogWait(op: string)
	_debugLog(op)
	task.wait()
	-- Reset timer after yield so we only measure actual work
	_lastOpStart = os.clock()
end

local function _debugEnd()
	_finishCurrentOp()
	_currentOp = "idle"
	_refreshDebugLabel()
	_refreshTopLabel()
end

-------------------------------------------------
-- Part pool (CFrame-to-infinity, on-demand creation)
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
	if chunkContainer then
		part.Parent = chunkContainer
	end
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
-- BulkMoveTo batch
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

-------------------------------------------------
-- Single block part creation
-------------------------------------------------

local function _makeBlockPart(
	blockTypeId: number,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number,
	batched: boolean?
): BasePart
	local halfBlock = BLOCK_SIZE / 2
	local px = cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock
	local py = cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock
	local pz = cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock

	local seed = lx * 7919 + ly * 6271 + lz * 4153 + cx * 31 + cy * 13 + cz * 17

	-- Slight position offset for organic feel
	local ox = (_hash(seed, 1, 0, 0) - 0.5) * 2 * MAX_OFFSET
	local oz = (_hash(seed, 2, 0, 0) - 0.5) * 2 * MAX_OFFSET

	-- Slight tilt for crystal feel
	local tiltX = (_hash(seed, 3, 0, 0) - 0.5) * 2 * MAX_TILT
	local tiltZ = (_hash(seed, 4, 0, 0) - 0.5) * 2 * MAX_TILT

	-- Color tint variation
	local tint = 1.0 + (_hash(seed, 5, 0, 0) - 0.5) * 2 * TINT_RANGE
	local baseColor = _getColor(blockTypeId)
	local r = math.clamp(baseColor.R * tint, 0, 1)
	local g = math.clamp(baseColor.G * tint, 0, 1)
	local b = math.clamp(baseColor.B * tint, 0, 1)

	local part = _getPart()
	part.Color = Color3.new(r, g, b)
	part.Material = _getMaterial(blockTypeId)
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CanCollide = true
	part.CanQuery = true
	part.Transparency = 0

	local targetCFrame = CFrame.new(px + ox, py, pz + oz) * CFrame.Angles(tiltX, 0, tiltZ)

	if batched then
		table.insert(_batchParts, part)
		table.insert(_batchCFrames, targetCFrame)
		if #_batchParts >= BATCH_FLUSH_SIZE then
			_flushBatch()
		end
	else
		part.CFrame = targetCFrame
	end

	-- EggNode glow
	if blockTypeId == BlockType.EggNode then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 180)
		light.Brightness = 1
		light.Range = 15
		light.Parent = part
	end

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
	_debugLogWait("render " .. chunkKey)

	-- Clean up existing parts for this chunk
	local existing = chunkParts[chunkKey]
	if existing then
		for _, part in existing do
			_returnPart(part)
		end
	end

	chunkBlocks[chunkKey] = blocks
	renderedChunks[chunkKey] = true

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local parts: { [number]: BasePart } = {}
	chunkParts[chunkKey] = parts

	local renderStart = os.clock()
	local blocksProcessed = 0

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)

				if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
					parts[idx] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz, true)
				end

				-- Per-block frame budget check (every YIELD_CHECK_INTERVAL blocks)
				blocksProcessed += 1
				if blocksProcessed % YIELD_CHECK_INTERVAL == 0 and os.clock() - renderStart > FRAME_BUDGET then
					_flushBatch()
					task.wait()
					renderStart = os.clock()
				end
			end
		end
	end

	_flushBatch()
	_debugEnd()
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil

	local parts = chunkParts[chunkKey]
	if parts then
		for _, part in parts do
			_returnPart(part)
		end
		chunkParts[chunkKey] = nil
	end

	chunkBlocks[chunkKey] = nil
end

-------------------------------------------------
-- Block update (surgical per-block)
-------------------------------------------------

local function _handleBlockUpdate(chunkKey: string, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)

	local parts = chunkParts[chunkKey]
	if not parts then
		parts = {}
		chunkParts[chunkKey] = parts
	end

	-- Remove old part
	if parts[flatIndex] then
		_returnPart(parts[flatIndex])
		parts[flatIndex] = nil
	end

	-- Add new part if exposed
	if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
		parts[flatIndex] = _makeBlockPart(blockTypeId, cx, cy, cz, lx, ly, lz, false)
	end

	-- Update 6 neighbors
	for _, dir in NEIGHBOR_DIRS do
		local nx, ny, nz = lx + dir[1], ly + dir[2], lz + dir[3]
		if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
			continue
		end

		local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
		local nBlockType = buffer.readu8(blocks, nIdx)

		local hasPart = parts[nIdx] ~= nil
		local shouldRender = nBlockType ~= BlockType.Air and _isExposed(blocks, nx, ny, nz)

		if shouldRender and not hasPart then
			parts[nIdx] = _makeBlockPart(nBlockType, cx, cy, cz, nx, ny, nz, false)
		elseif not shouldRender and hasPart then
			_returnPart(parts[nIdx])
			parts[nIdx] = nil
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
	-- No pool pre-allocation: parts created on demand, recycled via pool
end

local function _processRenderQueue()
	if isProcessingQueue then
		return
	end
	isProcessingQueue = true

	-- Process chunks using index (avoids O(n^2) from table.remove(t, 1))
	local idx = 1
	while idx <= #renderQueue do
		local item = renderQueue[idx]
		_renderChunk(item.key, item.blocks)
		idx += 1
		-- Mandatory yield between chunks so other systems can breathe
		task.wait()
	end
	table.clear(renderQueue)

	isProcessingQueue = false
end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	WorldService.ChunkData:Connect(function(chunkKey: string, compressedBuffer: buffer)
		_debugLogWait("decompress " .. chunkKey)
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
