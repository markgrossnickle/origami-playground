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

local function fbmHeight(seed: number, worldX: number, worldZ: number): number
	local BASE_HEIGHT = 48
	local AMPLITUDE = 20
	local nx = worldX / 120
	local nz = worldZ / 120
	local h = math.noise(nx + seed, nz + seed) * AMPLITUDE
	h = h + math.noise(nx * 2 + seed + 100, nz * 2 + seed + 100) * (AMPLITUDE * 0.5)
	return math.floor(BASE_HEIGHT + h)
end

local function shouldPlaceTree(seed: number, worldX: number, worldZ: number): boolean
	local n = math.noise(worldX / 7.3 + seed + 200, worldZ / 7.3 + seed + 200)
	return n > 0.35
end

local function getOreType(seed: number, worldX: number, worldY: number, worldZ: number, depth: string): number?
	local n1 = math.noise(worldX / 5 + seed + 300, worldY / 5 + seed + 300, worldZ / 5 + seed + 300)
	local n2 = math.noise(worldX / 8 + seed + 400, worldY / 8 + seed + 400, worldZ / 8 + seed + 400)
	if depth == "shallow" then
		if n1 > 0.40 then
			return if n2 > 0 then BlockType.TissueOre else BlockType.CrepeOre
		end
	elseif depth == "deep" then
		if n1 > 0.43 then
			return if n2 > 0 then BlockType.FoilOre else BlockType.VellumOre
		end
	elseif depth == "bedrock" then
		if n1 > 0.46 then
			return if n2 > 0 then BlockType.CrystalOre else BlockType.NeonOre
		end
	end
	return nil
end

function WorldGenModule.generateChunk(seed: number, cx: number, cy: number, cz: number): buffer
	local blocks = buffer.create(4096)
	local chunkWorldX = cx * CHUNK_STUDS
	local chunkWorldY = cy * CHUNK_STUDS
	local chunkWorldZ = cz * CHUNK_STUDS

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local worldX = chunkWorldX + lx * BLOCK_SIZE
				local worldY = chunkWorldY + ly * BLOCK_SIZE
				local worldZ = chunkWorldZ + lz * BLOCK_SIZE
				local surfaceHeight = fbmHeight(seed, worldX, worldZ)
				local blockType = BlockType.Air

				if worldY <= 0 then
					blockType = BlockType.Bedrock
				elseif worldY <= surfaceHeight then
					if worldY == surfaceHeight then
						blockType = BlockType.PaperGrass
					elseif worldY > surfaceHeight - 3 * BLOCK_SIZE then
						blockType = BlockType.PaperDirt
					elseif worldY > 40 then
						local ore = getOreType(seed, worldX, worldY, worldZ, "shallow")
						blockType = ore or BlockType.Corrugated
					elseif worldY > 25 then
						local ore = getOreType(seed, worldX, worldY, worldZ, "shallow")
						blockType = ore or BlockType.Cardstock
					elseif worldY > 10 then
						local ore = getOreType(seed, worldX, worldY, worldZ, "deep")
						blockType = ore or BlockType.Manila
					else
						local ore = getOreType(seed, worldX, worldY, worldZ, "bedrock")
						blockType = ore or BlockType.PressedBoard
					end
				end

				local index = ChunkUtil.flatIndex(lx, ly, lz)
				buffer.writeu8(blocks, index, blockType)
			end
		end
	end

	-- Tree pass
	for lz = 0, CHUNK_SIZE - 1 do
		for lx = 0, CHUNK_SIZE - 1 do
			local worldX = chunkWorldX + lx * BLOCK_SIZE
			local worldZ = chunkWorldZ + lz * BLOCK_SIZE
			local surfaceHeight = fbmHeight(seed, worldX, worldZ)
			local surfaceLocalY = math.floor((surfaceHeight - chunkWorldY) / BLOCK_SIZE)
			if surfaceLocalY >= 0 and surfaceLocalY < CHUNK_SIZE - 1 and shouldPlaceTree(seed, worldX, worldZ) then
				local surfIdx = ChunkUtil.flatIndex(lx, surfaceLocalY, lz)
				if buffer.readu8(blocks, surfIdx) == BlockType.PaperGrass then
					local trunkHeight = 3
						+ math.floor(math.noise(worldX / 3 + seed + 500, worldZ / 3 + seed + 500) + 0.5)
					for ty = 1, trunkHeight do
						local trunkLocalY = surfaceLocalY + ty
						if trunkLocalY < CHUNK_SIZE then
							local tIdx = ChunkUtil.flatIndex(lx, trunkLocalY, lz)
							buffer.writeu8(blocks, tIdx, BlockType.PaperLog)
						end
					end
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
