--!strict
--!native

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
	maxElevationBlocks = 20, -- max surface height variation in blocks
	maxDepthBlocks = 400, -- how deep underground goes (in blocks, 2000 studs / 5)
	-- Island shape
	islandFalloffStart = 0.55,
	islandFalloffEnd = 0.85,
	-- Noise — terrain
	terrainFrequency = 0.005,
	terrainOctaves = 2,
	terrainLacunarity = 2.0,
	terrainPersistence = 0.25,
	-- Terrain smoothing
	terrainSmoothingRadius = 2,
	maxSlopeBlocks = 2,
	-- Heightmap plateau enforcement
	seaLevelFlattenRange = 3,
	seaLevelFlattenStrength = 0.7,
	plateauBandSize = 2,
	minPlateauCells = 10,
	globalSlopePasses = 3,
	-- Cave generation
	caveFrequency = 0.02,
	caveThreshold = 0.55, -- noise > this = cave
	caveMinDepth = 40, -- don't carve caves within 40 studs of surface
	-- Trees
	treeDensityMultiplier = 1.0,
	treeCheckRadius = 2,
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

local function fbmNoise(seed: number, x: number, z: number, baseScale: number, octaves: number): number
	local value = 0
	local amplitude = 1
	local frequency = 1
	local maxAmplitude = 0

	for i = 0, octaves - 1 do
		value += noise2D(seed + i * 31, x, z, baseScale / frequency) * amplitude
		maxAmplitude += amplitude
		amplitude *= Config.terrainPersistence
		frequency *= Config.terrainLacunarity
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

local function getSurfaceHeightRaw(seed: number, wx: number, wz: number): number
	local islandMask = getIslandMask(wx, wz)
	if islandMask <= 0 then
		return Config.seaLevelBlock - 3
	end

	local rawHeight = fbmNoise(seed, wx, wz, 1 / Config.terrainFrequency, Config.terrainOctaves)
	local surfaceBlock = Config.seaLevelBlock + math.floor(rawHeight * Config.maxElevationBlocks * islandMask)
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

	-- Pass 1a: Raw noise heights
	local rawHm = buffer.create(total)
	for bz = 0, size - 1 do
		for bx = 0, size - 1 do
			local wx = (HEIGHTMAP_ORIGIN + bx) * BLOCK_SIZE
			local wz = (HEIGHTMAP_ORIGIN + bz) * BLOCK_SIZE
			local h = getSurfaceHeightRaw(seed, wx, wz)
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

local function _ensureHeightmap(seed: number)
	if globalHeightmap and heightmapSeed == seed then
		return
	end
	_initializeGlobalHeightmap(seed)
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
	local surface = BiomeConfig.Surface
	local density = surface.treeDensity * Config.treeDensityMultiplier
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
	local surface = BiomeConfig.Surface
	local h = hashTwo(seed + 8888, bx, bz)
	local range = surface.trunkHeightMax - surface.trunkHeightMin + 1
	return surface.trunkHeightMin + (h % range)
end

local function placeTreesInChunk(blocks: buffer, seed: number, cx: number, cy: number, cz: number)
	local chunkBlockYBottom = cy * CHUNK_SIZE
	local chunkBlockYTop = chunkBlockYBottom + CHUNK_SIZE - 1
	local surface = BiomeConfig.Surface

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

			local trunkHeight = getTreeHeight(seed, bx, bz)
			local canopyR = surface.canopyRadius

			for ty = 0, trunkHeight - 1 do
				local worldBlockY = surfaceBlockY + 1 + ty
				if worldBlockY >= chunkBlockYBottom and worldBlockY <= chunkBlockYTop then
					local lx = bx - chunkBlockX
					local ly = worldBlockY - chunkBlockYBottom
					local lz = bz - chunkBlockZ
					if lx >= 0 and lx < CHUNK_SIZE and lz >= 0 and lz < CHUNK_SIZE then
						local idx = ChunkUtil.flatIndex(lx, ly, lz)
						buffer.writeu8(blocks, idx, BlockType.Wood)
					end
				end
			end

			local canopyBaseY = surfaceBlockY + trunkHeight
			for canopyLayer = 0, 1 do
				local worldBlockY = canopyBaseY + canopyLayer
				if worldBlockY >= chunkBlockYBottom and worldBlockY <= chunkBlockYTop then
					local ly = worldBlockY - chunkBlockYBottom
					for dx = -canopyR, canopyR do
						for dz = -canopyR, canopyR do
							if canopyLayer == 0 and dx == 0 and dz == 0 then
								continue
							end
							local lx = (bx + dx) - chunkBlockX
							local lz2 = (bz + dz) - chunkBlockZ
							if lx >= 0 and lx < CHUNK_SIZE and lz2 >= 0 and lz2 < CHUNK_SIZE then
								local idx = ChunkUtil.flatIndex(lx, ly, lz2)
								if buffer.readu8(blocks, idx) == BlockType.Air then
									buffer.writeu8(blocks, idx, BlockType.Leaves)
								end
							end
						end
					end
				end
			end

			local capY = canopyBaseY + 2
			if capY >= chunkBlockYBottom and capY <= chunkBlockYTop then
				local lx = bx - chunkBlockX
				local ly = capY - chunkBlockYBottom
				local lz = bz - chunkBlockZ
				if lx >= 0 and lx < CHUNK_SIZE and lz >= 0 and lz < CHUNK_SIZE then
					local idx = ChunkUtil.flatIndex(lx, ly, lz)
					if buffer.readu8(blocks, idx) == BlockType.Air then
						buffer.writeu8(blocks, idx, BlockType.Leaves)
					end
				end
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

	local surface = BiomeConfig.Surface

	-- Fill terrain column by column (yield periodically to prevent freezes)
	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			local colIdx = lz * 16 + lx
			local surfaceBlockY = columnSurface[colIdx + 1]
			local bedrockY = surfaceBlockY - Config.maxDepthBlocks

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

					if n > Config.caveThreshold then
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
