--!strict

local ChunkUtil = require(script.Parent.ChunkUtil)
local BlockType = require(script.Parent.Enums.BlockType)
local BiomeConfig = require(script.Parent.BiomeConfig)

local CHUNK_SIZE = ChunkUtil.CHUNK_SIZE
local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local CHUNK_STUDS = ChunkUtil.CHUNK_STUDS

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

local Config = {
	-- World size
	worldRadiusChunks = 16, -- radius in chunks from center (32x32 total)
	-- Terrain
	seaLevelBlock = 4, -- surface baseline in blocks above world Y=0
	maxElevationBlocks = 15, -- max surface height variation in blocks
	maxDepthBlocks = 400, -- how deep underground goes (in blocks, 2000 studs / 5)
	-- Island shape
	islandFalloffStart = 0.55,
	islandFalloffEnd = 0.85,
	-- Noise — terrain (flat mesas with steep cliffs)
	terrainFrequency = 0.004,
	terrainOctaves = 2,
	terrainLacunarity = 2.0,
	terrainPersistence = 0.25,
	-- Terrain smoothing
	terrainSmoothingRadius = 1,
	maxSlopeBlocks = 1,
	-- Heightmap plateau enforcement
	seaLevelFlattenRange = 3,
	seaLevelFlattenStrength = 0.4,
	plateauBandSize = 1,
	minPlateauCells = 4,
	globalSlopePasses = 2,
	-- Cave generation
	caveFrequency = 0.02,
	caveThreshold = 0.65, -- noise > this = cave (fewer caves for mesa)
	caveMinDepth = 40, -- don't carve caves within 40 studs of surface
	-- Trees
	treeDensityMultiplier = 0.3,
	treeCheckRadius = 4,
	minLargeTreeSpacingBlocks = 8,
	largeTreeCanopyThreshold = 2,
	-- Ore
	oreFrequencyMultiplier = 1.0,
}

local WorldGenModule = {}

------------------------------------------------------------
-- Global Heightmap (pre-computed 512x512 buffer)
------------------------------------------------------------
local WORLD_SIZE_BLOCKS = Config.worldRadiusChunks * 2 * CHUNK_SIZE -- 512
local HEIGHTMAP_ORIGIN = -Config.worldRadiusChunks * CHUNK_SIZE -- -256
local HEIGHTMAP_OFFSET = 128

local globalHeightmap: buffer? = nil
local heightmapSeed: number? = nil

------------------------------------------------------------
-- Hash & RNG (deterministic)
------------------------------------------------------------

local function hashSeed(seed: number, a: number, b: number, c: number): number
	local h = seed
	h = bit32.bxor(h, bit32.lshift(a * 374761393, 5))
	h = bit32.bxor(h, bit32.lshift(b * 668265263, 7))
	h = bit32.bxor(h, bit32.lshift(c * 2147483647, 11))
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = h * 1274126177
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

local function hashTwo(seed: number, x: number, z: number): number
	local h = bit32.bxor(seed, x * 374761393)
	h = bit32.bxor(h, z * 668265263)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = h * 1274126177
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

local function createRNG(seed: number)
	local state = if seed == 0 then 1 else math.abs(seed)
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return (state % 1000000) / 1000000
	end
end

------------------------------------------------------------
-- 2D Value Noise
------------------------------------------------------------

local function noiseCorner(seed: number, ix: number, iz: number): number
	local h = hashTwo(seed, ix, iz)
	return (h % 10000) / 10000
end

local function noise2D(seed: number, x: number, z: number, scale: number): number
	local sx = x / scale
	local sz = z / scale
	local ix = math.floor(sx)
	local iz = math.floor(sz)
	local fx = sx - ix
	local fz = sz - iz

	fx = fx * fx * (3 - 2 * fx)
	fz = fz * fz * (3 - 2 * fz)

	local v00 = noiseCorner(seed, ix, iz)
	local v10 = noiseCorner(seed, ix + 1, iz)
	local v01 = noiseCorner(seed, ix, iz + 1)
	local v11 = noiseCorner(seed, ix + 1, iz + 1)

	local top = v00 + (v10 - v00) * fx
	local bottom = v01 + (v11 - v01) * fx
	return top + (bottom - top) * fz
end

-- 3D noise for caves
local function noise3D(seed: number, x: number, y: number, z: number, scale: number): number
	-- Use 2D noise slices combined for cheap 3D approximation
	local n1 = noise2D(seed, x, z, scale)
	local n2 = noise2D(seed + 100, x, y, scale)
	local n3 = noise2D(seed + 200, y, z, scale)
	return (n1 + n2 + n3) / 3
end

local function fbmNoise(seed: number, x: number, z: number, baseScale: number, octaves: number, persistence: number?, lacunarity: number?): number
	local value = 0
	local amplitude = 1
	local frequency = 1
	local maxAmplitude = 0
	local pers = persistence or Config.terrainPersistence
	local lac = lacunarity or Config.terrainLacunarity

	for i = 0, octaves - 1 do
		value += noise2D(seed + i * 31, x, z, baseScale / frequency) * amplitude
		maxAmplitude += amplitude
		amplitude *= pers
		frequency *= lac
	end

	return value / maxAmplitude
end

------------------------------------------------------------
-- Island Mask
------------------------------------------------------------

local function getIslandMask(wx: number, wz: number): number
	local worldRadius = Config.worldRadiusChunks * CHUNK_STUDS
	local dist = math.sqrt(wx * wx + wz * wz)
	local normalizedDist = dist / worldRadius

	if normalizedDist <= Config.islandFalloffStart then
		return 1
	elseif normalizedDist >= Config.islandFalloffEnd then
		return 0
	else
		local t = (normalizedDist - Config.islandFalloffStart) / (Config.islandFalloffEnd - Config.islandFalloffStart)
		t = t * t * (3 - 2 * t)
		return 1 - t
	end
end

------------------------------------------------------------
-- Surface Height
------------------------------------------------------------

local function getSurfaceHeightRaw(seed: number, wx: number, wz: number, biome: any?): number
	local islandMask = getIslandMask(wx, wz)
	if islandMask <= 0 then
		return Config.seaLevelBlock - 3
	end

	local freq = if biome then (biome.terrainFrequency or Config.terrainFrequency) else Config.terrainFrequency
	local octaves = if biome then (biome.terrainOctaves or Config.terrainOctaves) else Config.terrainOctaves
	local maxElev = if biome then (biome.maxElevationBlocks or Config.maxElevationBlocks) else Config.maxElevationBlocks
	local persistence = Config.terrainPersistence
	local lacunarity = Config.terrainLacunarity

	local rawHeight = fbmNoise(seed, wx, wz, 1 / freq, octaves, persistence, lacunarity)
	local surfaceBlock = Config.seaLevelBlock + math.floor(rawHeight * maxElev * islandMask)
	return surfaceBlock
end

------------------------------------------------------------
-- Heightmap Initialization (5-pass pipeline)
------------------------------------------------------------

local function _initializeGlobalHeightmap(seed: number)
	local size = WORLD_SIZE_BLOCKS
	local total = size * size
	local hm = buffer.create(total)
	local seaLevel = Config.seaLevelBlock

	-- Pass 1a: Raw noise heights (biome-aware)
	local rawHm = buffer.create(total)
	for bz = 0, size - 1 do
		for bx = 0, size - 1 do
			local wx = (HEIGHTMAP_ORIGIN + bx) * BLOCK_SIZE
			local wz = (HEIGHTMAP_ORIGIN + bz) * BLOCK_SIZE
			local biome = BiomeConfig.getBiome(wx, wz)
			local h = getSurfaceHeightRaw(seed, wx, wz, biome)
			buffer.writeu8(rawHm, bz * size + bx, math.clamp(h + HEIGHTMAP_OFFSET, 0, 255))
		end
		if bz % 8 == 0 then
			task.wait()
		end
	end

	-- Pass 1b: Smooth
	local radius = Config.terrainSmoothingRadius
	if radius <= 0 then
		buffer.copy(hm, 0, rawHm, 0, total)
	else
		local kernelSize = (2 * radius + 1) * (2 * radius + 1)
		for bz = 0, size - 1 do
			for bx = 0, size - 1 do
				local sum = 0
				for dz = -radius, radius do
					local sz = math.clamp(bz + dz, 0, size - 1)
					local rowOff = sz * size
					for dx = -radius, radius do
						local sx = math.clamp(bx + dx, 0, size - 1)
						sum += buffer.readu8(rawHm, rowOff + sx) - HEIGHTMAP_OFFSET
					end
				end
				local h = math.floor(sum / kernelSize + 0.5)
				buffer.writeu8(hm, bz * size + bx, math.clamp(h + HEIGHTMAP_OFFSET, 0, 255))
			end
		end
	end

	-- Pass 2: Sea-level flattening
	local flattenRange = Config.seaLevelFlattenRange
	local flattenStrength = Config.seaLevelFlattenStrength
	for i = 0, total - 1 do
		local h = buffer.readu8(hm, i) - HEIGHTMAP_OFFSET
		if h >= seaLevel and h <= seaLevel + flattenRange then
			h = seaLevel + math.floor((h - seaLevel) * (1 - flattenStrength) + 0.5)
			buffer.writeu8(hm, i, math.clamp(h + HEIGHTMAP_OFFSET, 0, 255))
		end
	end
	task.wait()

	-- Pass 3: Height quantization
	local bandSize = Config.plateauBandSize
	for i = 0, total - 1 do
		local h = buffer.readu8(hm, i) - HEIGHTMAP_OFFSET
		if h >= seaLevel then
			h = seaLevel + math.floor((h - seaLevel) / bandSize + 0.5) * bandSize
			buffer.writeu8(hm, i, math.clamp(h + HEIGHTMAP_OFFSET, 0, 255))
		end
	end
	task.wait()

	-- Pass 4: Plateau enforcement (connected components + merge small regions)
	local minCells = Config.minPlateauCells
	for _ = 1, 3 do
		local parent = table.create(total, 0)
		local ufRank = table.create(total, 0)
		for i = 1, total do
			parent[i] = i
		end

		local function find(x: number): number
			while parent[x] ~= x do
				parent[x] = parent[parent[x]]
				x = parent[x]
			end
			return x
		end

		local function ufUnion(a: number, b: number)
			a = find(a)
			b = find(b)
			if a == b then
				return
			end
			if ufRank[a] < ufRank[b] then
				a, b = b, a
			end
			parent[b] = a
			if ufRank[a] == ufRank[b] then
				ufRank[a] += 1
			end
		end

		for bz2 = 0, size - 1 do
			for bx2 = 0, size - 1 do
				local bufIdx = bz2 * size + bx2
				local h = buffer.readu8(hm, bufIdx) - HEIGHTMAP_OFFSET
				if h < seaLevel then
					continue
				end
				if bx2 < size - 1 then
					local nh = buffer.readu8(hm, bufIdx + 1) - HEIGHTMAP_OFFSET
					if nh >= seaLevel and nh == h then
						ufUnion(bufIdx + 1, bufIdx + 2)
					end
				end
				if bz2 < size - 1 then
					local nh = buffer.readu8(hm, bufIdx + size) - HEIGHTMAP_OFFSET
					if nh >= seaLevel and nh == h then
						ufUnion(bufIdx + 1, bufIdx + size + 1)
					end
				end
			end
		end

		local compSize: { [number]: number } = {}
		local compHeight: { [number]: number } = {}
		for i = 0, total - 1 do
			local h = buffer.readu8(hm, i) - HEIGHTMAP_OFFSET
			if h < seaLevel then
				continue
			end
			local root = find(i + 1)
			compSize[root] = (compSize[root] or 0) + 1
			compHeight[root] = h
		end

		local hasSmall = false
		for _, count in compSize do
			if count < minCells then
				hasSmall = true
				break
			end
		end
		if not hasSmall then
			break
		end

		local smallRoots: { [number]: boolean } = {}
		for root, count in compSize do
			if count < minCells then
				smallRoots[root] = true
			end
		end

		local mergeTarget: { [number]: number } = {}
		local bestNeighborSize: { [number]: number } = {}
		for bz2 = 0, size - 1 do
			for bx2 = 0, size - 1 do
				local bufIdx = bz2 * size + bx2
				local h = buffer.readu8(hm, bufIdx) - HEIGHTMAP_OFFSET
				if h < seaLevel then
					continue
				end
				local root = find(bufIdx + 1)
				if not smallRoots[root] then
					continue
				end
				if bx2 > 0 then
					local nh = buffer.readu8(hm, bufIdx - 1) - HEIGHTMAP_OFFSET
					if nh >= seaLevel then
						local nRoot = find(bufIdx)
						if nRoot ~= root and (compSize[nRoot] or 0) > (bestNeighborSize[root] or 0) then
							mergeTarget[root] = nRoot
							bestNeighborSize[root] = compSize[nRoot] or 0
						end
					end
				end
				if bx2 < size - 1 then
					local nh = buffer.readu8(hm, bufIdx + 1) - HEIGHTMAP_OFFSET
					if nh >= seaLevel then
						local nRoot = find(bufIdx + 2)
						if nRoot ~= root and (compSize[nRoot] or 0) > (bestNeighborSize[root] or 0) then
							mergeTarget[root] = nRoot
							bestNeighborSize[root] = compSize[nRoot] or 0
						end
					end
				end
				if bz2 > 0 then
					local nh = buffer.readu8(hm, bufIdx - size) - HEIGHTMAP_OFFSET
					if nh >= seaLevel then
						local nRoot = find(bufIdx - size + 1)
						if nRoot ~= root and (compSize[nRoot] or 0) > (bestNeighborSize[root] or 0) then
							mergeTarget[root] = nRoot
							bestNeighborSize[root] = compSize[nRoot] or 0
						end
					end
				end
				if bz2 < size - 1 then
					local nh = buffer.readu8(hm, bufIdx + size) - HEIGHTMAP_OFFSET
					if nh >= seaLevel then
						local nRoot = find(bufIdx + size + 1)
						if nRoot ~= root and (compSize[nRoot] or 0) > (bestNeighborSize[root] or 0) then
							mergeTarget[root] = nRoot
							bestNeighborSize[root] = compSize[nRoot] or 0
						end
					end
				end
			end
		end

		for i = 0, total - 1 do
			local h = buffer.readu8(hm, i) - HEIGHTMAP_OFFSET
			if h < seaLevel then
				continue
			end
			local root = find(i + 1)
			if smallRoots[root] and mergeTarget[root] then
				local targetH = compHeight[mergeTarget[root]]
				if targetH then
					buffer.writeu8(hm, i, math.clamp(targetH + HEIGHTMAP_OFFSET, 0, 255))
				end
			end
		end
		task.wait()
	end

	-- Pass 5: Global slope clamping
	local maxSlope = Config.maxSlopeBlocks
	for _ = 1, Config.globalSlopePasses do
		for bz2 = 0, size - 1 do
			for bx2 = 0, size - 1 do
				local idx = bz2 * size + bx2
				local h = buffer.readu8(hm, idx) - HEIGHTMAP_OFFSET
				if bx2 > 0 then
					local nh = buffer.readu8(hm, idx - 1) - HEIGHTMAP_OFFSET
					if h - nh > maxSlope then
						h = nh + maxSlope
					elseif nh - h > maxSlope then
						h = nh - maxSlope
					end
				end
				if bx2 < size - 1 then
					local nh = buffer.readu8(hm, idx + 1) - HEIGHTMAP_OFFSET
					if h - nh > maxSlope then
						h = nh + maxSlope
					elseif nh - h > maxSlope then
						h = nh - maxSlope
					end
				end
				if bz2 > 0 then
					local nh = buffer.readu8(hm, idx - size) - HEIGHTMAP_OFFSET
					if h - nh > maxSlope then
						h = nh + maxSlope
					elseif nh - h > maxSlope then
						h = nh - maxSlope
					end
				end
				if bz2 < size - 1 then
					local nh = buffer.readu8(hm, idx + size) - HEIGHTMAP_OFFSET
					if h - nh > maxSlope then
						h = nh + maxSlope
					elseif nh - h > maxSlope then
						h = nh - maxSlope
					end
				end
				buffer.writeu8(hm, idx, math.clamp(h + HEIGHTMAP_OFFSET, 0, 255))
			end
		end
		task.wait()
	end

	globalHeightmap = hm
	heightmapSeed = seed
end

local heightmapInitializing = false

local function _ensureHeightmap(seed: number)
	if globalHeightmap and heightmapSeed == seed then
		return
	end
	-- Guard: only one initialization at a time, others wait
	if heightmapInitializing then
		while heightmapInitializing do
			task.wait()
		end
		return
	end
	heightmapInitializing = true
	_initializeGlobalHeightmap(seed)
	heightmapInitializing = false
end

local function getSurfaceHeight(seed: number, wx: number, wz: number): number
	_ensureHeightmap(seed)
	local bx = math.clamp(math.floor(wx / BLOCK_SIZE) - HEIGHTMAP_ORIGIN, 0, WORLD_SIZE_BLOCKS - 1)
	local bz = math.clamp(math.floor(wz / BLOCK_SIZE) - HEIGHTMAP_ORIGIN, 0, WORLD_SIZE_BLOCKS - 1)
	return buffer.readu8(globalHeightmap :: buffer, bz * WORLD_SIZE_BLOCKS + bx) - HEIGHTMAP_OFFSET
end

------------------------------------------------------------
-- Ore Vein Placement (random walk)
------------------------------------------------------------

local solidBlocks: { [number]: boolean } = {
	[BlockType.Paper] = true,
	[BlockType.Cardboard] = true,
	[BlockType.DriedPulp] = true,
	[BlockType.CompressedPulp] = true,
	[BlockType.Clay] = true,
	[BlockType.RecycledFiber] = true,
	[BlockType.FoldedStone] = true,
	[BlockType.InkStone] = true,
	[BlockType.OrigamiRock] = true,
	[BlockType.GemFragment] = true,
	[BlockType.CrystalBlock] = true,
	[BlockType.FoilSheet] = true,
	[BlockType.VoidStone] = true,
	[BlockType.DarkPaper] = true,
	[BlockType.PrismaticBlock] = true,
	[BlockType.CoreFragment] = true,
}

local function placeOreVeins(blocks: buffer, rng: () -> number, oreConfig: BiomeConfig.OreConfig, oreMult: number)
	local veins = math.floor(oreConfig.veinsPerChunk * oreMult * Config.oreFrequencyMultiplier + 0.5)
	for _ = 1, veins do
		if rng() > oreConfig.chance * 10 then
			continue
		end

		local startX = math.floor(rng() * CHUNK_SIZE)
		local startY = math.floor(rng() * CHUNK_SIZE)
		local startZ = math.floor(rng() * CHUNK_SIZE)

		local veinLen = oreConfig.veinSize.min
			+ math.floor(rng() * (oreConfig.veinSize.max - oreConfig.veinSize.min + 1))

		local ox, oy, oz = startX, startY, startZ
		for _ = 1, veinLen do
			if ox >= 0 and ox < CHUNK_SIZE and oy >= 0 and oy < CHUNK_SIZE and oz >= 0 and oz < CHUNK_SIZE then
				local idx = ChunkUtil.flatIndex(ox, oy, oz)
				local existingBlock = buffer.readu8(blocks, idx)
				if solidBlocks[existingBlock] then
					buffer.writeu8(blocks, idx, oreConfig.blockType)
				end
			end

			local dir = math.floor(rng() * 6)
			if dir == 0 then
				ox += 1
			elseif dir == 1 then
				ox -= 1
			elseif dir == 2 then
				oy += 1
			elseif dir == 3 then
				oy -= 1
			elseif dir == 4 then
				oz += 1
			else
				oz -= 1
			end
		end
	end
end

------------------------------------------------------------
-- Tree Placement (deterministic, cross-chunk safe)
------------------------------------------------------------

local function isTreeDensityPass(seed: number, bx: number, bz: number, density: number): boolean
	if density <= 0 then
		return false
	end
	local h = hashTwo(seed + 7777, bx, bz)
	return (h % 10000) / 10000 < density
end

local function isTreeRoot(seed: number, bx: number, bz: number): boolean
	local wx = bx * BLOCK_SIZE
	local wz = bz * BLOCK_SIZE
	local surface = BiomeConfig.getBiome(wx, wz)
	local density = surface.treeDensity * (surface.treeDensityMultiplier or Config.treeDensityMultiplier)
	if not isTreeDensityPass(seed, bx, bz, density) then
		return false
	end

	if surface.canopyRadius < Config.largeTreeCanopyThreshold then
		return true
	end

	local spacing = Config.minLargeTreeSpacingBlocks
	local cellX = math.floor(bx / spacing)
	local cellZ = math.floor(bz / spacing)
	local myHash = hashTwo(seed + 7777, bx, bz)

	local cellStartX = cellX * spacing
	local cellStartZ = cellZ * spacing
	for sx = cellStartX, cellStartX + spacing - 1 do
		for sz = cellStartZ, cellStartZ + spacing - 1 do
			if sx == bx and sz == bz then
				continue
			end
			if not isTreeDensityPass(seed, sx, sz, density) then
				continue
			end
			local neighborHash = hashTwo(seed + 7777, sx, sz)
			if neighborHash < myHash then
				return false
			end
			if neighborHash == myHash and (sx < bx or (sx == bx and sz < bz)) then
				return false
			end
		end
	end

	return true
end

local function getTreeHeight(seed: number, bx: number, bz: number): number
	local wx = bx * BLOCK_SIZE
	local wz = bz * BLOCK_SIZE
	local surface = BiomeConfig.getBiome(wx, wz)
	local h = hashTwo(seed + 8888, bx, bz)
	local range = surface.trunkHeightMax - surface.trunkHeightMin + 1
	return surface.trunkHeightMin + (h % range)
end

-- All available structure types for "mixed" mode
local MIXED_STRUCTURES = { "tree", "tree_giant", "tree_pine", "tree_willow", "tree_palm", "cactus", "bonsai" }

-- Per-structure block overrides (used in mixed mode for visual variety)
local STRUCTURE_BLOCKS = {
	cactus = { trunk = BlockType.CactusGreen, canopy = BlockType.CactusFlower },
	bonsai = { trunk = BlockType.BonsaiBark, canopy = BlockType.CherryBlossom },
	tree_giant = { trunk = BlockType.GiantBark, canopy = BlockType.Leaves },
	tree_pine = { trunk = BlockType.Wood, canopy = BlockType.PineNeedle },
	tree_willow = { trunk = BlockType.Wood, canopy = BlockType.WillowVine },
	tree_palm = { trunk = BlockType.Wood, canopy = BlockType.PalmFrond },
	mushroom = { trunk = BlockType.MushroomStem, canopy = BlockType.MushroomCap },
	mushroom_cluster = { trunk = BlockType.MushroomStem, canopy = BlockType.MushroomCap },
	mushroom_tall = { trunk = BlockType.MushroomStem, canopy = BlockType.MushroomCap },
	mushroom_shelf = { trunk = BlockType.MushroomStem, canopy = BlockType.ShelfBracket },
}

-- Structure label names for display
local STRUCTURE_LABELS = {
	tree = "Tree", tree_giant = "Giant Tree", tree_pine = "Pine", tree_willow = "Willow",
	tree_palm = "Palm", cactus = "Cactus",
	bonsai = "Bonsai", mushroom = "Mushroom",
	mushroom_cluster = "Mushroom Cluster", mushroom_tall = "Tall Mushroom",
	mushroom_shelf = "Shelf Mushroom", spire = "Spire", cluster = "Cluster",
	column = "Column",
}

-- Block type → structure name mapping (for mining feedback)
local BLOCK_STRUCTURE_NAME: { [number]: string } = {}
for structName, overrides in STRUCTURE_BLOCKS do
	local label = STRUCTURE_LABELS[structName]
	if label and overrides.trunk then
		BLOCK_STRUCTURE_NAME[overrides.trunk] = label
	end
	if label and overrides.canopy then
		BLOCK_STRUCTURE_NAME[overrides.canopy] = label
	end
end

-- Helper: place a single block if within chunk bounds and target is air
local function placeBlock(blocks: buffer, blockType: number, bx: number, worldBlockY: number, bz: number, chunkBlockX: number, chunkBlockYBottom: number, chunkBlockYTop: number, chunkBlockZ: number, requireAir: boolean?)
	if worldBlockY < chunkBlockYBottom or worldBlockY > chunkBlockYTop then
		return
	end
	local lx = bx - chunkBlockX
	local ly = worldBlockY - chunkBlockYBottom
	local lz = bz - chunkBlockZ
	if lx < 0 or lx >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE then
		return
	end
	local idx = ChunkUtil.flatIndex(lx, ly, lz)
	if requireAir and buffer.readu8(blocks, idx) ~= BlockType.Air then
		return
	end
	buffer.writeu8(blocks, idx, blockType)
end

-- Trunk position helper (no sway — straight trunks on grid)
local function getTrunkPos(_seed: number, bx: number, bz: number, _ty: number): (number, number)
	return bx, bz
end

local function placeTreesInChunk(blocks: buffer, seed: number, cx: number, cy: number, cz: number)
	local chunkBlockYBottom = cy * CHUNK_SIZE
	local chunkBlockYTop = chunkBlockYBottom + CHUNK_SIZE - 1

	local checkRadius = Config.treeCheckRadius
	local chunkBlockX = cx * CHUNK_SIZE
	local chunkBlockZ = cz * CHUNK_SIZE

	for bx = chunkBlockX - checkRadius, chunkBlockX + CHUNK_SIZE - 1 + checkRadius do
		for bz = chunkBlockZ - checkRadius, chunkBlockZ + CHUNK_SIZE - 1 + checkRadius do
			if not isTreeRoot(seed, bx, bz) then
				continue
			end

			local worldX = bx * BLOCK_SIZE
			local worldZ = bz * BLOCK_SIZE
			local surfaceBlockY = getSurfaceHeight(seed, worldX, worldZ)

			if surfaceBlockY < Config.seaLevelBlock then
				continue
			end

			local surface = BiomeConfig.getBiome(worldX, worldZ)
			local trunkHeight = getTreeHeight(seed, bx, bz)
			local canopyR = surface.canopyRadius

			local trunkBlock = surface.trunkBlock or BlockType.Wood
			local canopyBlock = surface.canopyBlock or BlockType.Leaves
			local structureType = surface.structureType or "tree"

			-- Mixed mode: pick structure type from hash + use unique blocks
			if structureType == "mixed" then
				local mixHash = hashTwo(seed + 9999, bx, bz)
				structureType = MIXED_STRUCTURES[(mixHash % #MIXED_STRUCTURES) + 1]
				local overrides = STRUCTURE_BLOCKS[structureType]
				if overrides then
					trunkBlock = overrides.trunk
					canopyBlock = overrides.canopy
				end
				-- Height overrides for tree variants
				if structureType == "tree_giant" then
					trunkHeight = 40 + (hashTwo(seed + 5555, bx, bz) % 25) -- 40-64
					canopyR = 4
				elseif structureType == "tree_pine" then
					trunkHeight = 6 + (hashTwo(seed + 5556, bx, bz) % 4) -- 6-9
				elseif structureType == "tree_willow" then
					trunkHeight = 5 + (hashTwo(seed + 5557, bx, bz) % 3) -- 5-7
					canopyR = 3
				elseif structureType == "tree_palm" then
					trunkHeight = 7 + (hashTwo(seed + 5558, bx, bz) % 4) -- 7-10
				end
			end

			if structureType == "cactus" then
				-- Cylindrical saguaro cactus (r=1 cylinder) with arms
				for ty = 0, trunkHeight do
					local y = surfaceBlockY + 1 + ty
					-- 2x2 cylinder core (+ cross pattern for roundness)
					placeBlock(blocks, trunkBlock, bx, y, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bx + 1, y, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bx, y, bz + 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bx + 1, y, bz + 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end
				-- Flower on top
				placeBlock(blocks, canopyBlock, bx, surfaceBlockY + trunkHeight + 2, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				placeBlock(blocks, canopyBlock, bx + 1, surfaceBlockY + trunkHeight + 2, bz + 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				-- Arm at height 3 (cylindrical: 1-block wide arm extending out)
				local armDir = hashTwo(seed + 3333, bx, bz) % 4
				local armDx = if armDir == 0 then 1 elseif armDir == 1 then -1 else 0
				local armDz = if armDir == 2 then 1 elseif armDir == 3 then -1 else 0
				local armY = surfaceBlockY + 3
				-- Arm extends 2 blocks outward from trunk edge, then goes up 2
				local armBaseX = bx + (if armDx > 0 then 2 else if armDx < 0 then -1 else 0)
				local armBaseZ = bz + (if armDz > 0 then 2 else if armDz < 0 then -1 else 0)
				placeBlock(blocks, trunkBlock, armBaseX, armY, armBaseZ, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				placeBlock(blocks, trunkBlock, armBaseX + armDx, armY, armBaseZ + armDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				placeBlock(blocks, trunkBlock, armBaseX + armDx, armY + 1, armBaseZ + armDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				placeBlock(blocks, canopyBlock, armBaseX + armDx, armY + 2, armBaseZ + armDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				-- Second arm opposite (50%)
				if hashTwo(seed + 4444, bx, bz) % 2 == 0 and trunkHeight >= 4 then
					local arm2Y = surfaceBlockY + 5
					local arm2BaseX = bx + (if armDx > 0 then -1 else if armDx < 0 then 2 else 0)
					local arm2BaseZ = bz + (if armDz > 0 then -1 else if armDz < 0 then 2 else 0)
					placeBlock(blocks, trunkBlock, arm2BaseX, arm2Y, arm2BaseZ, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, arm2BaseX - armDx, arm2Y, arm2BaseZ - armDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, arm2BaseX - armDx, arm2Y + 1, arm2BaseZ - armDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, canopyBlock, arm2BaseX - armDx, arm2Y + 2, arm2BaseZ - armDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end

			elseif structureType == "bonsai" then
				-- Bonsai with organic sway trunk + fork-like branches with separate canopy clusters
				local bonsaiTrunk = 4 + (hashTwo(seed + 6100, bx, bz) % 2) -- 4-5
				local topX, topZ = bx, bz
				for ty = 0, bonsaiTrunk - 1 do
					local sx, sz = getTrunkPos(seed, bx, bz, ty)
					placeBlock(blocks, trunkBlock, sx, surfaceBlockY + 1 + ty, sz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					topX, topZ = sx, sz
				end
				-- 3 branches like fork tines: connected to trunk, each with its own canopy cluster
				local branchDirs = { {1, 0}, {-1, 0}, {0, 1}, {0, -1} }
				local branchCount = 2 + (hashTwo(seed + 6101, bx, bz) % 2)
				for bi = 1, branchCount do
					local dir = branchDirs[((hashTwo(seed + 6102 + bi, bx, bz) % #branchDirs)) + 1]
					local branchStartY = surfaceBlockY + 2 + (bi - 1) * 2
					local bsx, bsz = getTrunkPos(seed, bx, bz, 1 + (bi - 1) * 2)
					-- Branch: connector → extends 3 blocks outward, angling up
					placeBlock(blocks, trunkBlock, bsx + dir[1], branchStartY, bsz + dir[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bsx + dir[1] * 2, branchStartY + 1, bsz + dir[2] * 2, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bsx + dir[1] * 3, branchStartY + 2, bsz + dir[2] * 3, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bsx + dir[1] * 4, branchStartY + 2, bsz + dir[2] * 4, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					-- Canopy cluster at branch end (r=2 flat)
					local endX, endZ = bsx + dir[1] * 4, bsz + dir[2] * 4
					local endY = branchStartY + 3
					for dx = -2, 2 do
						for dz = -2, 2 do
							if dx * dx + dz * dz <= 5 then
								placeBlock(blocks, canopyBlock, endX + dx, endY, endZ + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
					placeBlock(blocks, canopyBlock, endX, endY + 1, endZ, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
				end
				-- Small crown at trunk top
				local crownY = surfaceBlockY + bonsaiTrunk + 1
				for dx = -1, 1 do
					for dz = -1, 1 do
						placeBlock(blocks, canopyBlock, topX + dx, crownY, topZ + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					end
				end

			elseif structureType == "tree_giant" then
				-- Massive tree: 2x2 trunk + short stubby leafy branches at intervals
				-- Root buttresses
				for _, roff in { {-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, 1} } do
					placeBlock(blocks, trunkBlock, bx + roff[1], surfaceBlockY + 1, bz + roff[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end
				-- Full 2x2 trunk
				for ty = 0, trunkHeight - 1 do
					for dx = 0, 1 do
						for dz = 0, 1 do
							placeBlock(blocks, trunkBlock, bx + dx, surfaceBlockY + 1 + ty, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
						end
					end
				end
				-- Stubby branches every 6 blocks, 4 directions, with flat canopy pads
				local branchDirs = { {1, 0}, {-1, 0}, {0, 1}, {0, -1} }
				local branchInterval = 6
				for bi = 1, math.floor(trunkHeight / branchInterval) do
					local branchY = surfaceBlockY + bi * branchInterval
					local dirIdx = ((hashTwo(seed + 7000 + bi, bx, bz) % #branchDirs)) + 1
					local dir = branchDirs[dirIdx]
					placeBlock(blocks, trunkBlock, bx + dir[1], branchY, bz + dir[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					placeBlock(blocks, trunkBlock, bx + dir[1] * 2, branchY, bz + dir[2] * 2, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					local padX, padZ = bx + dir[1] * 2, bz + dir[2] * 2
					for dx = -2, 2 do
						for dz = -2, 2 do
							if dx * dx + dz * dz <= 5 then
								placeBlock(blocks, canopyBlock, padX + dx, branchY + 1, padZ + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
				end
				-- Crown at very top
				local crownY = surfaceBlockY + trunkHeight + 1
				for dx = -3, 3 do
					for dz = -3, 3 do
						if dx * dx + dz * dz <= 10 then
							placeBlock(blocks, canopyBlock, bx + dx, crownY, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
						end
					end
				end
				placeBlock(blocks, canopyBlock, bx, crownY + 1, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)

			elseif structureType == "tree_pine" then
				-- Pine: straight trunk + cone canopy
				for ty = 0, trunkHeight - 1 do
					placeBlock(blocks, trunkBlock, bx, surfaceBlockY + 1 + ty, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end
				-- Cone canopy: widest at bottom, narrows to tip
				local coneStart = surfaceBlockY + math.floor(trunkHeight * 0.4)
				local coneLayers = trunkHeight - math.floor(trunkHeight * 0.4) + 2
				for layer = 0, coneLayers - 1 do
					local r = math.max(0, math.floor((coneLayers - layer) * 3 / coneLayers))
					local layerY = coneStart + layer
					for dx = -r, r do
						for dz = -r, r do
							if dx * dx + dz * dz <= r * r + 1 then
								placeBlock(blocks, canopyBlock, bx + dx, layerY, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
				end
				placeBlock(blocks, canopyBlock, bx, coneStart + coneLayers, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)

			elseif structureType == "tree_willow" then
				-- Weeping willow: straight trunk + sphere canopy + hanging vines
				for ty = 0, trunkHeight - 1 do
					placeBlock(blocks, trunkBlock, bx, surfaceBlockY + 1 + ty, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end
				-- Sphere canopy
				local centerY = surfaceBlockY + trunkHeight + 1
				for dx = -canopyR, canopyR do
					for dy = -canopyR, canopyR do
						for dz = -canopyR, canopyR do
							if dx * dx + dy * dy + dz * dz <= canopyR * canopyR then
								placeBlock(blocks, canopyBlock, bx + dx, centerY + dy, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
				end
				-- Hanging vines from canopy bottom (~40% density, 3-6 blocks long)
				local vineBaseY = centerY - canopyR
				for dx = -canopyR, canopyR do
					for dz = -canopyR, canopyR do
						if dx * dx + dz * dz <= canopyR * canopyR then
							if hashTwo(seed + 6660, bx + dx, bz + dz) % 5 < 2 then
								local vineLen = 3 + (hashTwo(seed + 6666, bx + dx, bz + dz) % 4)
								for vy = 1, vineLen do
									placeBlock(blocks, canopyBlock, bx + dx, vineBaseY - vy, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								end
							end
						end
					end
				end

			elseif structureType == "tree_palm" then
				-- Palm with organic sway trunk + frond fan at top
				local topBx, topBz = bx, bz
				for ty = 0, trunkHeight - 1 do
					local sx, sz = getTrunkPos(seed, bx, bz, ty)
					placeBlock(blocks, trunkBlock, sx, surfaceBlockY + 1 + ty, sz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					topBx, topBz = sx, sz
				end
				-- Frond fan: + shape with 2-block drooping arms
				local frondY = surfaceBlockY + trunkHeight + 1
				placeBlock(blocks, canopyBlock, topBx, frondY, topBz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
				for _, fdir in { {1, 0}, {-1, 0}, {0, 1}, {0, -1} } do
					placeBlock(blocks, canopyBlock, topBx + fdir[1], frondY, topBz + fdir[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, topBx + fdir[1] * 2, frondY - 1, topBz + fdir[2] * 2, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, topBx + fdir[1] * 3, frondY - 2, topBz + fdir[2] * 3, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
				end
				-- Diagonal fronds
				for _, fdir in { {1, 1}, {-1, 1}, {1, -1}, {-1, -1} } do
					placeBlock(blocks, canopyBlock, topBx + fdir[1], frondY, topBz + fdir[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
				end

			elseif structureType == "spire" then
				for ty = 0, trunkHeight - 1 do
					local blockToPlace = if ty == trunkHeight - 1 then canopyBlock else trunkBlock
					placeBlock(blocks, blockToPlace, bx, surfaceBlockY + 1 + ty, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end

			elseif structureType == "cluster" then
				for ty = 0, math.min(2, trunkHeight - 1) do
					placeBlock(blocks, trunkBlock, bx, surfaceBlockY + 1 + ty, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
				end
				local centerY = surfaceBlockY + 4
				for dx = -canopyR, canopyR do
					for dy = -canopyR, canopyR do
						for dz = -canopyR, canopyR do
							if dx * dx + dy * dy + dz * dz <= canopyR * canopyR then
								placeBlock(blocks, canopyBlock, bx + dx, centerY + dy, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
				end

			elseif structureType == "column" then
				for ty = 0, trunkHeight - 1 do
					local worldBlockY = surfaceBlockY + 1 + ty
					for dx = 0, 1 do
						for dz = 0, 1 do
							placeBlock(blocks, trunkBlock, bx + dx, worldBlockY, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
						end
					end
				end
				local topY = surfaceBlockY + trunkHeight + 1
				for dx = -1, 1 do
					for dz = -1, 1 do
						placeBlock(blocks, canopyBlock, bx + dx, topY, bz + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					end
				end

			elseif structureType == "mushroom_cluster" then
				-- Group of 3 small mushrooms at slightly different heights
				local offsets = { {0, 0}, {1, 1}, {-1, 1} }
				for i, off in offsets do
					local mh = 1 + (i - 1) -- heights 1, 2, 3
					local mx, mz = bx + off[1], bz + off[2]
					for ty = 0, mh - 1 do
						placeBlock(blocks, trunkBlock, mx, surfaceBlockY + 1 + ty, mz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					end
					-- Small cap: single block + cross
					local capY = surfaceBlockY + mh + 1
					placeBlock(blocks, canopyBlock, mx, capY, mz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, mx + 1, capY, mz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, mx - 1, capY, mz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, mx, capY, mz + 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, mx, capY, mz - 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
				end

			elseif structureType == "mushroom_tall" then
				-- Extra tall mushroom with organic sway + dome cap
				local tallHeight = trunkHeight + 3
				local topX, topZ = bx, bz
				for ty = 0, tallHeight - 1 do
					local sx, sz = getTrunkPos(seed, bx, bz, ty)
					placeBlock(blocks, trunkBlock, sx, surfaceBlockY + 1 + ty, sz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					topX, topZ = sx, sz
				end
				-- Dome cap centered on trunk top
				local domeR = 2
				local domeY = surfaceBlockY + tallHeight + 1
				for dx = -domeR, domeR do
					for dz = -domeR, domeR do
						for dy = 0, domeR do
							if dx * dx + dy * dy + dz * dz <= domeR * domeR + 1 then
								placeBlock(blocks, canopyBlock, topX + dx, domeY + dy, topZ + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
				end

			elseif structureType == "mushroom_shelf" then
				-- Shelf mushroom with organic sway + spiraling shelves
				local topX, topZ = bx, bz
				for ty = 0, trunkHeight + 1 do
					local sx, sz = getTrunkPos(seed, bx, bz, ty)
					placeBlock(blocks, trunkBlock, sx, surfaceBlockY + 1 + ty, sz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					topX, topZ = sx, sz
				end
				-- Shelf brackets at different heights, following trunk sway
				local dirs = { {1, 0}, {0, 1}, {-1, 0}, {0, -1} }
				for shelf = 0, 2 do
					local shelfY = surfaceBlockY + 2 + shelf * 2
					local shelfSx, shelfSz = getTrunkPos(seed, bx, bz, 1 + shelf * 2)
					local dir = dirs[(shelf % 4) + 1]
					placeBlock(blocks, canopyBlock, shelfSx + dir[1], shelfY, shelfSz + dir[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, shelfSx + dir[1] * 2, shelfY, shelfSz + dir[2] * 2, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					local perpDx = if dir[1] == 0 then 1 else 0
					local perpDz = if dir[2] == 0 then 1 else 0
					placeBlock(blocks, canopyBlock, shelfSx + dir[1] + perpDx, shelfY, shelfSz + dir[2] + perpDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					placeBlock(blocks, canopyBlock, shelfSx + dir[1] - perpDx, shelfY, shelfSz + dir[2] - perpDz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
				end

			elseif structureType == "mushroom" then
				-- Mushroom with organic sway trunk
				local topX, topZ = bx, bz
				for ty = 0, trunkHeight - 1 do
					local sx, sz = getTrunkPos(seed, bx, bz, ty)
					placeBlock(blocks, trunkBlock, sx, surfaceBlockY + 1 + ty, sz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					topX, topZ = sx, sz
				end
				local capY = surfaceBlockY + trunkHeight + 1
				for dx = -canopyR, canopyR do
					for dz = -canopyR, canopyR do
						placeBlock(blocks, canopyBlock, topX + dx, capY, topZ + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
					end
				end
				placeBlock(blocks, canopyBlock, topX, capY + 1, topZ, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)

			else -- "tree" (default) with organic sway
				local topX, topZ = bx, bz
				for ty = 0, trunkHeight - 1 do
					local sx, sz = getTrunkPos(seed, bx, bz, ty)
					placeBlock(blocks, trunkBlock, sx, surfaceBlockY + 1 + ty, sz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
					topX, topZ = sx, sz
				end
				local canopyBaseY = surfaceBlockY + trunkHeight
				for canopyLayer = 0, 1 do
					local worldBlockY = canopyBaseY + canopyLayer
					for dx = -canopyR, canopyR do
						for dz = -canopyR, canopyR do
							if canopyLayer == 0 and dx == 0 and dz == 0 then
								continue
							end
							placeBlock(blocks, canopyBlock, topX + dx, worldBlockY, topZ + dz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
						end
					end
				end
				placeBlock(blocks, canopyBlock, topX, canopyBaseY + 2, topZ, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
			end
		end
	end
end

------------------------------------------------------------
-- Egg Node Placement
------------------------------------------------------------

local function placeEggNodes(blocks: buffer, rng: () -> number, eggChance: number)
	if eggChance <= 0 or rng() > eggChance then
		return
	end
	-- Place 1 egg node at random position in chunk
	local ex = math.floor(rng() * CHUNK_SIZE)
	local ey = math.floor(rng() * CHUNK_SIZE)
	local ez = math.floor(rng() * CHUNK_SIZE)
	local idx = ChunkUtil.flatIndex(ex, ey, ez)
	local existing = buffer.readu8(blocks, idx)
	if solidBlocks[existing] then
		buffer.writeu8(blocks, idx, BlockType.EggNode)
	end
end

-- Place neon mushrooms on cave floors (underground only)
local CAVE_MUSHROOM_TYPES = { "mushroom", "mushroom_cluster", "mushroom_tall", "mushroom_shelf" }

local function placeCaveMushrooms(blocks: buffer, seed: number, cx: number, cy: number, cz: number)
	local chunkBlockYBottom = cy * CHUNK_SIZE
	local chunkBlockX = cx * CHUNK_SIZE
	local chunkBlockZ = cz * CHUNK_SIZE

	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			for ly = 1, CHUNK_SIZE - 1 do
				local below = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly - 1, lz))
				local here = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly, lz))
				-- Cave floor: solid below, air here
				if below ~= BlockType.Air and below ~= BlockType.Bedrock and here == BlockType.Air then
					local worldBlockY = chunkBlockYBottom + ly
					if worldBlockY < -2 then -- only deep underground
						local h = hashSeed(seed + 22222, chunkBlockX + lx, worldBlockY, chunkBlockZ + lz)
						if h % 80 == 0 then -- ~1.25% chance per cave floor
							local mushType = CAVE_MUSHROOM_TYPES[(h % #CAVE_MUSHROOM_TYPES) + 1]
							local overrides = STRUCTURE_BLOCKS[mushType]
							local stemBlock = overrides.trunk
							local capBlock = overrides.canopy
							local bx = chunkBlockX + lx
							local bz = chunkBlockZ + lz
							local chunkBlockYTop = chunkBlockYBottom + CHUNK_SIZE - 1

							if mushType == "mushroom_cluster" then
								-- Small cluster
								placeBlock(blocks, stemBlock, bx, worldBlockY, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ)
								placeBlock(blocks, capBlock, bx, worldBlockY + 1, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							elseif mushType == "mushroom_tall" then
								-- Tall stem + small dome
								for ty = 0, 3 do
									placeBlock(blocks, stemBlock, bx, worldBlockY + ty, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								end
								placeBlock(blocks, capBlock, bx, worldBlockY + 4, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx + 1, worldBlockY + 4, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx - 1, worldBlockY + 4, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx, worldBlockY + 4, bz + 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx, worldBlockY + 4, bz - 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							elseif mushType == "mushroom_shelf" then
								-- Short stem + shelf
								placeBlock(blocks, stemBlock, bx, worldBlockY, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, stemBlock, bx, worldBlockY + 1, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								local dir = { {1, 0}, {0, 1}, {-1, 0}, {0, -1} }
								local d = dir[(h % 4) + 1]
								placeBlock(blocks, capBlock, bx + d[1], worldBlockY + 1, bz + d[2], chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx + d[1] * 2, worldBlockY + 1, bz + d[2] * 2, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							else -- basic mushroom
								placeBlock(blocks, stemBlock, bx, worldBlockY, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, stemBlock, bx, worldBlockY + 1, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx, worldBlockY + 2, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx + 1, worldBlockY + 2, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx - 1, worldBlockY + 2, bz, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx, worldBlockY + 2, bz + 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
								placeBlock(blocks, capBlock, bx, worldBlockY + 2, bz - 1, chunkBlockX, chunkBlockYBottom, chunkBlockYTop, chunkBlockZ, true)
							end
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- Main Chunk Generation
------------------------------------------------------------

function WorldGenModule.generateChunk(seed: number, cx: number, cy: number, cz: number): buffer
	local blocks = buffer.create(BLOCKS_PER_CHUNK)

	local chunkBlockYBottom = cy * CHUNK_SIZE
	local chunkBlockYTop = chunkBlockYBottom + CHUNK_SIZE - 1
	local chunkBlockX = cx * CHUNK_SIZE
	local chunkBlockZ = cz * CHUNK_SIZE

	-- Pre-compute per-column data
	local columnSurface = table.create(256, 0)

	local maxSurface = -math.huge
	local minSurface = math.huge

	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			local wx = (chunkBlockX + lx) * BLOCK_SIZE
			local wz = (chunkBlockZ + lz) * BLOCK_SIZE
			local surfaceBlockY = getSurfaceHeight(seed, wx, wz)
			local colIdx = lz * 16 + lx
			columnSurface[colIdx + 1] = surfaceBlockY

			if surfaceBlockY > maxSurface then
				maxSurface = surfaceBlockY
			end
			if surfaceBlockY < minSurface then
				minSurface = surfaceBlockY
			end
		end
	end

	-- Quick rejection: chunk entirely above max surface + tree height
	local maxTreeTop = maxSurface + 10
	if chunkBlockYBottom > maxTreeTop then
		return blocks -- all air
	end

	-- Quick rejection: chunk entirely below bedrock
	local bedrockLevel = minSurface - Config.maxDepthBlocks
	if chunkBlockYTop < bedrockLevel then
		buffer.fill(blocks, 0, BlockType.Bedrock)
		return blocks
	end

	-- Fill terrain column by column (yield periodically to prevent freezes)
	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			local colIdx = lz * 16 + lx
			local surfaceBlockY = columnSurface[colIdx + 1]
			local bedrockY = surfaceBlockY - Config.maxDepthBlocks

			-- Per-column biome lookup
			local wx = (chunkBlockX + lx) * BLOCK_SIZE
			local wz = (chunkBlockZ + lz) * BLOCK_SIZE
			local surface = BiomeConfig.getBiome(wx, wz)

			for ly = 0, CHUNK_SIZE - 1 do
				local worldBlockY = chunkBlockYBottom + ly

				if worldBlockY > surfaceBlockY then
					continue -- air
				end

				local idx = ChunkUtil.flatIndex(lx, ly, lz)

				if worldBlockY <= bedrockY then
					buffer.writeu8(blocks, idx, BlockType.Bedrock)
				elseif worldBlockY == surfaceBlockY then
					buffer.writeu8(blocks, idx, surface.surfaceBlock)
				elseif worldBlockY >= surfaceBlockY - 3 then
					buffer.writeu8(blocks, idx, surface.subsurfaceBlock)
				else
					-- Underground: depth-based layer selection
					local depthBelowSurface = (surfaceBlockY - worldBlockY) * BLOCK_SIZE
					local depthLayer = BiomeConfig.getDepthLayer(depthBelowSurface)
					local blockType = depthLayer.primaryBlock

					-- Noise-driven secondary block mixing
					if depthLayer.secondaryBlock then
						local wx = (chunkBlockX + lx) * BLOCK_SIZE
						local wz = (chunkBlockZ + lz) * BLOCK_SIZE
						local n = noise2D(seed + 1, wx, wz, 32)
						if n > 0.6 then
							blockType = depthLayer.secondaryBlock
						end
					end

					buffer.writeu8(blocks, idx, blockType)
				end
			end
		end
		if lz % 4 == 3 then
			task.wait()
		end
	end

	-- Cave carving for underground chunks (yield periodically)
	if chunkBlockYTop < minSurface then
		for ly = 0, CHUNK_SIZE - 1 do
			for lz = 0, CHUNK_SIZE - 1 do
				for lx = 0, CHUNK_SIZE - 1 do
					local worldBlockY = chunkBlockYBottom + ly
					local colIdx = lz * 16 + lx
					local surfaceBlockY = columnSurface[colIdx + 1]
					local depthStuds = (surfaceBlockY - worldBlockY) * BLOCK_SIZE

					if depthStuds < Config.caveMinDepth then
						continue
					end

					local wx = (chunkBlockX + lx) * BLOCK_SIZE
					local wy = worldBlockY * BLOCK_SIZE
					local wz = (chunkBlockZ + lz) * BLOCK_SIZE
					local n = noise3D(seed + 999, wx, wy, wz, 1 / Config.caveFrequency)

					local colBiome = BiomeConfig.getBiome(wx, wz)
					local caveThr = colBiome.caveThreshold or Config.caveThreshold
					if n > caveThr then
						local idx = ChunkUtil.flatIndex(lx, ly, lz)
						local existing = buffer.readu8(blocks, idx)
						if existing ~= BlockType.Bedrock then
							buffer.writeu8(blocks, idx, BlockType.Air)
						end
					end
				end
			end
			if ly % 4 == 3 then
				task.wait()
			end
		end
	end

	-- Place ore veins in underground chunks
	if chunkBlockYTop < minSurface then
		local chunkHash = hashSeed(seed, cx, cy, cz)
		local rng = createRNG(chunkHash)

		local avgSurface = (maxSurface + minSurface) / 2
		local centerBlockY = chunkBlockYBottom + CHUNK_SIZE / 2
		local depthBelowSurface = (avgSurface - centerBlockY) * BLOCK_SIZE
		local depthLayer = BiomeConfig.getDepthLayer(math.max(0, depthBelowSurface))

		for _, oreConfig in depthLayer.ores do
			placeOreVeins(blocks, rng, oreConfig, 1.0)
		end

		-- Place egg nodes
		placeEggNodes(blocks, rng, depthLayer.eggChance)
	end

	-- Place cave mushrooms in underground chunks (after cave carving)
	if chunkBlockYTop < minSurface then
		placeCaveMushrooms(blocks, seed, cx, cy, cz)
	end

	-- Place trees on chunks near the surface
	if maxSurface + 10 >= chunkBlockYBottom and minSurface <= chunkBlockYTop then
		placeTreesInChunk(blocks, seed, cx, cy, cz)
	end

	return blocks
end

------------------------------------------------------------
-- Spawn & Surface
------------------------------------------------------------

function WorldGenModule.getSpawnPosition(seed: number): Vector3
	local bestX, bestZ = 0, 0
	local bestScore = -math.huge

	for sx = -3, 3 do
		for sz = -3, 3 do
			local wx = sx * CHUNK_STUDS
			local wz = sz * CHUNK_STUDS

			-- Prefer flat terrain near center
			local centerHeight = getSurfaceHeight(seed, wx, wz)
			local variance = 0
			local samples = 0
			for dx = -5, 5, 2 do
				for dz = -5, 5, 2 do
					local h = getSurfaceHeight(seed, wx + dx * BLOCK_SIZE, wz + dz * BLOCK_SIZE)
					variance += math.abs(h - centerHeight)
					samples += 1
				end
			end
			local flatScore = math.max(0, 5 - variance / samples)
			local landScore = getIslandMask(wx, wz) * 5
			local score = flatScore + landScore

			if score > bestScore then
				bestScore = score
				bestX = wx
				bestZ = wz
			end
		end
	end

	local surfaceBlockY = getSurfaceHeight(seed, bestX, bestZ)
	local worldY = (surfaceBlockY + 1) * BLOCK_SIZE + BLOCK_SIZE
	return Vector3.new(bestX, worldY, bestZ)
end

function WorldGenModule.getSurfaceWorldY(seed: number, wx: number, wz: number): number
	local surfaceBlockY = getSurfaceHeight(seed, wx, wz)
	return (surfaceBlockY + 1) * BLOCK_SIZE + BLOCK_SIZE
end

function WorldGenModule.getSurfaceBlockY(seed: number, wx: number, wz: number): number
	return getSurfaceHeight(seed, wx, wz)
end

function WorldGenModule.getSeaLevelBlock(): number
	return Config.seaLevelBlock
end

function WorldGenModule.getWorldRadiusChunks(): number
	return Config.worldRadiusChunks
end

-- Get structure name for a block type (used by mining feedback)
function WorldGenModule.getStructureName(blockTypeId: number): string?
	return BLOCK_STRUCTURE_NAME[blockTypeId]
end

function WorldGenModule.verifyDeterminism(seed: number, cx: number, cy: number, cz: number): boolean
	local a = WorldGenModule.generateChunk(seed, cx, cy, cz)
	local b = WorldGenModule.generateChunk(seed, cx, cy, cz)
	for i = 0, BLOCKS_PER_CHUNK - 1 do
		if buffer.readu8(a, i) ~= buffer.readu8(b, i) then
			return false
		end
	end
	return true
end

return WorldGenModule
