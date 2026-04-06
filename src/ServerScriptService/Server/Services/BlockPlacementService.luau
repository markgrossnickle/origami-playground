--[[
	BlockPlacementService — server-side validation and placement of blocks
	in the voxel world. Deducts materials from MiningInventory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local MAX_PLACE_DISTANCE = 20

-- Reverse mapping: inventory itemId → BlockType id for world placement
local ITEM_TO_BLOCK: { [string]: number } = {
	paper_scrap = BlockType.Paper,
	cardboard = BlockType.Cardboard,
	wood = BlockType.Wood,
	dried_pulp = BlockType.DriedPulp,
	compressed_pulp = BlockType.CompressedPulp,
	clay_chunk = BlockType.Clay,
	folded_stone = BlockType.FoldedStone,
	quartz_shard = BlockType.PaperQuartz,
	paper_crystal = BlockType.PaperCrystal,
	ink_stone = BlockType.InkStone,
	origami_rock = BlockType.OrigamiRock,
	gem_fragment = BlockType.GemFragment,
	foil_ore = BlockType.FoilOre,
	ruby_paper = BlockType.RubyPaper,
	crystal_shard = BlockType.CrystalBlock,
	foil_sheet = BlockType.FoilSheet,
	metal_origami = BlockType.MetalOrigami,
	sapphire_crystal = BlockType.SapphireCrystal,
	void_stone = BlockType.VoidStone,
	dark_paper = BlockType.DarkPaper,
	shadow_fold = BlockType.ShadowFold,
	void_crystal = BlockType.VoidCrystal,
	prismatic_shard = BlockType.PrismaticBlock,
	core_fragment = BlockType.CoreFragment,
	rainbow_paper = BlockType.RainbowPaper,
}

local BlockPlacementService = Knit.CreateService({
	Name = "BlockPlacementService",
	Client = {
		PlacementResult = Knit.CreateSignal(),
	},
})

local WorldService
local PlayerDataService

-- Rate limit: one placement per player per 0.15s
local _lastPlaceTime: { [Player]: number } = {}
local PLACE_COOLDOWN = 0.15

function BlockPlacementService.Client:PlaceBlock(player: Player, chunkKey: string, flatIndex: number, itemId: string)
	-- Type validation
	if type(chunkKey) ~= "string" or type(flatIndex) ~= "number" or type(itemId) ~= "string" then
		return { success = false, error = "invalid_args" }
	end

	-- Validate flatIndex
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK or flatIndex ~= math.floor(flatIndex) then
		return { success = false, error = "invalid_index" }
	end

	-- Validate chunkKey format
	local parts = string.split(chunkKey, ",")
	if #parts ~= 3 or not tonumber(parts[1]) or not tonumber(parts[2]) or not tonumber(parts[3]) then
		return { success = false, error = "invalid_chunk" }
	end

	-- Validate item is placeable
	local blockTypeId = ITEM_TO_BLOCK[itemId]
	if not blockTypeId then
		return { success = false, error = "not_placeable" }
	end

	-- Rate limit
	local now = os.clock()
	local last = _lastPlaceTime[player]
	if last and (now - last) < PLACE_COOLDOWN then
		return { success = false, error = "cooldown" }
	end

	-- Range check: player must be within MAX_PLACE_DISTANCE of target block
	local character = player.Character
	if not character then
		return { success = false, error = "no_character" }
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return { success = false, error = "no_character" }
	end

	local cx = tonumber(parts[1]) :: number
	local cy = tonumber(parts[2]) :: number
	local cz = tonumber(parts[3]) :: number
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local blockPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)
	local dist = (rootPart.Position - blockPos).Magnitude
	if dist > MAX_PLACE_DISTANCE + BLOCK_SIZE then
		return { success = false, error = "too_far" }
	end

	-- Check player is subscribed to this chunk
	if not WorldService:IsSubscribed(player, chunkKey) then
		return { success = false, error = "not_subscribed" }
	end

	-- Check target position is air
	local currentBlock = WorldService:GetBlock(chunkKey, flatIndex)
	if currentBlock ~= BlockType.Air then
		return { success = false, error = "occupied" }
	end

	-- Check inventory
	local invCount = PlayerDataService:Read(player, { "MiningInventory", itemId }) or 0
	if invCount < 1 then
		return { success = false, error = "no_material" }
	end

	-- Deduct material
	PlayerDataService:Write(player, { "MiningInventory", itemId }, invCount - 1)
	_lastPlaceTime[player] = now

	-- Place block in voxel world (broadcasts BlockUpdate to subscribers)
	WorldService:SetBlock(chunkKey, flatIndex, blockTypeId)

	return { success = true }
end

function BlockPlacementService:KnitInit() end

function BlockPlacementService:KnitStart()
	WorldService = Knit.GetService("WorldService")
	PlayerDataService = Knit.GetService("PlayerDataService")

	-- Clean up rate limit entries on leave
	Players.PlayerRemoving:Connect(function(player: Player)
		_lastPlaceTime[player] = nil
	end)
end

return BlockPlacementService
