--!strict
-- MiningService: Server-authoritative mining validation, damage accumulation, and drop awards
-- Uses WorldService:BreakBlock(cx, cy, cz, lx, ly, lz) API

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
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

-- Per-player mining state
local playerTiers: { [Player]: number } = {}
local blockDamage: { [string]: number } = {} -- "chunkKey:flatIndex" -> accumulated damage

function MiningService:KnitInit() end

function MiningService:KnitStart()
	-- Clean up on player leave
	Players.PlayerRemoving:Connect(function(player: Player)
		playerTiers[player] = nil
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
	local WorldService = Knit.GetService("WorldService")
	-- Validate player has a character
	local character = player.Character
	if not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	-- Distance check
	local blockWorldPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz) + MiningConfig.WORLD_OFFSET
	local dist = (rootPart.Position - blockWorldPos).Magnitude
	if dist > MiningConfig.REACH_TOLERANCE * 2 then
		return false
	end

	local chunkKey = ChunkUtil.chunkKey(cx, cy, cz)
	local flatIdx = ChunkUtil.flatIndex(lx, ly, lz)

	-- Read block type from chunk data
	local chunkData = WorldService:GetChunkData(cx, cy, cz)
	local blockTypeId = buffer.readu8(chunkData, flatIdx)

	if blockTypeId == BlockType.Air or blockTypeId == BlockType.Bedrock then
		return false
	end

	local blockDef = BlockRegistry.get(blockTypeId)
	if not blockDef or not blockDef.mineable then
		return false
	end

	-- Tool tier check
	local tier = playerTiers[player] or 1
	if tier < blockDef.minTier then
		return false
	end

	-- Get tool power and speed
	local toolDef = MiningConfig.TOOL_TIERS[tier]
	local power = toolDef and toolDef.power or 1
	local speed = toolDef and toolDef.speed or 1.0

	-- Accumulate damage
	local damageKey = chunkKey .. ":" .. flatIdx
	local currentDamage = (blockDamage[damageKey] or 0) + power * speed
	local hardness = blockDef.hardness

	if currentDamage >= hardness then
		-- Block breaks
		blockDamage[damageKey] = nil
		local success = WorldService:BreakBlock(cx, cy, cz, lx, ly, lz)

		if success then
			WorldService.Client.BlockChanged:FireAll(cx, cy, cz, lx, ly, lz, BlockType.Air)
			self.Client.BlockBroken:Fire(player, cx, cy, cz, lx, ly, lz, blockTypeId, blockDef.xp)
			return true
		end
	else
		blockDamage[damageKey] = currentDamage
		-- Fire progress
		local progress = currentDamage / hardness
		self.Client.MineProgress:Fire(player, cx, cy, cz, lx, ly, lz, progress)
	end

	return false
end

-- Client method to set tool tier
function MiningService.Client:SetToolTier(player: Player, tier: number)
	tier = math.clamp(tier, 1, #MiningConfig.TOOL_TIERS)
	playerTiers[player] = tier
end

-- Client method to get current tier
function MiningService.Client:GetTier(player: Player): number
	return playerTiers[player] or 1
end

-- Client method to upgrade tier (simplified -- in production use currency)
function MiningService.Client:UpgradeTier(player: Player): (boolean, number)
	local currentTier = playerTiers[player] or 1
	if currentTier >= #MiningConfig.TOOL_TIERS then
		return false, currentTier
	end
	local newTier = currentTier + 1
	playerTiers[player] = newTier
	return true, newTier
end

return MiningService
