--!strict
--!native

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local GreedyMesher = require(ReplicatedStorage.Shared.GreedyMesher)

type Region = GreedyMesher.Region

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local CHUNK_STUDS = ChunkUtil.CHUNK_STUDS
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK

-- Pool
local POOL_MAX = 30000

-- Frame budget
local FRAME_BUDGET = 0.008
local YIELD_REGION_INTERVAL = 32 -- yield check every N regions emitted

-- Paper-crystal layer parameters (LOD 0 only)
local LAYERS_PER_BLOCK = 2
local LAYER_HEIGHT = BLOCK_SIZE / 2 * 0.9
local LAYER_GAP = BLOCK_SIZE / 2
local MAX_OFFSET = 0.15
local MAX_TILT = math.rad(8)
local LAYER_BRIGHTNESS = { 0.93, 1.07 }

-- Precomputed Vector3 sizes for the single-cell hot path.
local LAYER_SIZE_A = Vector3.new(BLOCK_SIZE * 1.08, LAYER_HEIGHT, BLOCK_SIZE * 0.92)
local LAYER_SIZE_B = Vector3.new(BLOCK_SIZE * 0.92, LAYER_HEIGHT, BLOCK_SIZE * 1.08)
local COLLISION_SIZE = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
local SIMPLE_SIZE_DEFAULT = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)

-- Simple block parameters (LOD 1 single-cell)
local SIMPLE_MAX_OFFSET = 0.08
local SIMPLE_MAX_TILT = math.rad(3)
local SIMPLE_TINT_RANGE = 0.08

-- LOD: squared chunk distance threshold
local LOD_NEAR_DIST2 = 2 -- dist <= 2 chunk = paper layers (~19 chunks)
local RENDER_MAX_DIST2 = 18 -- skip rendering chunks beyond this

-- Bouncy block config
local BOUNCY_BLOCKS: { [number]: boolean } = {
	[BlockType.MushroomCap] = true,
	[BlockType.ShelfBracket] = true,
}
local BOUNCE_VEL_MIN = 60
local BOUNCE_VEL_MAX = 80
local BOUNCE_MULTIPLIER = 1.2
local BOUNCE_DEBOUNCE = 0.2
local FLASH_DURATION = 0.3
local MUSHROOM_FLASH_COLORS = {
	Color3.fromRGB(255, 0, 200),
	Color3.fromRGB(0, 220, 255),
	Color3.fromRGB(255, 230, 0),
	Color3.fromRGB(0, 255, 100),
	Color3.fromRGB(255, 140, 0),
}

-- CFrame-to-infinity
local FAR_AWAY = CFrame.new(0, -1e6, 0)

local BATCH_FLUSH_SIZE = 256

-- Trickle fill
local TRICKLE_FILL_PER_FRAME = 4
local TRICKLE_FILL_TARGET = 500

-- Leaf blocks that get random Y-rotation for organic look (not vines, not platform/shelf).
-- Only applied to single-cell regions; merged rectangles of leaves use a flat rotation.
local ROTATABLE_LEAVES: { [number]: boolean } = {
	[BlockType.Leaves] = true,
	[BlockType.CherryBlossom] = true,
	[BlockType.PineNeedle] = true,
	[BlockType.PalmFrond] = true,
	[BlockType.GladeCanopy] = true,
	[BlockType.FairyCanopy] = true,
	[BlockType.HollowCanopy] = true,
	[BlockType.BrassLeaf] = true,
	[BlockType.CoralCanopy] = true,
	[BlockType.AquamarineCanopy] = true,
	[BlockType.WarmPinkTop] = true,
	[BlockType.AuroraVioletCanopy] = true,
	[BlockType.InkSplatterLeaf] = true,
	[BlockType.PasteDripLeaf] = true,
	[BlockType.BalloonTop] = true,
	[BlockType.MoltenCap] = true,
	[BlockType.CyanCanopy] = true,
	[BlockType.CobaltDome] = true,
	[BlockType.BambooTop] = true,
	[BlockType.DustyCanopy] = true,
	[BlockType.CrayonCanopy] = true,
	[BlockType.RosePinkCanopy] = true,
	[BlockType.PinataLeaves] = true,
}

-- Small startup pool to reduce initial Instance.new calls.
local POOL_STARTUP = 200
local POOL_STARTUP_BATCH = 50

-- LOD re-evaluation interval
local LOD_CHECK_INTERVAL = 2.0

local NEIGHBOR_DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

-- Logging: print a one-liner per chunk with region/part counts so perf impact
-- is visible in the Output pane. Flip to false once the greedy renderer is
-- verified in production to avoid spam.
local LOG_CHUNK_RENDER = true

local function _getColor(blockTypeId: number): Color3
	return BlockRegistry.getColor(blockTypeId)
end

local function _getMaterial(blockTypeId: number): Enum.Material
	return BlockRegistry.getMaterial(blockTypeId)
end

local function _tintColor(color: Color3, brightness: number): Color3
	local r = math.clamp(color.R * brightness, 0, 1)
	local g = math.clamp(color.G * brightness, 0, 1)
	local b = math.clamp(color.B * brightness, 0, 1)
	return Color3.new(r, g, b)
end

-- LOD 0 layer tints are deterministic per (blockTypeId, layerIdx).
local _layerTintCache1: { [number]: Color3 } = {}
local _layerTintCache2: { [number]: Color3 } = {}

local function _getLayerTint(blockTypeId: number, layerIdx: number): Color3
	local cache = if layerIdx == 1 then _layerTintCache1 else _layerTintCache2
	local cached = cache[blockTypeId]
	if cached then
		return cached
	end
	local tinted = _tintColor(BlockRegistry.getColor(blockTypeId), LAYER_BRIGHTNESS[layerIdx])
	cache[blockTypeId] = tinted
	return tinted
end

--[=[
	@class ChunkRenderController
	Greedy-meshed LOD renderer:
	  LOD 0 (near): For merged regions of size > 1, 2 stretched paper-crystal
	    layers + 1 collision part (flat, no per-block tilt). For single-cell
	    regions, the original per-block tilt/offset path is used.
	  LOD 1 (far):  1 stretched Part per region (visual + collision).
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [number]: boolean } = {}
-- chunkParts[chunkKey][flatIndex] = { BasePart } shared group for every block
-- in the same region (all flat indices covered by a region point to the same
-- { BasePart } table). This is how mining splits find all parts to clean up.
local chunkParts: { [number]: { [number]: { BasePart } } } = {}
-- chunkRegions[chunkKey][flatIndex] = Region shared across all covered indices.
-- Used to compute the remesh bounding box when a block is edited.
local chunkRegions: { [number]: { [number]: Region } } = {}
local chunkBlocks: { [number]: buffer } = {}
local chunkLOD: { [number]: number } = {}

local chunkContainer: Folder

-- Track parts that have children (PointLights) to skip GetChildren on the 95%+ that don't
local _partsWithChildren: { [BasePart]: boolean } = {}

-- Deferred cleanup queue for returned parts (processed across frames)
local _cleanupQueue: { BasePart } = {}

-- Bouncy block tracking
local bouncyConns: { [BasePart]: RBXScriptConnection } = {}
local bouncyOrigColor: { [BasePart]: Color3 } = {}
local lastBounceTime: { [Player]: number } = {}

local function _cleanupBounce(part: BasePart)
	local conn = bouncyConns[part]
	if conn then
		conn:Disconnect()
		bouncyConns[part] = nil
		part.CanTouch = false
	end
	bouncyOrigColor[part] = nil
end

local renderQueue: { { key: number, blocks: buffer } } = {}
local isProcessingQueue = false

-- Character-ready gate
local characterReady = false
local pendingChunkData: { { key: number, blocks: buffer } } = {}

-- LOD re-evaluation timer
local lastLODCheck = 0
local _lastLODPlayerCx: number? = nil
local _lastLODPlayerCy: number? = nil
local _lastLODPlayerCz: number? = nil

-- LOD helper

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

-- Part pool

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
	_cleanupBounce(part)
	part.CFrame = FAR_AWAY
	if _partsWithChildren[part] then
		for _, child in part:GetChildren() do
			child:Destroy()
		end
		_partsWithChildren[part] = nil
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

-- BulkMoveTo batch

local _batchParts: { BasePart } = {}
local _batchCFrames: { CFrame } = {}

local function _flushBatch()
	if #_batchParts > 0 then
		workspace:BulkMoveTo(_batchParts, _batchCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(_batchParts)
		table.clear(_batchCFrames)
	end
end

-- Bulk-hide all unique groups in a chunk via BulkMoveTo. Because every flat
-- index of a merged region points to the SAME { BasePart } table, we track
-- which group tables we've already seen to avoid double-hiding.
local function _bulkHideChunkParts(chunkKey: number)
	local parts = chunkParts[chunkKey]
	if not parts then
		return
	end
	local seen: { [{ BasePart }]: boolean } = {}
	for _, group in parts do
		if seen[group] then
			continue
		end
		seen[group] = true
		for _, part in group do
			table.insert(_batchParts, part)
			table.insert(_batchCFrames, FAR_AWAY)
			if #_batchParts >= BATCH_FLUSH_SIZE then
				_flushBatch()
			end
		end
	end
	_flushBatch()
end

-- Queue a part for deferred cleanup (child destroy + pool return).
local function _queuePartForCleanup(part: BasePart)
	_cleanupBounce(part)
	activePartsCount -= 1
	table.insert(_cleanupQueue, part)
end

local function _processCleanupQueue()
	if #_cleanupQueue == 0 then
		return
	end
	local start = os.clock()
	local processed = 0
	while #_cleanupQueue > 0 do
		local part = table.remove(_cleanupQueue, #_cleanupQueue)
		if _partsWithChildren[part] then
			for _, child in part:GetChildren() do
				child:Destroy()
			end
			_partsWithChildren[part] = nil
		end
		if #partPool < POOL_MAX then
			table.insert(partPool, part)
		else
			part:Destroy()
		end
		processed += 1
		if processed % YIELD_REGION_INTERVAL == 0 then
			if os.clock() - start > FRAME_BUDGET then
				return
			end
		end
	end
end

-- Deterministic hash

local function _hash(a: number, b: number, c: number, d: number): number
	local h = a * 7919 + b * 6271 + c * 4153 + d * 1009
	return (h % 65521) / 65521
end

-- Willow vine taper: top block = full size, each block below loses 6% on X/Z
local VINE_TAPER_PER_BLOCK = 0.06
local VINE_TAPER_MIN = 0.2

local function _vineTaperFactor(blocks: buffer, lx: number, ly: number, lz: number): number
	local depth = 0
	local y = ly + 1
	while y < CHUNK_SIZE do
		local id = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, y, lz))
		if id ~= BlockType.WillowVine then
			break
		end
		depth += 1
		y += 1
	end
	return math.max(VINE_TAPER_MIN, 1 - depth * VINE_TAPER_PER_BLOCK)
end

-- Single-cell LOD 0 path: preserves the original paper-crystal per-block tilt/offset.
local function _makeSingleLayerParts(
	blocks: buffer,
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
		local rotY = if ROTATABLE_LEAVES[blockTypeId] then _hash(layerSeed, 6, 0, 0) * math.pi * 2 else 0

		local stretchAxis = layerSeed % 2

		local part = _getPart()
		part.Color = _getLayerTint(blockTypeId, i)
		part.Material = mat
		if blockTypeId == BlockType.WillowVine then
			local taper = _vineTaperFactor(blocks, lx, ly, lz)
			local baseSx = if stretchAxis == 0 then BLOCK_SIZE * 1.08 else BLOCK_SIZE * 0.92
			local baseSz = if stretchAxis == 0 then BLOCK_SIZE * 0.92 else BLOCK_SIZE * 1.08
			part.Size = Vector3.new(baseSx * taper, LAYER_HEIGHT, baseSz * taper)
		else
			part.Size = if stretchAxis == 0 then LAYER_SIZE_A else LAYER_SIZE_B
		end
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 0

		local targetCFrame = CFrame.new(px + ox, layerY, pz + oz) * CFrame.Angles(tiltX, rotY, tiltZ)

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
			_partsWithChildren[part] = true
		end

		table.insert(parts, part)
	end

	-- Invisible collision part (full block size)
	local collisionPart = _getPart()
	collisionPart.Size = COLLISION_SIZE
	collisionPart.Transparency = 1
	collisionPart.CanCollide = true
	collisionPart.CanQuery = true

	local collisionCFrame = CFrame.new(px, blockBottom + halfBlock, pz)
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

	if BOUNCY_BLOCKS[blockTypeId] then
		collisionPart.CanTouch = true
		bouncyOrigColor[collisionPart] = _getColor(blockTypeId)

		local visualParts = {}
		for i = 1, #parts - 1 do
			table.insert(visualParts, parts[i])
		end

		local conn = collisionPart.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not character then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or not humanoid.RootPart then
				return
			end
			local rootPart = humanoid.RootPart

			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end

			local vel = rootPart.AssemblyLinearVelocity
			if vel.Y > -5 then
				return
			end

			local now = os.clock()
			if lastBounceTime[player] and now - lastBounceTime[player] < BOUNCE_DEBOUNCE then
				return
			end
			lastBounceTime[player] = now

			local bounceY = math.min(BOUNCE_VEL_MAX, math.max(BOUNCE_VEL_MIN, -vel.Y * BOUNCE_MULTIPLIER))
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, bounceY, vel.Z)

			local flashColor = MUSHROOM_FLASH_COLORS[math.random(1, #MUSHROOM_FLASH_COLORS)]
			local savedColors = {}
			for _, vp in visualParts do
				table.insert(savedColors, vp.Color)
				vp.Color = flashColor
			end
			task.delay(FLASH_DURATION, function()
				for idx, vp in visualParts do
					if bouncyConns[collisionPart] then
						vp.Color = savedColors[idx]
					end
				end
			end)

			local sound = Instance.new("Sound")
			sound.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
			sound.Volume = 0.5
			sound.Parent = collisionPart
			sound:Play()
			task.delay(1, function()
				sound:Destroy()
			end)
		end)

		bouncyConns[collisionPart] = conn
	end

	return parts
end

-- Single-cell LOD 1 path: preserves per-block tilt/offset for isolated blocks.
local function _makeSingleSimplePart(
	blocks: buffer,
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
	local px = cx * CHUNK_STUDS + lx * BLOCK_SIZE + halfBlock
	local py = cy * CHUNK_STUDS + ly * BLOCK_SIZE + halfBlock
	local pz = cz * CHUNK_STUDS + lz * BLOCK_SIZE + halfBlock

	local seed = lx * 7919 + ly * 6271 + lz * 4153 + cx * 31 + cy * 13 + cz * 17

	local ox = (_hash(seed, 1, 0, 0) - 0.5) * 2 * SIMPLE_MAX_OFFSET
	local oz = (_hash(seed, 2, 0, 0) - 0.5) * 2 * SIMPLE_MAX_OFFSET
	local tiltX = (_hash(seed, 3, 0, 0) - 0.5) * 2 * SIMPLE_MAX_TILT
	local tiltZ = (_hash(seed, 4, 0, 0) - 0.5) * 2 * SIMPLE_MAX_TILT
	local rotY = if ROTATABLE_LEAVES[blockTypeId] then _hash(seed, 6, 0, 0) * math.pi * 2 else 0

	local tint = 1.0 + (_hash(seed, 5, 0, 0) - 0.5) * 2 * SIMPLE_TINT_RANGE
	local baseColor = _getColor(blockTypeId)

	local part = _getPart()
	part.Color = _tintColor(baseColor, tint)
	part.Material = _getMaterial(blockTypeId)
	if blockTypeId == BlockType.WillowVine then
		local taper = _vineTaperFactor(blocks, lx, ly, lz)
		part.Size = Vector3.new(BLOCK_SIZE * taper, BLOCK_SIZE, BLOCK_SIZE * taper)
	else
		part.Size = SIMPLE_SIZE_DEFAULT
	end
	part.CanCollide = true
	part.CanQuery = false
	part.Transparency = 0

	local targetCFrame = CFrame.new(px + ox, py, pz + oz) * CFrame.Angles(tiltX, rotY, tiltZ)

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
		_partsWithChildren[part] = true
	end

	if BOUNCY_BLOCKS[blockTypeId] then
		part.CanTouch = true
		bouncyOrigColor[part] = part.Color
		local origColor = part.Color
		local conn = part.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not character then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			local rootPart = humanoid.RootPart
			if not rootPart then
				return
			end

			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end

			local vel = rootPart.AssemblyLinearVelocity
			if vel.Y > -5 then
				return
			end

			local now = os.clock()
			if lastBounceTime[player] and now - lastBounceTime[player] < BOUNCE_DEBOUNCE then
				return
			end
			lastBounceTime[player] = now

			local bounceY = math.min(BOUNCE_VEL_MAX, math.max(BOUNCE_VEL_MIN, -vel.Y * BOUNCE_MULTIPLIER))
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, bounceY, vel.Z)

			local flashColor = MUSHROOM_FLASH_COLORS[math.random(1, #MUSHROOM_FLASH_COLORS)]
			part.Color = flashColor
			task.delay(FLASH_DURATION, function()
				if bouncyOrigColor[part] then
					part.Color = origColor
				end
			end)

			local sound = Instance.new("Sound")
			sound.SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3"
			sound.Volume = 0.5
			sound.PlayOnRemove = false
			sound.Parent = part
			sound:Play()
			task.delay(1, function()
				sound:Destroy()
			end)
		end)

		bouncyConns[part] = conn
	end

	return { part }
end

-- Multi-cell LOD 0: stretched paper-crystal layers + stretched collision plate.
-- Flat (no tilt) across the whole region.
local function _makeRegionLayerParts(
	region: Region,
	cx: number,
	cy: number,
	cz: number,
	batched: boolean?
): { BasePart }
	local blockTypeId = region.blockTypeId
	local sx = (region.maxLx - region.minLx + 1) * BLOCK_SIZE
	local sz = (region.maxLz - region.minLz + 1) * BLOCK_SIZE

	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local centerX = baseX + (region.minLx + region.maxLx + 1) / 2 * BLOCK_SIZE
	local blockBottom = baseY + region.minLy * BLOCK_SIZE
	local centerZ = baseZ + (region.minLz + region.maxLz + 1) / 2 * BLOCK_SIZE

	local mat = _getMaterial(blockTypeId)
	local parts: { BasePart } = {}

	for i = 1, LAYERS_PER_BLOCK do
		local layerY = blockBottom + (i - 0.5) * LAYER_GAP
		local part = _getPart()
		part.Color = _getLayerTint(blockTypeId, i)
		part.Material = mat
		-- Alternate subtle stretch direction per layer (1.08/0.92) to keep the
		-- layered paper look on flat surfaces.
		if i == 1 then
			part.Size = Vector3.new(sx * 1.04, LAYER_HEIGHT, sz * 0.96)
		else
			part.Size = Vector3.new(sx * 0.96, LAYER_HEIGHT, sz * 1.04)
		end
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 0

		local targetCFrame = CFrame.new(centerX, layerY, centerZ)
		if batched then
			table.insert(_batchParts, part)
			table.insert(_batchCFrames, targetCFrame)
			if #_batchParts >= BATCH_FLUSH_SIZE then
				_flushBatch()
			end
		else
			part.CFrame = targetCFrame
		end

		table.insert(parts, part)
	end

	-- Stretched collision plate.
	local collisionPart = _getPart()
	collisionPart.Size = Vector3.new(sx, BLOCK_SIZE, sz)
	collisionPart.Transparency = 1
	collisionPart.CanCollide = true
	collisionPart.CanQuery = true
	local halfBlock = BLOCK_SIZE / 2
	local collisionCFrame = CFrame.new(centerX, blockBottom + halfBlock, centerZ)
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

-- Multi-cell LOD 1: single stretched Part.
local function _makeRegionSimplePart(
	region: Region,
	cx: number,
	cy: number,
	cz: number,
	batched: boolean?
): { BasePart }
	local blockTypeId = region.blockTypeId
	local sx = (region.maxLx - region.minLx + 1) * BLOCK_SIZE
	local sz = (region.maxLz - region.minLz + 1) * BLOCK_SIZE

	local baseX = cx * CHUNK_STUDS
	local baseY = cy * CHUNK_STUDS
	local baseZ = cz * CHUNK_STUDS

	local centerX = baseX + (region.minLx + region.maxLx + 1) / 2 * BLOCK_SIZE
	local centerY = baseY + (region.minLy + region.maxLy + 1) / 2 * BLOCK_SIZE
	local centerZ = baseZ + (region.minLz + region.maxLz + 1) / 2 * BLOCK_SIZE

	-- Flat tint per region (seeded by min corner for determinism).
	local seed = region.minLx * 7919 + region.minLy * 6271 + region.minLz * 4153 + cx * 31 + cy * 13 + cz * 17
	local tint = 1.0 + (_hash(seed, 5, 0, 0) - 0.5) * 2 * SIMPLE_TINT_RANGE
	local baseColor = _getColor(blockTypeId)

	local part = _getPart()
	part.Color = _tintColor(baseColor, tint)
	part.Material = _getMaterial(blockTypeId)
	part.Size = Vector3.new(sx, BLOCK_SIZE, sz)
	part.CanCollide = true
	part.CanQuery = false
	part.Transparency = 0

	local targetCFrame = CFrame.new(centerX, centerY, centerZ)
	if batched then
		table.insert(_batchParts, part)
		table.insert(_batchCFrames, targetCFrame)
		if #_batchParts >= BATCH_FLUSH_SIZE then
			_flushBatch()
		end
	else
		part.CFrame = targetCFrame
	end

	return { part }
end

-- Build parts for one region. Dispatches based on LOD and region size.
local function _makeRegionParts(
	blocks: buffer,
	region: Region,
	cx: number,
	cy: number,
	cz: number,
	lod: number,
	batched: boolean?
): { BasePart }
	local isSingle = region.minLx == region.maxLx and region.minLy == region.maxLy and region.minLz == region.maxLz
	if isSingle then
		if lod == 0 then
			return _makeSingleLayerParts(
				blocks,
				region.blockTypeId,
				cx,
				cy,
				cz,
				region.minLx,
				region.minLy,
				region.minLz,
				batched
			)
		else
			return _makeSingleSimplePart(
				blocks,
				region.blockTypeId,
				cx,
				cy,
				cz,
				region.minLx,
				region.minLy,
				region.minLz,
				batched
			)
		end
	else
		if lod == 0 then
			return _makeRegionLayerParts(region, cx, cy, cz, batched)
		else
			return _makeRegionSimplePart(region, cx, cy, cz, batched)
		end
	end
end

-- Register a region's parts into the chunk-level lookup tables. Every flat
-- index covered by the region points to the SAME group and region objects.
local function _registerRegion(
	chunkKey: number,
	region: Region,
	group: { BasePart },
	parts: { [number]: { BasePart } },
	regions: { [number]: Region }
)
	for ly = region.minLy, region.maxLy do
		for lz = region.minLz, region.maxLz do
			for lx = region.minLx, region.maxLx do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				parts[idx] = group
				regions[idx] = region
			end
		end
	end
end

-- Chunk rendering

local function _renderChunk(chunkKey: number, blocks: buffer)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lod = _getChunkLOD(cx, cy, cz)

	chunkBlocks[chunkKey] = blocks

	if lod == -1 then
		-- Too far to render, just keep data.
		renderedChunks[chunkKey] = false
		chunkLOD[chunkKey] = lod
		return
	end

	local existingParts = chunkParts[chunkKey]
	if existingParts then
		_bulkHideChunkParts(chunkKey)
		local seen: { [{ BasePart }]: boolean } = {}
		for _, group in existingParts do
			if seen[group] then
				continue
			end
			seen[group] = true
			for _, part in group do
				_queuePartForCleanup(part)
			end
		end
	end

	renderedChunks[chunkKey] = true
	chunkLOD[chunkKey] = lod

	local parts: { [number]: { BasePart } } = {}
	local regions: { [number]: Region } = {}
	chunkParts[chunkKey] = parts
	chunkRegions[chunkKey] = regions

	local meshed = GreedyMesher.meshChunk(blocks)

	local renderStart = os.clock()
	local emittedPartCount = 0
	local emittedRegions = 0

	for i, region in meshed do
		local group = _makeRegionParts(blocks, region, cx, cy, cz, lod, true)
		_registerRegion(chunkKey, region, group, parts, regions)
		emittedPartCount += #group
		emittedRegions += 1

		if i % YIELD_REGION_INTERVAL == 0 then
			if os.clock() - renderStart > FRAME_BUDGET then
				_flushBatch()
				task.wait()
				renderStart = os.clock()
			end
		end
	end

	_flushBatch()

	if LOG_CHUNK_RENDER then
		-- Estimate what the non-greedy renderer would have emitted for comparison.
		-- LOD 0: 3 parts per exposed block. LOD 1: 1 part per exposed block.
		local exposedBlocks = 0
		for _, region in meshed do
			exposedBlocks += (region.maxLx - region.minLx + 1) * (region.maxLy - region.minLy + 1) * (region.maxLz - region.minLz + 1)
		end
		local wouldHaveEmitted = if lod == 0 then exposedBlocks * 3 else exposedBlocks
		print(
			string.format(
				"[ChunkRenderer] chunk=(%d,%d,%d) lod=%d regions=%d parts=%d (was ~%d)",
				cx,
				cy,
				cz,
				lod,
				emittedRegions,
				emittedPartCount,
				wouldHaveEmitted
			)
		)
	end
end

local function _unrenderChunk(chunkKey: number)
	renderedChunks[chunkKey] = nil
	chunkLOD[chunkKey] = nil

	local parts = chunkParts[chunkKey]
	if parts then
		_bulkHideChunkParts(chunkKey)
		local seen: { [{ BasePart }]: boolean } = {}
		for _, group in parts do
			if seen[group] then
				continue
			end
			seen[group] = true
			for _, part in group do
				_queuePartForCleanup(part)
			end
		end
		chunkParts[chunkKey] = nil
	end

	chunkRegions[chunkKey] = nil
	chunkBlocks[chunkKey] = nil
end

-- Block update (greedy-mesh split/remesh).
-- The affected re-mesh box is the bounding box of:
--  1. The old region containing the edited block (if any), expanded by 1 on
--     each side to catch newly-exposed neighbors.
--  2. Any old regions that contained the 6 face neighbors of the edited block
--     (an edit can split those too, e.g. a newly-opened interior face).
local function _handleBlockUpdate(chunkKey: number, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lod = chunkLOD[chunkKey] or 1

	-- If the chunk isn't currently rendered (too far / no entry), skip visual
	-- update. The buffer was still updated so GetBlockAt returns the new value.
	local parts = chunkParts[chunkKey]
	local regions = chunkRegions[chunkKey]
	if not parts or not regions then
		return
	end

	-- Compute the remesh bounding box.
	local minBoxLx, minBoxLy, minBoxLz = lx - 1, ly - 1, lz - 1
	local maxBoxLx, maxBoxLy, maxBoxLz = lx + 1, ly + 1, lz + 1

	local function expandByRegion(r: Region)
		if r.minLx < minBoxLx then
			minBoxLx = r.minLx
		end
		if r.minLy < minBoxLy then
			minBoxLy = r.minLy
		end
		if r.minLz < minBoxLz then
			minBoxLz = r.minLz
		end
		if r.maxLx > maxBoxLx then
			maxBoxLx = r.maxLx
		end
		if r.maxLy > maxBoxLy then
			maxBoxLy = r.maxLy
		end
		if r.maxLz > maxBoxLz then
			maxBoxLz = r.maxLz
		end
	end

	local oldRegion = regions[flatIndex]
	if oldRegion then
		expandByRegion(oldRegion)
	end
	for _, dir in NEIGHBOR_DIRS do
		local nx, ny, nz = lx + dir[1], ly + dir[2], lz + dir[3]
		if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE or nz < 0 or nz >= CHUNK_SIZE then
			continue
		end
		local nIdx = ChunkUtil.flatIndex(nx, ny, nz)
		local nRegion = regions[nIdx]
		if nRegion then
			expandByRegion(nRegion)
		end
	end

	-- Clamp to chunk.
	if minBoxLx < 0 then
		minBoxLx = 0
	end
	if minBoxLy < 0 then
		minBoxLy = 0
	end
	if minBoxLz < 0 then
		minBoxLz = 0
	end
	if maxBoxLx > CHUNK_SIZE - 1 then
		maxBoxLx = CHUNK_SIZE - 1
	end
	if maxBoxLy > CHUNK_SIZE - 1 then
		maxBoxLy = CHUNK_SIZE - 1
	end
	if maxBoxLz > CHUNK_SIZE - 1 then
		maxBoxLz = CHUNK_SIZE - 1
	end

	-- Collect unique groups touched by the box, and expand the box to cover
	-- each group's full region bounding box. This ensures every index we
	-- clear below is also remeshed — no dangling parts[idx] references.
	local groupsToRecycle: { { BasePart } } = {}
	local groupRegions: { Region } = {}
	local seenGroups: { [{ BasePart }]: boolean } = {}

	local function maybeCollect(idx: number)
		local group = parts[idx]
		if not group or seenGroups[group] then
			return
		end
		seenGroups[group] = true
		local r = regions[idx]
		if not r then
			return
		end
		table.insert(groupsToRecycle, group)
		table.insert(groupRegions, r)
		expandByRegion(r)
	end

	-- Iterate the initial box once to seed collection. As the box grows via
	-- expandByRegion during iteration, we'd miss entries added by expansion,
	-- so we loop-until-stable: after each pass, if no new groups were added,
	-- we are done. In practice the first pass picks up everything because all
	-- regions touching the box are contiguous.
	local prevMinLx, prevMinLy, prevMinLz = minBoxLx, minBoxLy, minBoxLz
	local prevMaxLx, prevMaxLy, prevMaxLz = maxBoxLx, maxBoxLy, maxBoxLz
	repeat
		for ly2 = minBoxLy, maxBoxLy do
			for lz2 = minBoxLz, maxBoxLz do
				for lx2 = minBoxLx, maxBoxLx do
					maybeCollect(ChunkUtil.flatIndex(lx2, ly2, lz2))
				end
			end
		end
		local stable = minBoxLx == prevMinLx
			and minBoxLy == prevMinLy
			and minBoxLz == prevMinLz
			and maxBoxLx == prevMaxLx
			and maxBoxLy == prevMaxLy
			and maxBoxLz == prevMaxLz
		prevMinLx, prevMinLy, prevMinLz = minBoxLx, minBoxLy, minBoxLz
		prevMaxLx, prevMaxLy, prevMaxLz = maxBoxLx, maxBoxLy, maxBoxLz
	until stable

	-- Clear each group's full region mapping.
	for _, r in groupRegions do
		for ly2 = r.minLy, r.maxLy do
			for lz2 = r.minLz, r.maxLz do
				for lx2 = r.minLx, r.maxLx do
					local idx = ChunkUtil.flatIndex(lx2, ly2, lz2)
					parts[idx] = nil
					regions[idx] = nil
				end
			end
		end
	end

	-- Return parts to pool.
	for _, group in groupsToRecycle do
		_returnGroup(group)
	end

	-- Remesh the expanded bounding box.
	local newRegions: { Region } =
		GreedyMesher.meshBox(blocks, minBoxLx, minBoxLy, minBoxLz, maxBoxLx, maxBoxLy, maxBoxLz, nil)
	for _, region in newRegions do
		local group = _makeRegionParts(blocks, region, cx, cy, cz, lod, false)
		_registerRegion(chunkKey, region, group, parts, regions)
	end
end

-- Public API

function ChunkRenderController:GetBlockAt(chunkKey: number, flatIndex: number): number
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return BlockType.Air
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end
	return buffer.readu8(blocks, flatIndex)
end

function ChunkRenderController:GetChunkBlocks(chunkKey: number): buffer?
	return chunkBlocks[chunkKey]
end

function ChunkRenderController:GetActivePartCount(): number
	return activePartsCount
end

function ChunkRenderController:GetPoolSize(): number
	return #partPool
end

-- Render queue processing

local function _processRenderQueue()
	if isProcessingQueue then
		return
	end
	isProcessingQueue = true

	while #renderQueue > 0 do
		local batch = renderQueue
		renderQueue = {}

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

		local seen: { [number]: boolean } = {}
		local keep: { [number]: boolean } = {}
		for i = #batch, 1, -1 do
			local key = batch[i].key
			if not seen[key] then
				seen[key] = true
				keep[i] = true
			end
		end

		for i = 1, #batch do
			if keep[i] then
				_renderChunk(batch[i].key, batch[i].blocks)
				task.wait()
			end
		end
	end

	isProcessingQueue = false
end

-- LOD re-evaluation

local function _reevaluateLODs()
	if not characterReady then
		return
	end
	local now = os.clock()
	if now - lastLODCheck < LOD_CHECK_INTERVAL then
		return
	end

	local pcx, pcy, pcz = _getPlayerChunkPos()
	if not pcx or not pcy or not pcz then
		return
	end
	if pcx == _lastLODPlayerCx and pcy == _lastLODPlayerCy and pcz == _lastLODPlayerCz then
		lastLODCheck = now
		return
	end
	_lastLODPlayerCx = pcx
	_lastLODPlayerCy = pcy
	_lastLODPlayerCz = pcz

	lastLODCheck = now

	local queued = false
	for chunkKey, currentLod in chunkLOD do
		local blocks = chunkBlocks[chunkKey]
		if not blocks then
			continue
		end
		local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
		local newLod = _getChunkLOD(cx, cy, cz)
		if newLod ~= currentLod then
			table.insert(renderQueue, { key = chunkKey, blocks = blocks })
			queued = true
		end
	end

	if queued and not isProcessingQueue then
		task.spawn(_processRenderQueue)
	end
end

-- Knit lifecycle

function ChunkRenderController:KnitInit()
	chunkContainer = Instance.new("Folder")
	chunkContainer.Name = "ChunkRender"
	chunkContainer.Parent = workspace

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

	local function _onCharacterReady()
		if characterReady then
			return
		end
		characterReady = true

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

	WorldService.ChunkData:Connect(function(chunkKey: number, compressedBuffer: buffer)
		local blocks = ChunkSerializer.decompress(compressedBuffer)

		if not characterReady then
			table.insert(pendingChunkData, { key = chunkKey, blocks = blocks })
			return
		end

		table.insert(renderQueue, { key = chunkKey, blocks = blocks })
		_processRenderQueue()
	end)

	WorldService.ChunkUnload:Connect(function(chunkKey: number)
		_unrenderChunk(chunkKey)
	end)

	WorldService.BlockUpdate:Connect(function(chunkKey: number, flatIndex: number, blockTypeId: number)
		_handleBlockUpdate(chunkKey, flatIndex, blockTypeId)
	end)

	RunService.Heartbeat:Connect(function(_dt: number)
		_processCleanupQueue()
		_trickleFillPool()
		_reevaluateLODs()
	end)
end

return ChunkRenderController
