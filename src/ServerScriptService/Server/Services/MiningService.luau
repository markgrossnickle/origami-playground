--!strict
-- MiningService: Server-side mining logic (break validation, tool gating, XP/drops)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local MiningService = Knit.CreateService({
	Name = "MiningService",
	Client = {
		BlockBroken = Knit.CreateSignal(),
		MineProgress = Knit.CreateSignal(),
	},
})

local playerToolTier: { [Player]: number } = {}
local playerMineState: { [Player]: { key: string, progress: number, hardness: number } } = {}

function MiningService:KnitInit() end

function MiningService:KnitStart()
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		playerToolTier[player] = nil
		playerMineState[player] = nil
	end)
end

function MiningService.Client:MineBlock(
	player: Player,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number
): boolean
	return self.Server:_processMine(player, cx, cy, cz, lx, ly, lz)
end

function MiningService.Client:SetToolTier(player: Player, tier: number)
	tier = math.clamp(math.floor(tier), 1, #MiningConfig.TOOL_TIERS)
	playerToolTier[player] = tier
end

function MiningService:_processMine(
	player: Player,
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number
): boolean
	local WorldService = Knit.GetService("WorldService")
	local character = player.Character
	if not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end
	local blockPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)
	local worldBlockPos = blockPos + MiningConfig.WORLD_OFFSET
	if (rootPart.Position - worldBlockPos).Magnitude > MiningConfig.BLOCK_SIZE * 5 + MiningConfig.REACH_TOLERANCE then
		return false
	end
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local chunkData = WorldService:GetChunkData(cx, cy, cz)
	local index = ChunkUtil.flatIndex(lx, ly, lz)
	local blockTypeId = buffer.readu8(chunkData, index)
	local def = BlockRegistry.get(blockTypeId)
	if not def or not def.mineable then
		return false
	end
	local tier = playerToolTier[player] or 1
	if tier < def.minTier then
		return false
	end
	local toolDef = MiningConfig.TOOL_TIERS[tier]
	local power = toolDef.power * toolDef.speed
	local blockKey = key .. ":" .. tostring(index)
	local state = playerMineState[player]
	if not state or state.key ~= blockKey then
		state = { key = blockKey, progress = 0, hardness = def.hardness }
		playerMineState[player] = state
	end
	state.progress = state.progress + power
	if state.progress >= state.hardness then
		local oldType = WorldService:BreakBlock(key, index)
		if oldType ~= 0 then
			self.Client.BlockBroken:Fire(player, cx, cy, cz, lx, ly, lz, blockTypeId, def.xp)
		end
		playerMineState[player] = nil
		return oldType ~= 0
	else
		local pct = math.clamp(state.progress / state.hardness, 0, 1)
		self.Client.MineProgress:Fire(player, cx, cy, cz, lx, ly, lz, pct)
		return false
	end
end

return MiningService
