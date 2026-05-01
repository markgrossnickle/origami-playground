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

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local CHUNK_STUDS = ChunkUtil.CHUNK_STUDS
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK

-- Pool
local POOL_MAX = 30000

-- Frame budget
local FRAME_BUDGET = 0.008
local YIELD_PART_INTERVAL = 32 -- yield check every N blocks iterated

-- Paper-crystal layer parameters (LOD 0 only)
local LAYERS_PER_BLOCK = 2
local LAYER_HEIGHT = BLOCK_SIZE / 2 * 0.9
local LAYER_GAP = BLOCK_SIZE / 2
local MAX_OFFSET = 0.15
local MAX_TILT = math.rad(8)
local LAYER_BRIGHTNESS = { 0.93, 1.07 }

-- Precomputed Vector3 sizes — reused across all non-WillowVine blocks so the
-- per-block hot loop avoids Vector3.new allocations.
local LAYER_SIZE_A = Vector3.new(BLOCK_SIZE * 1.08, LAYER_HEIGHT, BLOCK_SIZE * 0.92)
local LAYER_SIZE_B = Vector3.new(BLOCK_SIZE * 0.92, LAYER_HEIGHT, BLOCK_SIZE * 1.08)
local COLLISION_SIZE = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
local SIMPLE_SIZE_DEFAULT = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)

-- Simple block parameters (LOD 1)
local SIMPLE_MAX_OFFSET = 0.08
local SIMPLE_MAX_TILT = math.rad(3)
local SIMPLE_TINT_RANGE = 0.08

-- LOD: squared chunk distance threshold.
-- Tier 0 (≤ LOD_NEAR_DIST2)            → per-block paper-crystal layers + collision.
-- Tier 1 (> LOD_NEAR_DIST2, ≤ LOD_MID_DIST2) → per-block simple part w/ tilt + tint.
-- Tier 2 (> LOD_MID_DIST2, ≤ RENDER_MAX_DIST2) → greedy-merged solid slabs.
-- Tier -1 (> RENDER_MAX_DIST2)          → unrendered (data only).
--
-- LOD_NEAR_DIST2 widened from 1 → 4 (chunk-distance ≤ 2, ~33 chunks) so all
-- terrain within 160 studs of the player stays at the same LOD permanently.
-- The earlier value of 1 (only 7 chunks LOD 0) caused visible chunks to
-- transition LOD 0 → LOD 1 just outside the player's immediate cell — which
-- the player walked across constantly, triggering re-renders of chunks under
-- and immediately around them. Wider LOD 0 bubble keeps transitions
-- comfortably out of the player's near vision.
local LOD_NEAR_DIST2 = 4
local LOD_MID_DIST2 = 16
local RENDER_MAX_DIST2 = 25

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

-- CFrame-to-infinity for pooled parts. 2^24 (~16M studs) matches Pyseph's
-- ObjectCache convention — places pooled parts so far outside any gameplay
-- broadphase cell that they occupy a "dead" spatial-hash bucket no raycast
-- or physics query will ever enter. Verified via Roblox staff comments that
-- hidden/CanQuery=false parts still live in the broadphase tree; only raw
-- distance moves them to cells nothing scans.
local FAR_AWAY = CFrame.new(2 ^ 24, 2 ^ 24, 2 ^ 24)

-- BulkMoveTo batch size. Larger batches amortize the fixed per-call cost
-- (event fire, broadphase update) across more parts, so fewer flushes per
-- chunk build = less total CPU in WorldRoot.BulkMoveTo. 1024 covers most
-- chunk builds in 1-2 flushes instead of 4-6 at 256.
local BATCH_FLUSH_SIZE = 1024

-- Trickle fill
local TRICKLE_FILL_PER_FRAME = 4
local TRICKLE_FILL_TARGET = 500

-- Bulk-rendered block types. These get a single flat axis-aligned cube per
-- block with no rotation, tilt, position jitter, or paper-crystal layering,
-- regardless of LOD tier. Covers underground geology (stone/ore/gem/void
-- layers 1-7) and biome subsurface fillers — everything the player sees
-- once they've dug past the surface grass + paper layer.
--
-- Decorative blocks (anything NOT in this set) keep the full per-block
-- character treatment: paper-crystal layers at LOD 0, simple part at LOD 1.
-- Surface toppers (PaperGrass, FairyMoss, …), tree trunks, leaves/canopies,
-- mushrooms, accents, EggNode lights, bouncy blocks, and WillowVine taper
-- all live in the decorative path because their special-case handling
-- (bounce, light, taper) is wired into _makeLayerParts / _makeSimplePart.
local BULK_BLOCKS: { [number]: boolean } = {
	[BlockType.Bedrock] = true,

	-- Paper Fields bulk
	-- NOTE: Paper is intentionally NOT in BULK_BLOCKS — it's the visible
	-- subsurface block on the surface biome and players expect the paper-
	-- crystal layered look (multi-layer + tilt + jitter) when they dig the
	-- first layer. Adding it here makes the world feel flat. InkdropOre
	-- and Cardboard remain bulk-rendered (rare ore + legacy filler).
	[BlockType.Cardboard] = true,
	[BlockType.InkdropOre] = true,

	-- Pulp Caverns
	[BlockType.Pulp] = true,
	[BlockType.ClayBeadOre] = true,
	[BlockType.RecycledFiber] = true,
	[BlockType.PulpOre] = true,

	-- Fold Tunnels
	[BlockType.FoldedStone] = true,
	[BlockType.QuartzOre] = true,
	[BlockType.PaperCrystal] = true,
	[BlockType.InkStone] = true,

	-- Origami Depths
	[BlockType.OrigamiRock] = true,
	[BlockType.GemFragmentOre] = true,
	[BlockType.FoilOre] = true,
	[BlockType.RubyPaper] = true,

	-- Crystal Lattice
	[BlockType.Crystal] = true,
	[BlockType.FoilShardOre] = true,
	[BlockType.MetalOrigami] = true,
	[BlockType.SapphireCrystal] = true,

	-- Void Seams
	[BlockType.VoidStone] = true,
	[BlockType.DarkPaper] = true,
	[BlockType.ShadowWispOre] = true,
	[BlockType.VoidCrystal] = true,

	-- The Core
	[BlockType.PrismaticBlock] = true,
	[BlockType.PrismCoreOre] = true,
	[BlockType.RainbowPaper] = true,

	-- Biome subsurface fillers (bulk dirt/rock under the surface topper)
	[BlockType.EnchantedSoil] = true,
	[BlockType.FairyFiller] = true,
	[BlockType.GladeSoil] = true,
	[BlockType.HollowSoil] = true,
	[BlockType.ReefRock] = true,
	[BlockType.CoralFiller] = true,
	[BlockType.RoseQuartz] = true,
	[BlockType.RedClay] = true,
	[BlockType.MintFrost] = true,
	[BlockType.ConfettiFiller] = true,
	[BlockType.AgedPaper] = true,
	[BlockType.NewspaperGray] = true,
	[BlockType.NewspaperLayer] = true,
	[BlockType.AshStone] = true,
	[BlockType.ScorchedBase] = true,
	[BlockType.StellarDust] = true,
	[BlockType.NebulaFiller] = true,
	[BlockType.TerracottaClay] = true,
	[BlockType.MosaicSandstone] = true,
	[BlockType.CoralPaper] = true,
	[BlockType.SteamFiller] = true,
	[BlockType.InkSubsurface] = true,
	[BlockType.CrayonSubsurface] = true,
	[BlockType.LavenderSubsurface] = true,
	[BlockType.BoulderGray] = true,
	[BlockType.CorrugatedCardboard] = true,
	[BlockType.DarkCardboard] = true,
}

-- Leaf blocks that get random Y-rotation for organic look (not vines, not platform/shelf)
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

-- Small startup pool to reduce initial Instance.new calls. Kept small so the
-- join-time stall is brief; the trickle-fill pool (_trickleFillPool) grows the
-- pool up to TRICKLE_FILL_TARGET during idle frames post-join.
local POOL_STARTUP = 200
local POOL_STARTUP_BATCH = 50

-- LOD re-evaluation interval
local LOD_CHECK_INTERVAL = 2.0

local NEIGHBOR_DIRS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

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

-- LOD 0 layer tints are deterministic per (blockTypeId, layerIdx) since both
-- baseColor and LAYER_BRIGHTNESS are static. Cache lazily to avoid re-computing
-- and re-allocating Color3 on every block render.
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
	LOD renderer:
	  LOD 0 (near): 2 paper-crystal layers + invisible collision part
	  LOD 1 (far):  1 full-size block with tilt/tint (visual + collision)
]=]
local ChunkRenderController = Knit.CreateController({
	Name = "ChunkRenderController",
})

local partPool: { BasePart } = {}
local activePartsCount = 0

local renderedChunks: { [number]: boolean } = {}
-- chunkParts holds LOD 0/1 per-block parts keyed by flat block index.
local chunkParts: { [number]: { [number]: { BasePart } } } = {}
-- greedyParts holds LOD 2 merged-region parts as a flat list per chunk. A
-- chunk is rendered in exactly one of these tables depending on its LOD —
-- LOD transitions move ownership by clearing the old side and populating the
-- other.
local greedyParts: { [number]: { BasePart } } = {}
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

local function _setupBounce(part: BasePart, blockTypeId: number)
	if not BOUNCY_BLOCKS[blockTypeId] then
		return
	end

	part.CanTouch = true
	bouncyOrigColor[part] = part.Color

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

		-- Only bounce when falling
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y > -5 then
			return
		end

		-- Debounce per player
		local now = os.clock()
		if lastBounceTime[player] and now - lastBounceTime[player] < BOUNCE_DEBOUNCE then
			return
		end
		lastBounceTime[player] = now

		-- Spring bounce
		local bounceY = math.min(BOUNCE_VEL_MAX, math.max(BOUNCE_VEL_MIN, -vel.Y * BOUNCE_MULTIPLIER))
		rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, bounceY, vel.Z)

		-- Color flash on all visual parts in the group
		local flashColor = MUSHROOM_FLASH_COLORS[math.random(1, #MUSHROOM_FLASH_COLORS)]
		local origColor = bouncyOrigColor[part]
		part.Color = flashColor
		task.delay(FLASH_DURATION, function()
			if bouncyOrigColor[part] then
				part.Color = origColor
			end
		end)

		-- Bounce sound
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

local function _cleanupBounce(part: BasePart)
	local conn = bouncyConns[part]
	if conn then
		conn:Disconnect()
		bouncyConns[part] = nil
		-- CanTouch is only ever set to true by bouncy-block setup, so reset
		-- it here instead of in every cleanup-queue/pool-return path. Avoids
		-- a property write on every returned part when ~99% aren't bouncy.
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
-- Track player's last LOD-check position in WORLD STUDS (not chunk coords).
-- Chunk-coord equality breaks down at chunk boundaries: a stationary player
-- whose HRP rests at exactly Y=80 (or any 80-stud boundary) gets tiny
-- physics-induced floating-point oscillations that flip floor(y/80) between
-- two integers. The chunk-coord gate would then run a full LOD scan every
-- 2s for a stationary player, causing visible re-render flicker.
-- World-stud hysteresis: only re-eval LOD when the player has moved at
-- least HALF A CHUNK (40 studs) from their last LOD-check position.
local _lastLODPlayerWX: number? = nil
local _lastLODPlayerWY: number? = nil
local _lastLODPlayerWZ: number? = nil
local LOD_HYSTERESIS_STUDS = 40
local LOD_HYSTERESIS_STUDS_SQ = LOD_HYSTERESIS_STUDS * LOD_HYSTERESIS_STUDS

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
		return -1
	end
	if dist2 <= LOD_NEAR_DIST2 then
		return 0
	end
	if dist2 <= LOD_MID_DIST2 then
		return 1
	end
	return 2
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
	-- Checkout paths (_makeLayerParts, _makeSimplePart) always re-assign
	-- Size, CanCollide, CanQuery, Transparency, Color, Material, and CFrame,
	-- so we don't reset those here. CanTouch is reset inside _cleanupBounce
	-- only when the part was actually bouncy (rare).
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

-- Bulk-hide all parts in a chunk via BulkMoveTo (single native call)
local function _bulkHideChunkParts(chunkKey: number)
	local parts = chunkParts[chunkKey]
	if parts then
		for _, group in parts do
			for _, part in group do
				table.insert(_batchParts, part)
				table.insert(_batchCFrames, FAR_AWAY)
				if #_batchParts >= BATCH_FLUSH_SIZE then
					_flushBatch()
				end
			end
		end
	end
	local gparts = greedyParts[chunkKey]
	if gparts then
		for _, part in gparts do
			table.insert(_batchParts, part)
			table.insert(_batchCFrames, FAR_AWAY)
			if #_batchParts >= BATCH_FLUSH_SIZE then
				_flushBatch()
			end
		end
	end
	_flushBatch()
end

-- Queue a part for deferred cleanup (property reset + child destroy + pool return)
local function _queuePartForCleanup(part: BasePart)
	_cleanupBounce(part)
	activePartsCount -= 1
	table.insert(_cleanupQueue, part)
end

-- Process deferred cleanup queue with frame budgeting.
-- Note: checkout paths reassign Size/CanCollide/CanQuery/Color/Material/
-- Transparency/CFrame, so we skip resetting those here. CanTouch was already
-- handled inside _cleanupBounce at enqueue time. The only work left is
-- destroying attached children (PointLights on EggNodes) and returning to
-- pool or destroying if over cap.
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
		if processed % YIELD_PART_INTERVAL == 0 then
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

-- LOD 0: Paper-crystal layers + collision part

local function _makeLayerParts(
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

	-- 2 visual layers (no collision)
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

	-- Bouncy mushroom caps: setup on collision part, flash visual layers
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

			-- Flash visual layers
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

-- LOD 1: Single full-size block (visual + collision)

local function _makeSimplePart(
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
	-- LOD 1 (far) blocks are beyond mining reach (~113 studs vs 30-stud
	-- raycast). Disabling CanQuery hides them from Roblox's camera popper,
	-- which was the dominant client-frame cost (Popper → queryViewport →
	-- queryPoint → WorldRoot.Raycast) at high part counts.
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

	_setupBounce(part, blockTypeId)

	return { part }
end

-- Bulk block renderer: one axis-aligned cube per block. No jitter, no tilt,
-- no rotation, no paper-crystal layers. Used for underground geology +
-- subsurface biome filler (BULK_BLOCKS). Saves two parts per block vs
-- _makeLayerParts and skips the hash/CFrame.Angles math per block vs
-- _makeSimplePart. Active at both LOD 0 and LOD 1 since bulk blocks look
-- identical at any near-ish viewing distance.
local function _makeBulkPart(
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

	local part = _getPart()
	part.Color = _getColor(blockTypeId)
	part.Material = _getMaterial(blockTypeId)
	part.Size = SIMPLE_SIZE_DEFAULT
	part.CanCollide = true
	part.CanQuery = true
	part.Transparency = 0

	local targetCFrame = CFrame.new(px, py, pz)
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

-- LOD 2: one Part per greedy-merged region. No per-block character (tilt,
-- tint, paper layers) — this tier only renders at ~226+ studs where jitter is
-- imperceptible anyway. CanQuery=false because mining reach never touches
-- LOD 2 chunks, so hiding these from the camera popper is a free win.
local function _makeGreedyRegionPart(
	region: GreedyMesher.Region,
	cx: number,
	cy: number,
	cz: number,
	batched: boolean?
): BasePart
	local blockTypeId = region.blockTypeId
	local minLx, maxLx = region.minLx, region.maxLx
	local minLy, maxLy = region.minLy, region.maxLy
	local minLz, maxLz = region.minLz, region.maxLz

	local spanX = maxLx - minLx + 1
	local spanY = maxLy - minLy + 1
	local spanZ = maxLz - minLz + 1

	-- Region center in world space.
	local px = cx * CHUNK_STUDS + (minLx + spanX * 0.5) * BLOCK_SIZE
	local py = cy * CHUNK_STUDS + (minLy + spanY * 0.5) * BLOCK_SIZE
	local pz = cz * CHUNK_STUDS + (minLz + spanZ * 0.5) * BLOCK_SIZE

	local part = _getPart()
	part.Color = _getColor(blockTypeId)
	part.Material = _getMaterial(blockTypeId)
	part.Size = Vector3.new(spanX * BLOCK_SIZE, spanY * BLOCK_SIZE, spanZ * BLOCK_SIZE)
	part.CanCollide = true
	part.CanQuery = false
	part.Transparency = 0

	local targetCFrame = CFrame.new(px, py, pz)
	if batched then
		table.insert(_batchParts, part)
		table.insert(_batchCFrames, targetCFrame)
		if #_batchParts >= BATCH_FLUSH_SIZE then
			_flushBatch()
		end
	else
		part.CFrame = targetCFrame
	end

	return part
end

-- Block creation dispatcher
--
-- Matrix:
--                   | Decorative block       | Bulk block (BULK_BLOCKS)
--   LOD 0 (near)    | _makeLayerParts (3 pt) | _makeBulkPart (1 pt)
--   LOD 1 (mid)     | _makeSimplePart (1 pt) | _makeBulkPart (1 pt)
--   LOD 2 (far)     | Not called — _renderChunkGreedy emits merged regions.
--
-- Bulk blocks always render as a flat axis-aligned cube regardless of LOD
-- tier. At ~500 exposed blocks per chunk with underground being ~80% bulk,
-- this saves roughly 800 parts per LOD 0 chunk vs the old 3-part path —
-- pool pressure, property writes, and physics broadphase all drop
-- proportionally.
local function _makeBlockParts(
	blocks: buffer,
	blockTypeId: number,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number,
	lod: number,
	batched: boolean?
): { BasePart }
	if BULK_BLOCKS[blockTypeId] then
		return _makeBulkPart(blockTypeId, cx, cy, cz, lx, ly, lz, batched)
	end
	if lod == 0 then
		return _makeLayerParts(blocks, blockTypeId, cx, cy, cz, lx, ly, lz, batched)
	else
		return _makeSimplePart(blocks, blockTypeId, cx, cy, cz, lx, ly, lz, batched)
	end
end

-- Visibility checks

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

-- Chunk rendering

-- Recycle all currently-rendered parts for this chunk (both per-block and
-- greedy). Called at the start of every _renderChunk so a LOD transition
-- cleans up the previous tier's geometry before building the new one.
local function _recycleChunkParts(chunkKey: number)
	_bulkHideChunkParts(chunkKey)

	local existing = chunkParts[chunkKey]
	if existing then
		for _, group in existing do
			for _, part in group do
				_queuePartForCleanup(part)
			end
		end
		chunkParts[chunkKey] = nil
	end

	local gparts = greedyParts[chunkKey]
	if gparts then
		for _, part in gparts do
			_queuePartForCleanup(part)
		end
		greedyParts[chunkKey] = nil
	end
end

-- LOD 0/1 per-block render. Iterates the chunk, emits parts for every
-- exposed non-air block, keyed by flat index so _handleBlockUpdate can do
-- surgical single-block updates.
local function _renderChunkPerBlock(chunkKey: number, blocks: buffer, cx: number, cy: number, cz: number, lod: number)
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
					local group = _makeBlockParts(blocks, blockTypeId, cx, cy, cz, lx, ly, lz, lod, true)
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
end

-- LOD 2 greedy render. One Part per merged region from GreedyMesher. Stored
-- as a flat list — no per-block indexing because multiple blocks collapse
-- into one part.
local function _renderChunkGreedy(chunkKey: number, blocks: buffer, cx: number, cy: number, cz: number)
	local regions = GreedyMesher.meshChunk(blocks)

	local parts: { BasePart } = table.create(#regions)
	greedyParts[chunkKey] = parts

	local renderStart = os.clock()
	for i, region in regions do
		parts[i] = _makeGreedyRegionPart(region, cx, cy, cz, true)
		if i % YIELD_PART_INTERVAL == 0 then
			if os.clock() - renderStart > FRAME_BUDGET then
				_flushBatch()
				task.wait()
				renderStart = os.clock()
			end
		end
	end

	_flushBatch()
end

local function _renderChunk(chunkKey: number, blocks: buffer)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lod = _getChunkLOD(cx, cy, cz)

	-- Store block data even for unrendered chunks (needed for mining/block updates)
	chunkBlocks[chunkKey] = blocks

	if lod == -1 then
		-- Too far to render — clean up any existing parts from a previous LOD
		-- tier but keep the data around for mining / block updates.
		_recycleChunkParts(chunkKey)
		renderedChunks[chunkKey] = false
		chunkLOD[chunkKey] = lod
		return
	end

	-- Standing-on-chunk protection: if this is a re-render of a chunk the
	-- player is currently standing on, skip it. _recycleChunkParts BulkMoveTos
	-- the existing parts to FAR_AWAY *before* the new ones are placed, leaving
	-- a window with no collision under the player. They fall through and get
	-- stuck below the world. The chunk's old LOD is visually slightly off but
	-- collision is preserved; the next render after the player moves off the
	-- chunk will pick up the correct LOD.
	if renderedChunks[chunkKey] then
		local pcx, pcy, pcz = _getPlayerChunkPos()
		if pcx == cx and pcy == cy and pcz == cz then
			-- Stash latest blocks so a future render on this chunk uses them,
			-- but don't disturb the parts the player is standing on.
			return
		end
	end

	_recycleChunkParts(chunkKey)

	renderedChunks[chunkKey] = true
	chunkLOD[chunkKey] = lod

	if lod == 2 then
		_renderChunkGreedy(chunkKey, blocks, cx, cy, cz)
	else
		_renderChunkPerBlock(chunkKey, blocks, cx, cy, cz, lod)
	end
end

local function _unrenderChunk(chunkKey: number)
	renderedChunks[chunkKey] = nil
	chunkLOD[chunkKey] = nil

	_recycleChunkParts(chunkKey)

	chunkBlocks[chunkKey] = nil
end

-- Block update.
-- LOD 0/1: surgical — only re-render the changed block and its 6 neighbors
-- (their exposure may have flipped). Leaves the rest of the chunk untouched.
-- LOD 2:   full greedy re-mesh of the chunk. The mined block may split a
-- merged region into multiple smaller ones, so partial updates aren't
-- correct. In practice LOD 2 chunks are ≥ ~140 studs away so the rebuild is
-- invisible to the player, and the cost is bounded by chunk size (~0.5 ms).
local function _handleBlockUpdate(chunkKey: number, flatIndex: number, blockTypeId: number)
	local blocks = chunkBlocks[chunkKey]
	if not blocks then
		return
	end

	buffer.writeu8(blocks, flatIndex, blockTypeId)

	local lod = chunkLOD[chunkKey] or 1

	if lod == -1 then
		-- Chunk isn't rendered; block data is up to date, nothing else to do.
		return
	end

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)

	if lod == 2 then
		-- Full greedy re-mesh. Recycle old greedy parts, rebuild from scratch.
		local oldParts = greedyParts[chunkKey]
		if oldParts then
			for _, part in oldParts do
				table.insert(_batchParts, part)
				table.insert(_batchCFrames, FAR_AWAY)
				if #_batchParts >= BATCH_FLUSH_SIZE then
					_flushBatch()
				end
				_queuePartForCleanup(part)
			end
			_flushBatch()
			greedyParts[chunkKey] = nil
		end
		_renderChunkGreedy(chunkKey, blocks, cx, cy, cz)
		return
	end

	-- LOD 0/1: per-block surgical update.
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
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
		parts[flatIndex] = _makeBlockParts(blocks, blockTypeId, cx, cy, cz, lx, ly, lz, lod, false)
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
			parts[nIdx] = _makeBlockParts(blocks, nBlockType, cx, cy, cz, nx, ny, nz, lod, false)
		elseif not shouldRender and hasGroup then
			_returnGroup(parts[nIdx])
			parts[nIdx] = nil
		end
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

		-- Deduplicate in-place: walk backwards marking last occurrence, then
		-- forward-pass emitting only kept entries. O(n) instead of O(n²) from
		-- the previous table.insert(deduped, 1, ...) pattern.
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

	-- Hysteresis gate: only re-eval if the player has moved at least
	-- LOD_HYSTERESIS_STUDS from their last checked position. Prevents the
	-- chunk-boundary oscillation flicker where a stationary player's HRP
	-- bounces a few hundredths of a stud across an 80-stud boundary every
	-- frame (visible as a 2s-cadence re-render churn).
	local player = Players.LocalPlayer
	if not player or not player.Character then
		return
	end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local pos = hrp.Position
	if _lastLODPlayerWX and _lastLODPlayerWY and _lastLODPlayerWZ then
		local dx = pos.X - _lastLODPlayerWX
		local dy = pos.Y - _lastLODPlayerWY
		local dz = pos.Z - _lastLODPlayerWZ
		if dx * dx + dy * dy + dz * dz < LOD_HYSTERESIS_STUDS_SQ then
			lastLODCheck = now
			return
		end
	end
	_lastLODPlayerWX = pos.X
	_lastLODPlayerWY = pos.Y
	_lastLODPlayerWZ = pos.Z

	lastLODCheck = now

	-- Check all rendered chunks for LOD changes (player moved)
	-- Only queue — don't process synchronously (avoids blocking Heartbeat)
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

	-- WorldService.BlockUpdate fires a flat array at 10Hz, batching all block
	-- changes the player observed during that 100ms window. Each entry is
	-- 3 consecutive numbers: chunkKey, flatIndex, blockTypeId. Replaces the
	-- old 1-event-per-block pattern that storm-replicated mining bursts.
	WorldService.BlockUpdate:Connect(function(batch: { number })
		for i = 1, #batch, 3 do
			_handleBlockUpdate(batch[i], batch[i + 1], batch[i + 2])
		end
	end)

	-- Heartbeat: cleanup queue, trickle-fill pool, periodic LOD re-evaluation
	RunService.Heartbeat:Connect(function(_dt: number)
		_processCleanupQueue()
		_trickleFillPool()
		_reevaluateLODs()
	end)
end

return ChunkRenderController
