--!strict
-- MiningService: Server-authoritative mining validation, damage accumulation, and drop awards

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

local playerTiers: { [Player]: number } = {}
local blockDamage: { [string]: number } = {}

function MiningService:KnitInit() end

function MiningService:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	WorldService.BlockBroken:Connect(function(cx, cy, cz, lx, ly, lz, blockTypeId)
		local blockDef = BlockRegistry.get(blockTypeId)
		local _xp = blockDef and blockDef.xp or 0
		local chunkKey = ChunkUtil.chunkKey(cx, cy, cz)
		local flatIndex = ChunkUtil.flatIndex(lx, ly, lz)
		-- Notify all players about the block change
		WorldService.Client.BlockChanged:FireAll(chunkKey, flatIndex, BlockType.Air, lx, ly, lz, cx, cy, cz)
	end)

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
	local blockTypeId = WorldService:GetBlock(chunkKey, flatIdx)

	if blockTypeId == BlockType.Air or blockTypeId == BlockType.Bedrock then
		return false
	end

	local blockDef = BlockRegistry.get(blockTypeId)
	if not blockDef or not blockDef.mineable then
		return false
	end

	local tier = playerTiers[player] or 1
	if tier < blockDef.minTier then
		return false
	end

	local toolDef = MiningConfig.TOOL_TIERS[tier]
	local power = toolDef and toolDef.power or 1
	local speed = toolDef and toolDef.speed or 1.0

	local damageKey = chunkKey .. ":" .. flatIdx
	local currentDamage = (blockDamage[damageKey] or 0) + power * speed
	local hardness = blockDef.hardness

	if currentDamage >= hardness then
		blockDamage[damageKey] = nil
		local oldType = WorldService:BreakBlock(chunkKey, flatIdx)
		if oldType ~= BlockType.Air then
			self.Client.BlockBroken:Fire(player, cx, cy, cz, lx, ly, lz, blockTypeId, blockDef.xp)
			return true
		end
	else
		blockDamage[damageKey] = currentDamage
		local progress = currentDamage / hardness
		self.Client.MineProgress:Fire(player, cx, cy, cz, lx, ly, lz, progress)
	end

	return false
end

function MiningService.Client:SetToolTier(player: Player, tier: number): boolean
	tier = math.clamp(tier, 1, #MiningConfig.TOOL_TIERS)
	playerTiers[player] = tier
	return true
end

function MiningService.Client:GetTier(player: Player): number
	return playerTiers[player] or 1
end

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
