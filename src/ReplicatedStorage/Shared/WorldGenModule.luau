--!strict
-- WorldGenModule: Deterministic procedural world generation using math.noise()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)

local WorldGenModule = {}

local CHUNK_SIZE = MiningConfig.CHUNK_SIZE
local BLOCK_SIZE = MiningConfig.BLOCK_SIZE
local CHUNK_STUDS = MiningConfig.CHUNK_STUDS

-- 2-octave FBM heightmap
local function fbmHeight(seed: number, worldX: number, worldZ: number): number
	local BASE_HEIGHT = 48
	local AMPLITUDE = 20
	local nx = worldX / 120
	local nz = worldZ / 120

	local h = math.noise(nx + seed, nz + seed) * AMPLITUDE
	h = h + math.noise(nx * 2 + seed + 100, nz * 2 + seed + 100) * (AMPLITUDE * 0.5)
	return math.floor(BASE_HEIGHT + h)
end

-- Deterministic tree placement based on position hash
local function shouldPlaceTree(seed: number, worldX: number, worldZ: number): boolean
	local n = math.noise(worldX / 7.3 + seed + 200, worldZ / 7.3 + seed + 200)
	return n > 0.35
end

-- Ore vein check: returns ore type or nil
local function getOreType(seed: number, worldX: number, worldY: number, worldZ: number, depth: string): number?
	local n1 = math.noise(worldX / 5 + seed + 300, worldY / 5 + seed + 300, worldZ / 5 + seed + 300)
	local n2 = math.noise(worldX / 8 + seed + 400, worldY / 8 + seed + 400, worldZ / 8 + seed + 400)

	if depth == "shallow" then
		-- 3% chance: TissueOre or CrepeOre
		if n1 > 0.40 then
			return if n2 > 0 then BlockType.TissueOre else BlockType.CrepeOre
		end
	elseif depth == "deep" then
		-- 2% chance: FoilOre or VellumOre
		if n1 > 0.43 then
			return if n2 > 0 then BlockType.FoilOre else BlockType.VellumOre
		end
	elseif depth == "bedrock" then
		-- 1% chance: CrystalOre or NeonOre
		if n1 > 0.46 then
			return if n2 > 0 then BlockType.CrystalOre else BlockType.NeonOre
		end
	end

	return nil
end

-- Generate a full chunk of blocks
function WorldGenModule.generateChunk(seed: number, cx: number, cy: number, cz: number): buffer
	local blocks = buffer.create(4096)

	local chunkWorldX = cx * CHUNK_STUDS
	local chunkWorldY = cy * CHUNK_STUDS
	local chunkWorldZ = cz * CHUNK_STUDS

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local worldX = chunkWorldX + lx * BLOCK_SIZE -- studs (for noise input)
				local worldZ = chunkWorldZ + lz * BLOCK_SIZE -- studs (for noise input)
				local blockY = cy * CHUNK_SIZE + ly -- block coordinate

				local surfaceHeight = fbmHeight(seed, worldX, worldZ) -- returns blocks
				local blockType = BlockType.Air

				if blockY <= 0 then
					-- Bedrock floor
					blockType = BlockType.Bedrock
				elseif blockY <= surfaceHeight then
					-- Underground
					if blockY == surfaceHeight then
						-- Surface layer
						blockType = BlockType.PaperGrass
					elseif blockY > surfaceHeight - 3 then
						-- Dirt layer (3 blocks below surface)
						blockType = BlockType.PaperDirt
					elseif blockY > 30 then
						-- Shallow zone
						local ore = getOreType(seed, worldX, blockY, worldZ, "shallow")
						blockType = ore or BlockType.Corrugated
					elseif blockY > 20 then
						-- Transition: use Cardstock
						local ore = getOreType(seed, worldX, blockY, worldZ, "shallow")
						blockType = ore or BlockType.Cardstock
					elseif blockY > 10 then
						-- Deep zone
						local ore = getOreType(seed, worldX, blockY, worldZ, "deep")
						blockType = ore or BlockType.Manila
					else
						-- Bedrock zone
						local ore = getOreType(seed, worldX, blockY, worldZ, "bedrock")
						blockType = ore or BlockType.PressedBoard
					end
				end

				local index = ChunkUtil.flatIndex(lx, ly, lz)
				buffer.writeu8(blocks, index, blockType)
			end
		end
	end

	-- Tree pass: place trees on surface blocks within this chunk
	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			local worldX = chunkWorldX + lx * BLOCK_SIZE
			local worldZ = chunkWorldZ + lz * BLOCK_SIZE
			local surfaceHeight = fbmHeight(seed, worldX, worldZ)

			-- Check if surface is in this chunk
			local surfaceLocalY = surfaceHeight - cy * CHUNK_SIZE -- both in blocks
			if surfaceLocalY >= 0 and surfaceLocalY < CHUNK_SIZE - 1 and shouldPlaceTree(seed, worldX, worldZ) then
				-- Check the surface block is grass
				local surfIdx = ChunkUtil.flatIndex(lx, surfaceLocalY, lz)
				if buffer.readu8(blocks, surfIdx) == BlockType.PaperGrass then
					-- Trunk: 3-4 blocks tall
					local trunkHeight = 3
						+ math.floor(math.noise(worldX / 3 + seed + 500, worldZ / 3 + seed + 500) + 0.5)
					for ty = 1, trunkHeight do
						local trunkLocalY = surfaceLocalY + ty
						if trunkLocalY < CHUNK_SIZE then
							local tIdx = ChunkUtil.flatIndex(lx, trunkLocalY, lz)
							buffer.writeu8(blocks, tIdx, BlockType.PaperLog)
						end
					end

					-- Canopy: sphere of leaves at top
					local canopyY = surfaceLocalY + trunkHeight + 1
					for dy = -1, 1 do
						for dz = -1, 1 do
							for dx = -1, 1 do
								local clx = lx + dx
								local cly = canopyY + dy
								local clz = lz + dz
								if
									clx >= 0
									and clx < CHUNK_SIZE
									and cly >= 0
									and cly < CHUNK_SIZE
									and clz >= 0
									and clz < CHUNK_SIZE
								then
									-- Skip corners for rounder shape
									if math.abs(dx) + math.abs(dy) + math.abs(dz) < 3 then
										local cIdx = ChunkUtil.flatIndex(clx, cly, clz)
										if buffer.readu8(blocks, cIdx) == BlockType.Air then
											buffer.writeu8(blocks, cIdx, BlockType.PaperLeaves)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return blocks
end

return WorldGenModule
