--[[
	BlockPlacementService — server-side validation and placement of blocks
	in the voxel world. Deducts materials from MiningInventory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local PlaceableBlocks = require(ReplicatedStorage.Shared.PlaceableBlocks)
local MaterialTiers = require(ReplicatedStorage.Shared.MaterialTiers)
local ZoneRegistry = require(ReplicatedStorage.Shared.ZoneRegistry)
local ZonePermissions = require(ReplicatedStorage.Shared.ZonePermissions)

local BLOCKS_PER_CHUNK = ChunkUtil.BLOCKS_PER_CHUNK
local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local MAX_PLACE_DISTANCE = 20

local function _placementNamespace(itemId: string): string
	local role = MaterialTiers.getRole(itemId)
	if role == "bulk" or role == "ore" then
		return role
	end
	return "misc"
end

local BlockPlacementService = Knit.CreateService({
	Name = "BlockPlacementService",
	Client = {
		PlacementResult = Knit.CreateSignal(),
	},
})

local WorldService
local PlayerDataService
local RegionService

-- Rate limit: one placement per player per 0.15s
local _lastPlaceTime: { [Player]: number } = {}
local PLACE_COOLDOWN = 0.15

function BlockPlacementService.Client:PlaceBlock(player: Player, chunkKey: number, flatIndex: number, itemId: string)
	-- Type validation
	if type(chunkKey) ~= "number" or type(flatIndex) ~= "number" or type(itemId) ~= "string" then
		return { success = false, error = "invalid_args" }
	end

	-- Validate flatIndex
	if flatIndex < 0 or flatIndex >= BLOCKS_PER_CHUNK or flatIndex ~= math.floor(flatIndex) then
		return { success = false, error = "invalid_index" }
	end

	-- Validate chunkKey is a non-negative integer (packed key space)
	if chunkKey ~= math.floor(chunkKey) or chunkKey < 0 then
		return { success = false, error = "invalid_chunk" }
	end

	-- Validate item is placeable
	local blockTypeId = PlaceableBlocks.getBlockType(itemId)
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

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
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

	local zone = ZoneRegistry.getZone(blockPos.X, blockPos.Z)
	local isOwner = false
	if zone == "regions" then
		local slotId = ZoneRegistry.getRegionAt(blockPos.X, blockPos.Z)
		if slotId and RegionService and RegionService:GetOwnerOf(slotId) == player.UserId then
			isOwner = true
		end
	end
	local decision = ZonePermissions.canAct(zone, "place", isOwner)
	if not decision.allowed then
		return { success = false, error = decision.reason or "zone_locked" }
	end

	-- Check target position is air
	local currentBlock = WorldService:GetBlock(chunkKey, flatIndex)
	if currentBlock ~= BlockType.Air then
		return { success = false, error = "occupied" }
	end

	-- Check inventory
	local namespace = _placementNamespace(itemId)
	local invCount = PlayerDataService:Read(player, { "MiningInventory", namespace, itemId }) or 0
	if invCount < 1 then
		return { success = false, error = "no_material" }
	end

	-- Deduct material
	PlayerDataService:Write(player, { "MiningInventory", namespace, itemId }, invCount - 1)
	_lastPlaceTime[player] = now

	-- Place block in voxel world (broadcasts BlockUpdate to subscribers)
	WorldService:SetBlock(chunkKey, flatIndex, blockTypeId)

	return { success = true }
end

function BlockPlacementService:KnitInit() end

function BlockPlacementService:KnitStart()
	WorldService = Knit.GetService("WorldService")
	PlayerDataService = Knit.GetService("PlayerDataService")
	RegionService = Knit.GetService("RegionService")

	-- Clean up rate limit entries on leave
	Players.PlayerRemoving:Connect(function(player: Player)
		_lastPlaceTime[player] = nil
	end)
end

return BlockPlacementService
