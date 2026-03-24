--!strict
-- WorldService: Server-side chunk lifecycle, generation, delta tracking, DataStore persistence

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local WorldService = Knit.CreateService({
	Name = "WorldService",
	ChunkGenerated = Signal.new(),
	BlockBroken = Signal.new(),
	Client = {
		ChunkLoaded = Knit.CreateSignal(),
		ChunkUnloaded = Knit.CreateSignal(),
		BlockChanged = Knit.CreateSignal(),
	},
})

local chunks: { [string]: buffer } = {}
local deltas: { [string]: { [number]: number } } = {}
local refCounts: { [string]: number } = {}
local worldSeed = 42
local deltaStore: DataStore? = nil

function WorldService:KnitInit()
	pcall(function()
		deltaStore = DataStoreService:GetDataStore("MiningWorldDeltas_v1")
	end)
end

function WorldService:KnitStart() end

function WorldService:GetChunkData(cx: number, cy: number, cz: number): buffer
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	if chunks[key] then
		return chunks[key]
	end
	local blockData = WorldGenModule.generateChunk(worldSeed, cx, cy, cz)
	local savedDelta = self:_loadDelta(key)
	if savedDelta then
		for index, blockTypeId in pairs(savedDelta) do
			buffer.writeu8(blockData, index, blockTypeId)
		end
		deltas[key] = savedDelta
	end
	chunks[key] = blockData
	self.ChunkGenerated:Fire(cx, cy, cz)
	return blockData
end

function WorldService:GetBlock(chunkKey: string, flatIndex: number): number
	local blockData = chunks[chunkKey]
	if not blockData then
		return BlockType.Air
	end
	return buffer.readu8(blockData, flatIndex)
end

function WorldService:BreakBlock(chunkKey: string, flatIndex: number): number
	local blockData = chunks[chunkKey]
	if not blockData then
		return BlockType.Air
	end
	local currentType = buffer.readu8(blockData, flatIndex)
	if currentType == BlockType.Air or currentType == BlockType.Bedrock then
		return BlockType.Air
	end
	buffer.writeu8(blockData, flatIndex, BlockType.Air)
	if not deltas[chunkKey] then
		deltas[chunkKey] = {}
	end
	deltas[chunkKey][flatIndex] = BlockType.Air
	self:_saveDeltaDeferred(chunkKey)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	self.BlockBroken:Fire(cx, cy, cz, lx, ly, lz, currentType)
	return currentType
end

function WorldService:Subscribe(cx: number, cy: number, cz: number)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	refCounts[key] = (refCounts[key] or 0) + 1
end

function WorldService:Unsubscribe(cx: number, cy: number, cz: number)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local count = refCounts[key]
	if not count then
		return
	end
	count = count - 1
	if count <= 0 then
		refCounts[key] = nil
		chunks[key] = nil
	else
		refCounts[key] = count
	end
end

function WorldService.Client:GetChunkData(_player: Player, cx: number, cy: number, cz: number): buffer
	return self.Server:GetChunkData(cx, cy, cz)
end

function WorldService:_loadDelta(key: string): { [number]: number }?
	if not deltaStore then
		return nil
	end
	local ok, data = pcall(function()
		return (deltaStore :: DataStore):GetAsync("chunk_" .. key)
	end)
	if ok and data then
		return ChunkSerializer.deserializeDelta(data)
	end
	return nil
end

local pendingSaves: { [string]: boolean } = {}

function WorldService:_saveDeltaDeferred(key: string)
	if pendingSaves[key] or not deltaStore then
		return
	end
	pendingSaves[key] = true
	task.delay(5, function()
		pendingSaves[key] = nil
		local delta = deltas[key]
		if not delta then
			return
		end
		local serialized = ChunkSerializer.serializeDelta(delta)
		pcall(function()
			(deltaStore :: DataStore):SetAsync("chunk_" .. key, serialized)
		end)
	end)
end

return WorldService
