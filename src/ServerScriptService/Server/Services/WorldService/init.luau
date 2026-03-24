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
local _MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

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

-- Internal state
local chunks: { [string]: buffer } = {}
local deltas: { [string]: { [number]: number } } = {}
local refCounts: { [string]: number } = {}
local worldSeed = 42

local deltaStore: DataStore? = nil

function WorldService:KnitInit()
	-- Try to get DataStore (will fail in Studio without API access)
	pcall(function()
		deltaStore = DataStoreService:GetDataStore("MiningWorldDeltas_v1")
	end)
end

function WorldService:KnitStart() end

-- Get or generate chunk data
function WorldService:GetChunkData(cx: number, cy: number, cz: number): buffer
	local key = ChunkUtil.chunkKey(cx, cy, cz)

	if chunks[key] then
		return chunks[key]
	end

	-- Generate chunk
	local blockData = WorldGenModule.generateChunk(worldSeed, cx, cy, cz)

	-- Apply saved deltas
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

-- Break a block at the given chunk + local position
function WorldService:BreakBlock(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number): boolean
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local blockData = chunks[key]
	if not blockData then
		return false
	end

	local index = ChunkUtil.flatIndex(lx, ly, lz)
	local currentType = buffer.readu8(blockData, index)

	if currentType == BlockType.Air or currentType == BlockType.Bedrock then
		return false
	end

	-- Set to air
	buffer.writeu8(blockData, index, BlockType.Air)

	-- Track delta
	if not deltas[key] then
		deltas[key] = {}
	end
	deltas[key][index] = BlockType.Air

	-- Save delta periodically
	self:_saveDeltaDeferred(key)

	self.BlockBroken:Fire(cx, cy, cz, lx, ly, lz, currentType)
	return true
end

-- Subscribe a player to a chunk (increment ref count)
function WorldService:Subscribe(cx: number, cy: number, cz: number)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	refCounts[key] = (refCounts[key] or 0) + 1
end

-- Unsubscribe a player from a chunk (decrement ref count, unload if zero)
function WorldService:Unsubscribe(cx: number, cy: number, cz: number)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local count = refCounts[key]
	if not count then
		return
	end

	count = count - 1
	if count <= 0 then
		refCounts[key] = nil
		-- Unload chunk if no refs
		self:_unloadChunk(key)
	else
		refCounts[key] = count
	end
end

-- Get block type at a world position
function WorldService:GetBlockAt(worldX: number, worldY: number, worldZ: number): number
	local cx, cy, cz = ChunkUtil.worldToChunk(worldX, worldY, worldZ)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local blockData = chunks[key]
	if not blockData then
		return BlockType.Air
	end

	local lx, ly, lz = ChunkUtil.worldToLocalBlock(worldX, worldY, worldZ)
	local index = ChunkUtil.flatIndex(lx, ly, lz)
	return buffer.readu8(blockData, index)
end

-- Client method: request chunk data
function WorldService.Client:GetChunkData(_player: Player, cx: number, cy: number, cz: number): buffer
	return self.Server:GetChunkData(cx, cy, cz)
end

-- Internal: unload chunk from memory
function WorldService:_unloadChunk(key: string)
	chunks[key] = nil
	-- Keep deltas in memory briefly for save
end

-- Internal: load delta from DataStore
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

-- Internal: save delta to DataStore (deferred to avoid throttle)
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
