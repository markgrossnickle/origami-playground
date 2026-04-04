--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

-- Pool
local POOL_MAX = 20000

-- Frame budget
local FRAME_BUDGET = 0.004
local YIELD_PART_INTERVAL = 64 -- yield check every N blocks iterated

-- Paper-crystal layer parameters (LOD 0 only)
local LAYERS_PER_BLOCK = 2
local LAYER_HEIGHT = BLOCK_SIZE / 2 * 0.9
local LAYER_GAP = BLOCK_SIZE / 2
local MAX_OFFSET = 0.15
local MAX_TILT = math.rad(8)
local LAYER_BRIGHTNESS = { 0.93, 1.07 }

-- Simple block parameters (LOD 1)
local SIMPLE_MAX_OFFSET = 0.08
local SIMPLE_MAX_TILT = math.rad(3)
local SIMPLE_TINT_RANGE = 0.08

-- LOD: squared chunk distance threshold
local LOD_NEAR_DIST2 = 2 -- dist <= 2 chunk = paper layers (~19 chunks)
local RENDER_MAX_DIST2 = 18 -- skip rendering chunks beyond this

-- CFrame-to-infinity
local FAR_AWAY = CFrame.new(0, -1e6, 0)

local BATCH_FLUSH_SIZE = 256

-- Trickle fill
local TRICKLE_FILL_PER_FRAME = 4
local TRICKLE_FILL_TARGET = 500

-- Small startup pool to reduce initial Instance.new calls
local POOL_STARTUP = 1000
local POOL_STARTUP_BATCH = 100

-- LOD re-evaluation interval
local LOD_CHECK_INTERVAL = 2.0

local NEIGHBOR_DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

local GRASS_COLOR = Color3.fromRGB(210, 130, 60) -- burnt orange sandstone
local GRASS_MATERIAL = Enum.Material.Sandstone

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

local function _tintColor(color: Color3, brightness: number): Color3
	local r = math.clamp(color.R * brightness, 0, 1)
	local g = math.clamp(color.G * brightness, 0, 1)
	local b = math.clamp(color.B * brightness, 0, 1)
	return Color3.new(r, g, b)
end

--[=[
	@class ChunkRenderController
	LOD renderer:
	  LOD 0 (near): 2 paper-crystal layers + invisible collision part
	  LOD 1 (far):  1 full-size block with tilt/tint (visual + collision)
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [string]: boolean } = {}
local chunkParts: { [string]: { [number]: { BasePart } } } = {}
local chunkBlocks: { [string]: buffer } = {}
local chunkLOD: { [string]: number } = {}

local chunkContainer: Folder

local renderQueue: { { key: string, blocks: buffer } } = {}
local isProcessingQueue = false

-- Character-ready gate
local characterReady = false
local pendingChunkData: { { key: string, blocks: buffer } } = {}

-- LOD re-evaluation timer
local lastLODCheck = 0

-------------------------------------------------
-- Debug HUD
-------------------------------------------------
local opsLabel: TextLabel? = nil
local framesLabel: TextLabel? = nil
local MIN_DURATION_MS = 1
local TOP_COUNT = 5
local topOps: { { ms: number, name: string } } = {}
local topFrames: { { ms: number, context: string } } = {}

local function _insertTop(list: { { ms: number, name: string } }, ms: number, name: string)
	if #list < TOP_COUNT or ms > list[#list].ms then
		table.insert(list, { ms = ms, name = name })
		table.sort(list, function(a, b)
			return a.ms > b.ms
		end)
		if #list > TOP_COUNT then
			table.remove(list, #list + 1)
		end
	end
end

local function _refreshOpsLabel()
	if not opsLabel then
		return
	end
	local lines = { "TOP 5 OPS:" }
	for i, entry in topOps do
		table.insert(lines, string.format("%d. %.0fms %s", i, entry.ms, entry.name))
	end
	opsLabel.Text = table.concat(lines, "\n")
end

local function _refreshFramesLabel()
	if not framesLabel then
		return
	end
	local lines = { "TOP 5 FRAMES (any cause):" }
	for i, entry in topFrames do
		table.insert(lines, string.format("%d. %.0fms [%s]", i, entry.ms, entry.name))
	end
	framesLabel.Text = table.concat(lines, "\n")
end

local _currentOp = "idle"
local _lastOpStart = 0

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

	framesLabel = Instance.new("TextLabel")
	framesLabel.Size = UDim2.new(0.55, 0, 0, 6 * 16 + 4)
	framesLabel.Position = UDim2.new(1, -4, 0, 40)
	framesLabel.AnchorPoint = Vector2.new(1, 0)
	framesLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	framesLabel.BackgroundTransparency = 0.5
	framesLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	framesLabel.Font = Enum.Font.RobotoMono
	framesLabel.TextSize = 14
	framesLabel.TextXAlignment = Enum.TextXAlignment.Left
	framesLabel.TextYAlignment = Enum.TextYAlignment.Top
	framesLabel.Text = "TOP 5 FRAMES (any cause):"
	framesLabel.TextWrapped = true
	framesLabel.Active = false
	framesLabel.Parent = gui

	opsLabel = Instance.new("TextLabel")
	opsLabel.Size = UDim2.new(0.55, 0, 0, 6 * 16 + 4)
	opsLabel.Position = UDim2.new(1, -4, 0, 40 + 6 * 16 + 8)
	opsLabel.AnchorPoint = Vector2.new(1, 0)
	opsLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	opsLabel.BackgroundTransparency = 0.5
	opsLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
	opsLabel.Font = Enum.Font.RobotoMono
	opsLabel.TextSize = 14
	opsLabel.TextXAlignment = Enum.TextXAlignment.Left
	opsLabel.TextYAlignment = Enum.TextYAlignment.Top
	opsLabel.Text = "TOP 5 OPS:"
	opsLabel.TextWrapped = true
	opsLabel.Active = false
	opsLabel.Parent = gui

	local clearBtn = Instance.new("TextButton")
	clearBtn.Size = UDim2.new(0, 50, 0, 22)
	clearBtn.Position = UDim2.new(1, -4, 0, 16)
	clearBtn.AnchorPoint = Vector2.new(1, 0)
	clearBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	clearBtn.BackgroundTransparency = 0.3
	clearBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
	clearBtn.Font = Enum.Font.RobotoMono
	clearBtn.TextSize = 12
	clearBtn.Text = "CLEAR"
	clearBtn.ZIndex = 10
	clearBtn.Parent = gui

	clearBtn.Activated:Connect(function()
		table.clear(topOps)
		table.clear(topFrames)
		_refreshOpsLabel()
		_refreshFramesLabel()
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local frameMs = dt * 1000
		if frameMs >= 30 then
			_insertTop(topFrames :: any, frameMs, _currentOp)
			_refreshFramesLabel()
		end
	end)
end

local function _finishCurrentOp()
	if _lastOpStart <= 0 then
		return
	end
	local duration = (os.clock() - _lastOpStart) * 1000
	_lastOpStart = 0
	if duration >= MIN_DURATION_MS then
		_insertTop(topOps, duration, _currentOp)
	end
end

local function _debugLog(op: string)
	_finishCurrentOp()
	_currentOp = op
	_lastOpStart = os.clock()
	_refreshOpsLabel()
end

local function _debugLogWait(op: string)
	_debugLog(op)
	task.wait()
	_lastOpStart = os.clock()
end

local function _debugEnd()
	_finishCurrentOp()
	_currentOp = "idle"
	_refreshOpsLabel()
end

-------------------------------------------------
-- LOD helper
-------------------------------------------------

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
		return -1 -- too far, skip rendering
	end
	if dist2 <= LOD_NEAR_DIST2 then
		return 0
	end
	return 1
end

-------------------------------------------------
-- Part pool
-------------------------------------------------

local function _createPart(): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
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

local function _trickleFillPool()
	if isProcessingQueue then
		return
	end
	if #partPool >= TRICKLE_FILL_TARGET then
		return
	end
	for _ = 1, TRICKLE_FILL_PER_FRAME do
		if #partPool >= TRICKLE_FILL_TARGET then
			break
		end
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
	part.CFrame = FAR_AWAY
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.CanCollide = false
	part.CanQuery = false
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

local function _returnGroup(group: { BasePart })
	for _, part in group do
		_returnPart(part)
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
-- LOD 0: Paper-crystal layers + collision part
-------------------------------------------------

local function _makeLayerParts(
	blockTypeId: number,
	cx: number, cy: number, cz: number,
	lx: number, ly: number, lz: number,
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

	-- 2 visual layers (no collision)
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
			if #_batchParts >= BATCH_FLUSH_SIZE then
				_flushBatch()
			end
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

	-- Invisible collision part (full block size)
	local collisionPart = _getPart()
	collisionPart.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	collisionPart.Transparency = 1
	collisionPart.CanCollide = true
	collisionPart.CanQuery = true

	local collisionCFrame = CFrame.new(px, baseY + ly * BLOCK_SIZE + halfBlock, pz)
	if batched then
		table.insert(_batchParts, collisionPart)
		table.insert(_batchCFrames, collisionCFrame)
		if #_batchParts >= BATCH_FLUSH_SIZE then
			_flushBatch()
		end
	else
		collisionPart.CFrame = collisionCFrame
	end
	table.insert(parts, collisionPart)

	return parts
end

-------------------------------------------------
-- LOD 1: Single full-size block (visual + collision)
-------------------------------------------------

local function _makeSimplePart(
	blockTypeId: number,
	cx: number, cy: number, cz: number,
	lx: number, ly: number, lz: number,
	batched: boolean?
): { BasePart }
	local halfBlock = BLOCK_SIZE / 2
	local px = cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock
	local py = cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock
	local pz = cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock

	local seed = lx * 7919 + ly * 6271 + lz * 4153 + cx * 31 + cy * 13 + cz * 17

	local ox = (_hash(seed, 1, 0, 0) - 0.5) * 2 * SIMPLE_MAX_OFFSET
	local oz = (_hash(seed, 2, 0, 0) - 0.5) * 2 * SIMPLE_MAX_OFFSET
	local tiltX = (_hash(seed, 3, 0, 0) - 0.5) * 2 * SIMPLE_MAX_TILT
	local tiltZ = (_hash(seed, 4, 0, 0) - 0.5) * 2 * SIMPLE_MAX_TILT

	local tint = 1.0 + (_hash(seed, 5, 0, 0) - 0.5) * 2 * SIMPLE_TINT_RANGE
	local baseColor = _getColor(blockTypeId)

	local part = _getPart()
	part.Color = _tintColor(baseColor, tint)
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

	if blockTypeId == BlockType.EggNode then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 230, 180)
		light.Brightness = 1
		light.Range = 15
		light.Parent = part
	end

	return { part }
end

-------------------------------------------------
-- Block creation dispatcher
-------------------------------------------------

local function _makeBlockParts(
	blockTypeId: number,
	cx: number, cy: number, cz: number,
	lx: number, ly: number, lz: number,
	lod: number,
	batched: boolean?
): { BasePart }
	if lod == 0 then
		return _makeLayerParts(blockTypeId, cx, cy, cz, lx, ly, lz, batched)
	else
		return _makeSimplePart(blockTypeId, cx, cy, cz, lx, ly, lz, batched)
	end
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
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lod = _getChunkLOD(cx, cy, cz)

	-- Store block data even for unrendered chunks (needed for mining/block updates)
	chunkBlocks[chunkKey] = blocks

	if lod == -1 then
		-- Too far to render, just keep data
		renderedChunks[chunkKey] = false
		chunkLOD[chunkKey] = lod
		return
	end

	_debugLogWait("render " .. chunkKey .. " L" .. lod)

	local existing = chunkParts[chunkKey]
	if existing then
		for _, group in existing do
			_returnGroup(group)
		end
	end

	renderedChunks[chunkKey] = true
	chunkLOD[chunkKey] = lod

	local parts: { [number]: { BasePart } } = {}
	chunkParts[chunkKey] = parts

	local renderStart = os.clock()
	local blockCount = 0

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, idx)

				if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
					local group = _makeBlockParts(blockTypeId, cx, cy, cz, lx, ly, lz, lod, true)
					parts[idx] = group
				end

				blockCount += 1
				if blockCount >= YIELD_PART_INTERVAL then
					blockCount = 0
					if os.clock() - renderStart > FRAME_BUDGET then
						_flushBatch()
						task.wait()
						renderStart = os.clock()
					end
				end
			end
		end
	end

	_flushBatch()
	_debugEnd()
end

local function _unrenderChunk(chunkKey: string)
	renderedChunks[chunkKey] = nil
	chunkLOD[chunkKey] = nil

	local parts = chunkParts[chunkKey]
	if parts then
		for _, group in parts do
			_returnGroup(group)
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
	local lod = chunkLOD[chunkKey] or 1

	local parts = chunkParts[chunkKey]
	if not parts then
		parts = {}
		chunkParts[chunkKey] = parts
	end

	if parts[flatIndex] then
		_returnGroup(parts[flatIndex])
		parts[flatIndex] = nil
	end

	if blockTypeId ~= BlockType.Air and _isExposed(blocks, lx, ly, lz) then
		parts[flatIndex] = _makeBlockParts(blockTypeId, cx, cy, cz, lx, ly, lz, lod, false)
	end

	for _, dir in NEIGHBOR_DIRS do
		local nx, ny, nz = lx + dir[1], ly + dir[2], lz + dir[3]
		if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
			continue
		end

		local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
		local nBlockType = buffer.readu8(blocks, nIdx)

		local hasGroup = parts[nIdx] ~= nil
		local shouldRender = nBlockType ~= BlockType.Air and _isExposed(blocks, nx, ny, nz)

		if shouldRender and not hasGroup then
			parts[nIdx] = _makeBlockParts(nBlockType, cx, cy, cz, nx, ny, nz, lod, false)
		elseif not shouldRender and hasGroup then
			_returnGroup(parts[nIdx])
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
-- Render queue processing
-------------------------------------------------

local function _processRenderQueue()
	if isProcessingQueue then
		return
	end
	isProcessingQueue = true

	-- Process in batches: swap out the queue so new arrivals go to a fresh table
	while #renderQueue > 0 do
		local batch = renderQueue
		renderQueue = {} -- new chunks arriving during rendering go here

		-- Sort: closest chunks first
		local pcx, pcy, pcz = _getPlayerChunkPos()
		if pcx and pcy and pcz then
			table.sort(batch, function(a, b)
				local acx, acy, acz = ChunkUtil.parseChunkKey(a.key)
				local bcx, bcy, bcz = ChunkUtil.parseChunkKey(b.key)
				local aDist = (acx - pcx) ^ 2 + (acy - pcy) ^ 2 + (acz - pcz) ^ 2
				local bDist = (bcx - pcx) ^ 2 + (bcy - pcy) ^ 2 + (bcz - pcz) ^ 2
				return aDist < bDist
			end)
		end

		-- Deduplicate: keep last occurrence of each chunkKey
		local seen: { [string]: boolean } = {}
		local deduped = {}
		for i = #batch, 1, -1 do
			local key = batch[i].key
			if not seen[key] then
				seen[key] = true
				table.insert(deduped, 1, batch[i])
			end
		end

		for _, item in deduped do
			_renderChunk(item.key, item.blocks)
			task.wait()
		end
	end

	isProcessingQueue = false
end

-------------------------------------------------
-- LOD re-evaluation
-------------------------------------------------

local function _reevaluateLODs()
	if not characterReady then
		return
	end
	local now = os.clock()
	if now - lastLODCheck < LOD_CHECK_INTERVAL then
		return
	end
	lastLODCheck = now

	-- Check all rendered chunks for LOD changes (player moved)
	for chunkKey, currentLod in chunkLOD do
		local blocks = chunkBlocks[chunkKey]
		if not blocks then
			continue
		end
		local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
		local newLod = _getChunkLOD(cx, cy, cz)
		if newLod ~= currentLod then
			table.insert(renderQueue, { key = chunkKey, blocks = blocks })
		end
	end

	if #renderQueue > 0 then
		_processRenderQueue()
	end
end

-------------------------------------------------
-- Knit lifecycle
-------------------------------------------------

function ChunkRenderController:KnitInit()
	chunkContainer = Instance.new("Folder")
	chunkContainer.Name = "ChunkRender"
	chunkContainer.Parent = workspace

	_initDebugHUD()

	-- Small startup pool, spread across frames
	for i = 1, POOL_STARTUP do
		table.insert(partPool, _createPart())
		if i % POOL_STARTUP_BATCH == 0 then
			task.wait()
		end
	end
end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")
	local player = Players.LocalPlayer

	-- Character-ready detection
	local function _onCharacterReady()
		if characterReady then
			return
		end
		characterReady = true

		-- Flush pending chunk data into render queue
		for _, item in pendingChunkData do
			table.insert(renderQueue, item)
		end
		table.clear(pendingChunkData)

		if #renderQueue > 0 then
			_processRenderQueue()
		end
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

	WorldService.ChunkData:Connect(function(chunkKey: string, compressedBuffer: buffer)
		_debugLogWait("decompress " .. chunkKey)
		local blocks = ChunkSerializer.decompress(compressedBuffer)
		_debugEnd()

		if not characterReady then
			table.insert(pendingChunkData, { key = chunkKey, blocks = blocks })
			return
		end

		table.insert(renderQueue, { key = chunkKey, blocks = blocks })
		_processRenderQueue()
	end)

	WorldService.ChunkUnload:Connect(function(chunkKey: string)
		_unrenderChunk(chunkKey)
	end)

	WorldService.BlockUpdate:Connect(function(chunkKey: string, flatIndex: number, blockTypeId: number)
		_handleBlockUpdate(chunkKey, flatIndex, blockTypeId)
	end)

	-- Heartbeat: trickle-fill pool and periodic LOD re-evaluation
	RunService.Heartbeat:Connect(function(_dt: number)
		_trickleFillPool()
		_reevaluateLODs()
	end)
end

return ChunkRenderController
