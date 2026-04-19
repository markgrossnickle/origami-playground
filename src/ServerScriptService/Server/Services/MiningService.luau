--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local ToolRegistry = require(ReplicatedStorage.Shared.ToolRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local REACH_TOLERANCE = 10
local RATE_TOLERANCE = 0.8

type MiningState = {
	chunkKey: number?,
	flatIndex: number,
	damage: number,
	lastRequestTime: number,
}

--[=[
	@class MiningService
	Validates mining requests, accumulates damage, awards drops/XP.
]=]
local MiningService = Knit.CreateService({
	Name = "MiningService",

	BlockMined = Signal.new(),

	Client = {
		MiningResult = Knit.CreateSignal(),
		TierBlocked = Knit.CreateSignal(),
		EquipTool = Knit.CreateSignal(),
		ToolEquipped = Knit.CreateSignal(),
		CraftTool = Knit.CreateSignal(),
		ToolAcquired = Knit.CreateSignal(),
	},
})

local WorldService
local PlayerDataService

local miningStates: { [Player]: MiningState } = {}
local equippedTools: { [Player]: string } = {}

-- Helpers

local function _getPlayerTool(player: Player)
	local toolId = equippedTools[player] or "paper_hands"
	return ToolRegistry.get(toolId) or ToolRegistry.getDefault()
end

local function _getPlayerDistance(player: Player, chunkKey: number, flatIndex: number): number?
	local character = player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local blockPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)

	return (rootPart.Position - blockPos).Magnitude
end

local function _awardDrops(player: Player, blockTypeId: number, chunkKey: number, flatIndex: number)
	if not player.Parent then
		return
	end

	local config = BlockRegistry.get(blockTypeId)
	if not config then
		return
	end

	local droppedItemId: string? = nil
	local droppedCount = 0
	local xpAwarded = config.xp

	if config.drops then
		for _, drop in config.drops do
			if math.random() <= drop.chance then
				droppedItemId = drop.itemId
				droppedCount = drop.count

				-- Add to player inventory
				local currentCount = PlayerDataService:Read(player, { "MiningInventory", drop.itemId }) or 0
				PlayerDataService:Write(player, { "MiningInventory", drop.itemId }, currentCount + drop.count)
			end
		end
	end

	if not player.Parent then
		return
	end

	-- Update stats
	local totalMined = PlayerDataService:Read(player, { "BlocksMined" }) or 0
	PlayerDataService:Write(player, { "BlocksMined" }, totalMined + 1)

	-- Track deepest depth
	local _, chunkCY, _ = ChunkUtil.parseChunkKey(chunkKey)
	local _, ly, _ = ChunkUtil.fromFlatIndex(flatIndex)
	local worldY = chunkCY * ChunkUtil.CHUNK_STUDS + ly * ChunkUtil.BLOCK_SIZE
	local depth = ChunkUtil.depthFromWorldY(worldY)
	local currentDeepest = PlayerDataService:Read(player, { "DepthReached" }) or 0
	if depth > currentDeepest then
		PlayerDataService:Write(player, { "DepthReached" }, depth)
	end

	if player.Parent then
		MiningService.Client.MiningResult:Fire(player, true, droppedItemId, droppedCount, xpAwarded)
	end
end

-- Tree cascade-break

local TREE_COLLAPSE_DELAY = 0.08
local TREE_MAX_LATERAL = 3
local TREE_MAX_BFS_ITERATIONS = 200

-- Hoisted neighbor offsets for tree BFS (no downward — trees grow up/sideways)
local TREE_BFS_OFFSETS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

local function _getBlockAtWorld(worldX: number, worldY: number, worldZ: number): number
	local tcx, tcy, tcz = ChunkUtil.worldToChunk(worldX, worldY, worldZ)
	local tKey = ChunkUtil.chunkKey(tcx, tcy, tcz)
	local tFlatIndex = ChunkUtil.worldToFlatIndex(worldX, worldY, worldZ)
	return WorldService:GetBlock(tKey, tFlatIndex)
end

local function _tryTreeCollapse(player: Player, chunkKey: number, flatIndex: number)
	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local blockPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)
	local blockSize = ChunkUtil.BLOCK_SIZE

	local belowBlock = _getBlockAtWorld(blockPos.X, blockPos.Y - blockSize, blockPos.Z)
	if belowBlock == BlockType.Wood then
		return
	end

	local aboveBlock = _getBlockAtWorld(blockPos.X, blockPos.Y + blockSize, blockPos.Z)
	if aboveBlock ~= BlockType.Wood then
		return
	end

	local trunkX = blockPos.X
	local trunkZ = blockPos.Z
	local maxLateralStuds = TREE_MAX_LATERAL * blockSize

	-- Pack world-space block coordinates into a single number for visited
	-- tracking, avoiding the string allocations the previous string.format
	-- pattern produced (up to ~1200 strings per tree collapse BFS).
	local VISIT_BIAS = 32768
	local VISIT_SCALE = 65536
	local function _visitKey(x: number, y: number, z: number): number
		local bx = math.floor(x / blockSize) + VISIT_BIAS
		local by = math.floor(y / blockSize) + VISIT_BIAS
		local bz = math.floor(z / blockSize) + VISIT_BIAS
		return bx * VISIT_SCALE * VISIT_SCALE + by * VISIT_SCALE + bz
	end

	local treeBlocks: { { x: number, y: number, z: number } } = {}
	local visited: { [number]: boolean } = {}

	local queue: { { x: number, y: number, z: number } } = {}
	local queueHead = 1
	local iterations = 0
	table.insert(queue, { x = blockPos.X, y = blockPos.Y + blockSize, z = blockPos.Z })

	while queueHead <= #queue and iterations < TREE_MAX_BFS_ITERATIONS do
		iterations += 1
		local pos = queue[queueHead]
		queueHead += 1
		local key = _visitKey(pos.x, pos.y, pos.z)
		if visited[key] then
			continue
		end
		visited[key] = true

		local bt = _getBlockAtWorld(pos.x, pos.y, pos.z)
		if bt ~= BlockType.Wood and bt ~= BlockType.Leaves then
			continue
		end

		local dx = math.abs(pos.x - trunkX)
		local dz = math.abs(pos.z - trunkZ)
		if dx > maxLateralStuds or dz > maxLateralStuds then
			continue
		end

		table.insert(treeBlocks, pos)

		for _, offset in TREE_BFS_OFFSETS do
			local nx = pos.x + offset[1] * blockSize
			local ny = pos.y + offset[2] * blockSize
			local nz = pos.z + offset[3] * blockSize
			local nKey = _visitKey(nx, ny, nz)
			if not visited[nKey] then
				table.insert(queue, { x = nx, y = ny, z = nz })
			end
		end
	end

	table.sort(treeBlocks, function(a, b)
		return a.y < b.y
	end)

	task.spawn(function()
		for _, pos in treeBlocks do
			if not player.Parent then
				break
			end

			local tcx, tcy, tcz = ChunkUtil.worldToChunk(pos.x, pos.y, pos.z)
			local tKey = ChunkUtil.chunkKey(tcx, tcy, tcz)
			local tFlatIndex = ChunkUtil.worldToFlatIndex(pos.x, pos.y, pos.z)
			local oldBlock = WorldService:BreakBlock(tKey, tFlatIndex)
			if oldBlock ~= BlockType.Air then
				_awardDrops(player, oldBlock, tKey, tFlatIndex)
			end

			task.wait(TREE_COLLAPSE_DELAY)
		end
	end)
end

-- Mine request handler

local function _handleMineRequest(player: Player, chunkKey: number, flatIndex: number)
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK then
		return
	end

	local blockTypeId = WorldService:GetBlock(chunkKey, flatIndex)
	if blockTypeId == BlockType.Air then
		return
	end

	if not BlockRegistry.isMineable(blockTypeId) then
		return
	end

	local tool = _getPlayerTool(player)

	local blockConfig = BlockRegistry.get(blockTypeId)
	if blockConfig and tool.tier < blockConfig.minTier then
		MiningService.Client.TierBlocked:Fire(player, blockConfig.name, blockConfig.minTier)
		return
	end

	local dist = _getPlayerDistance(player, chunkKey, flatIndex)
	if not dist or dist > (tool.reach + REACH_TOLERANCE) then
		return
	end

	local now = os.clock()
	local state = miningStates[player]
	local minInterval = (1 / tool.speed) * RATE_TOLERANCE

	if state and state.lastRequestTime then
		local elapsed = now - state.lastRequestTime
		if elapsed < minInterval then
			return
		end
	end

	if not state or state.chunkKey ~= chunkKey or state.flatIndex ~= flatIndex then
		state = {
			chunkKey = chunkKey,
			flatIndex = flatIndex,
			damage = 0,
			lastRequestTime = now,
		}
		miningStates[player] = state
	end

	state.lastRequestTime = now
	state.damage += tool.power

	local hardness = BlockRegistry.getHardness(blockTypeId)
	if state.damage >= hardness then
		local currentBlock = WorldService:GetBlock(chunkKey, flatIndex)
		if currentBlock == BlockType.Air then
			state.damage = 0
			return
		end

		WorldService:BreakBlock(chunkKey, flatIndex)

		_awardDrops(player, blockTypeId, chunkKey, flatIndex)

		if blockTypeId == BlockType.Wood then
			_tryTreeCollapse(player, chunkKey, flatIndex)
		end

		state.damage = 0
		state.chunkKey = nil
		state.flatIndex = -1

		MiningService.BlockMined:Fire(player, chunkKey, flatIndex, blockConfig)
	end
end

-- Knit lifecycle

function MiningService:KnitInit()
	Players.PlayerRemoving:Connect(function(player)
		miningStates[player] = nil
		equippedTools[player] = nil
	end)
end

function MiningService:KnitStart()
	WorldService = Knit.GetService("WorldService")
	PlayerDataService = Knit.GetService("PlayerDataService")

	WorldService._onMineRequest:Connect(function(player: Player, chunkKey: number, flatIndex: number)
		_handleMineRequest(player, chunkKey, flatIndex)
	end)

	-- Handle tool equip requests
	self.Client.EquipTool:Connect(function(player: Player, toolId: string)
		if type(toolId) ~= "string" then
			return
		end

		local toolConfig = ToolRegistry.get(toolId)
		if not toolConfig then
			return
		end

		-- paper_hands is always available
		if toolId ~= "paper_hands" then
			local hasItem = PlayerDataService:Read(player, { "MiningInventory", toolId })
			if not hasItem or hasItem <= 0 then
				return
			end
		end

		equippedTools[player] = toolId
		PlayerDataService:Write(player, { "EquippedTool" }, toolId)
		self.Client.ToolEquipped:Fire(player, toolId)
	end)

	-- Handle tool crafting
	self.Client.CraftTool:Connect(function(player: Player, toolId: string)
		if type(toolId) ~= "string" then
			return
		end

		local toolConfig = ToolRegistry.get(toolId)
		if not toolConfig or not toolConfig.craftRecipe then
			return
		end

		for itemId, needed in toolConfig.craftRecipe do
			local have = PlayerDataService:Read(player, { "MiningInventory", itemId }) or 0
			if have < needed then
				return
			end
		end

		for itemId, needed in toolConfig.craftRecipe do
			local have = PlayerDataService:Read(player, { "MiningInventory", itemId }) or 0
			PlayerDataService:Write(player, { "MiningInventory", itemId }, have - needed)
		end

		local currentCount = PlayerDataService:Read(player, { "MiningInventory", toolId }) or 0
		PlayerDataService:Write(player, { "MiningInventory", toolId }, currentCount + 1)

		self.Client.ToolAcquired:Fire(player, toolId)
	end)

	-- Load player's saved tool (or default to paper_hands)
	local function _loadPlayerTool(player: Player)
		equippedTools[player] = "paper_hands"
		task.spawn(function()
			PlayerDataService:WaitForProfile(player)
				:andThen(function()
					if not player.Parent then
						return
					end
					local savedTool = PlayerDataService:Read(player, { "EquippedTool" })
					if savedTool and ToolRegistry.get(savedTool) then
						equippedTools[player] = savedTool
					end
				end)
				:catch(function(err)
					warn("[MiningService] Failed to load tool:", err)
				end)
		end)
	end

	for _, player in Players:GetPlayers() do
		_loadPlayerTool(player)
	end

	Players.PlayerAdded:Connect(function(player)
		_loadPlayerTool(player)
	end)
end

function MiningService.Client:GetMiningInventory(player: Player)
	return PlayerDataService:Read(player, { "MiningInventory" }) or {}
end

function MiningService.Client:GetEquippedTool(player: Player)
	return PlayerDataService:Read(player, { "EquippedTool" }) or "paper_hands"
end

return MiningService
