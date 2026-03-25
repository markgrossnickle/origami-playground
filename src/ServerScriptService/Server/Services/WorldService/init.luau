--!strict
-- WorldService: Manages chunk lifecycle, generation, and modification
-- Server-authoritative chunk storage with streaming support

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)
local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)

local BLOCKS_PER_CHUNK = MiningConfig.BLOCKS_PER_CHUNK

local WorldService = Knit.CreateService({
	Name = "WorldService",
	Client = {
		ChunkLoaded = Knit.CreateSignal(),
		ChunkUnloaded = Knit.CreateSignal(),
		BlockChanged = Knit.CreateSignal(),
	},
})

-- Internal state
local seed: number = 0
local chunks: { [string]: buffer } = {}
local deltas: { [string]: { [number]: number } } = {}
local refCounts: { [string]: number } = {}
local playerSubscriptions: { [Player]: { [string]: boolean } } = {}

function WorldService:KnitInit()
	seed = math.random(1, 999999)
	print("[WorldService] Initialized with seed:", seed)
	-- MiningWorld folder is created by Server:_setupWorld(), not here
end

function WorldService:KnitStart()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		local subs = playerSubscriptions[player]
		if subs then
			for chunkKey in subs do
				self:_unrefChunk(chunkKey)
			end
			playerSubscriptions[player] = nil
		end
	end)
end

function WorldService:GetSeed(): number
	return seed
end

function WorldService:GetChunkData(cx: number, cy: number, cz: number): buffer
	local key = ChunkUtil.chunkKey(cx, cy, cz)

	if not chunks[key] then
		local generated = WorldGenModule.generateChunk(seed, cx, cy, cz)
		local chunkDeltas = deltas[key]
		if chunkDeltas then
			for index, blockTypeVal in chunkDeltas do
				buffer.writeu8(generated, index, blockTypeVal)
			end
		end
		chunks[key] = generated
	end

	return chunks[key]
end

function WorldService:BreakBlock(chunkKey: string, flatIndex: number): number
	local chunkData = chunks[chunkKey]
	if not chunkData then
		return BlockType.Air
	end

	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end

	local oldType = buffer.readu8(chunkData, flatIndex)
	if oldType == BlockType.Air then
		return BlockType.Air
	end

	buffer.writeu8(chunkData, flatIndex, BlockType.Air)

	if not deltas[chunkKey] then
		deltas[chunkKey] = {}
	end
	deltas[chunkKey][flatIndex] = BlockType.Air

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)

	for player, subs in playerSubscriptions do
		if subs[chunkKey] then
			self.Client.BlockChanged:Fire(player, chunkKey, flatIndex, BlockType.Air, lx, ly, lz, cx, cy, cz)
		end
	end

	return oldType
end

function WorldService:Subscribe(player: Player, chunkKey: string)
	if not playerSubscriptions[player] then
		playerSubscriptions[player] = {}
	end

	if playerSubscriptions[player][chunkKey] then
		return
	end

	playerSubscriptions[player][chunkKey] = true

	if not refCounts[chunkKey] then
		refCounts[chunkKey] = 0
	end
	refCounts[chunkKey] += 1

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local chunkData = self:GetChunkData(cx, cy, cz)

	-- Count non-air blocks for diagnostic
	local nonAir = 0
	for i = 0, 4095 do
		if buffer.readu8(chunkData, i) ~= 0 then
			nonAir += 1
		end
	end

	local compressed = ChunkSerializer.compress(chunkData)
	print(
		string.format(
			"[WorldService] Subscribe chunk %s (cx=%d,cy=%d,cz=%d): %d non-air blocks, %d bytes compressed",
			chunkKey,
			cx,
			cy,
			cz,
			nonAir,
			buffer.len(compressed)
		)
	)
	self.Client.ChunkLoaded:Fire(player, chunkKey, compressed, cx, cy, cz)
end

function WorldService:Unsubscribe(player: Player, chunkKey: string)
	if not playerSubscriptions[player] then
		return
	end

	if not playerSubscriptions[player][chunkKey] then
		return
	end

	playerSubscriptions[player][chunkKey] = nil
	self:_unrefChunk(chunkKey)

	self.Client.ChunkUnloaded:Fire(player, chunkKey)
end

function WorldService:_unrefChunk(chunkKey: string)
	if not refCounts[chunkKey] then
		return
	end

	refCounts[chunkKey] -= 1
	if refCounts[chunkKey] <= 0 then
		refCounts[chunkKey] = nil
		if not deltas[chunkKey] then
			chunks[chunkKey] = nil
		end
	end
end

function WorldService:GetBlock(chunkKey: string, flatIndex: number): number
	local chunkData = chunks[chunkKey]
	if not chunkData then
		return BlockType.Air
	end
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return BlockType.Air
	end
	return buffer.readu8(chunkData, flatIndex)
end

function WorldService.Client:GetSeed(_player: Player): number
	return seed
end

return WorldService
