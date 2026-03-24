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
		RequestMine = Knit.CreateSignal(),
		MineResult = Knit.CreateSignal(),
	},
})

local playerTiers: { [Player]: number } = {}
local blockDamage: { [string]: number } = {}

function MiningService:KnitInit() end

function MiningService:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	self.Client.RequestMine:Connect(function(player: Player, relX: number, relY: number, relZ: number)
		local character = player.Character
		if not character then
			return
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			return
		end

		local blockWorldPos = Vector3.new(relX, relY, relZ) + MiningConfig.WORLD_OFFSET
		local dist = (rootPart.Position - blockWorldPos).Magnitude
		if dist > MiningConfig.REACH_TOLERANCE * 2 then
			return
		end

		local cx, cy, cz = ChunkUtil.worldToChunk(relX, relY, relZ)
		local lx, ly, lz = ChunkUtil.worldToLocalBlock(relX, relY, relZ)
		local chunkKey = ChunkUtil.chunkKey(cx, cy, cz)
		local flatIdx = ChunkUtil.flatIndex(lx, ly, lz)

		local blockTypeId = WorldService:GetBlock(chunkKey, flatIdx)

		if blockTypeId == BlockType.Air or blockTypeId == BlockType.Bedrock then
			return
		end

		local blockDef = BlockRegistry.get(blockTypeId)
		if not blockDef or not blockDef.mineable then
			return
		end

		local tier = playerTiers[player] or 1
		if tier < blockDef.minTier then
			self.Client.MineResult:Fire(player, false, "tier_too_low", 0)
			return
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
				local dropName = blockDef.name
				for _, drop in ipairs(blockDef.drops) do
					if math.random() <= drop.chance then
						local dropDef = BlockRegistry.get(drop.id)
						if dropDef then
							dropName = dropDef.name
						end
					end
				end
				self.Client.MineResult:Fire(player, true, dropName, blockDef.xp)
			end
		else
			blockDamage[damageKey] = currentDamage
			local progress = currentDamage / hardness
			self.Client.MineResult:Fire(player, false, "progress", progress)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		playerTiers[player] = nil
	end)
end

function MiningService:SetPlayerTier(player: Player, tier: number)
	tier = math.clamp(tier, 1, #MiningConfig.TOOL_TIERS)
	playerTiers[player] = tier
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
