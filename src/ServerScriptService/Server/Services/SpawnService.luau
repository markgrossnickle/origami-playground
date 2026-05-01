--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

--[=[
	@class SpawnService
	Region-aware spawn flow.

	* On first join (OwnedRegionId == "") asks RegionService to claim a free
	  slot and computes a HomePoint at the slot's surface; persists both to
	  the player's profile, then teleports them home.
	* On subsequent joins, teleports the character to the persisted HomePoint.
	* Falls back to the central Hearth platform when no region is assigned.
]=]
local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {
		RegionAssigned = Knit.CreateSignal(), -- (slotId: string, homePoint: {x,y,z})
	},
})

local WorldService
local PlayerDataService
local RegionService

-- Hearth platform: a fixed-position floating pad at the world origin, high
-- enough to be above the maximum possible terrain height. Players spawn here
-- IMMEDIATELY without waiting for the heightmap to initialize (which can take
-- 30+ seconds at worldRadius=70). World terrain streams in below them; they
-- jump off the pad to land on the ground once it's there.
--
-- Y=100 is comfortably above max surface (seaLevel=20 + maxElev≈50 = ~70).
local PLATFORM_THICKNESS = 1
local PLATFORM_SIZE = Vector3.new(24, PLATFORM_THICKNESS, 24)
local HEARTH_PLATFORM_Y = 100

local _hearthStandPos: Vector3 = Vector3.new(0, HEARTH_PLATFORM_Y + PLATFORM_SIZE.Y * 0.5 + 3, 0)

-- Position the SpawnLocation NOW (at module load), before Knit:Start has even
-- started. This way every player who joins lands on the Hearth platform —
-- no autoload-gating, no race with heightmap init.
do
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		spawnLocation.Size = PLATFORM_SIZE
		spawnLocation.Position = Vector3.new(0, HEARTH_PLATFORM_Y, 0)
		spawnLocation.Anchored = true
		spawnLocation.CanCollide = true
	else
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Size = PLATFORM_SIZE
		spawnLocation.Position = Vector3.new(0, HEARTH_PLATFORM_Y, 0)
		spawnLocation.Anchored = true
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.Color = Color3.fromRGB(245, 235, 220)
		spawnLocation.TopSurface = Enum.SurfaceType.Smooth
		spawnLocation.CanCollide = true
		spawnLocation.Parent = workspace
	end
	spawnLocation.Name = "SpawnPlatform"

	-- selene: allow(incorrect_standard_library_use)
	pcall(function()
		(workspace :: any).FallenPartsDestroyHeight = -5000
	end)
end

local function _vec3(p: { x: number, y: number, z: number }): Vector3
	return Vector3.new(p.x, p.y, p.z)
end

local function _isZeroHome(p: { x: number, y: number, z: number }): boolean
	return p.x == 0 and p.y == 0 and p.z == 0
end

local function _homePointFromProfile(player: Player): Vector3?
	if PlayerDataService == nil then
		return nil
	end
	local slotId = PlayerDataService:Read(player, { "OwnedRegionId" })
	if type(slotId) ~= "string" or slotId == "" then
		return nil
	end
	local home = PlayerDataService:Read(player, { "RegionHomePoint" })
	if type(home) ~= "table" then
		return nil
	end
	if _isZeroHome(home) then
		return nil
	end
	return _vec3(home)
end

local function _placeOnPosition(character: Model, pos: Vector3)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not rootPart then
		return
	end
	rootPart.CFrame = CFrame.new(pos)
	-- Re-snap on the next frame in case the default spawn system reposes us.
	task.defer(function()
		if rootPart.Parent then
			rootPart.CFrame = CFrame.new(pos)
		end
	end)
end

local function placeOnPlatform(player: Player, character: Model)
	-- ALWAYS spawn at the Hearth (world origin platform) for now.
	--
	-- Auto-teleport to RegionHomePoint is disabled: chunks at the slot
	-- centers (R=4000) often aren't streamed when the player teleports
	-- there, AND the slot ring sits inside the island falloff zone where
	-- terrain is suppressed to near sea level. Combined effect was a
	-- death loop — fall through ungenerated geometry → hit
	-- FallenPartsDestroyHeight → respawn at same bad home → repeat.
	--
	-- Hearth is at world origin where chunks are always loaded, so this
	-- is safe. Players walk to their region (visible via the slot pillars
	-- placed by LandmarkService). Phase 6 will re-enable auto-teleport
	-- once we have proper chunk-preload-then-teleport plumbing.
	local _ = player
	_placeOnPosition(character, _hearthStandPos)
end

local function _computeHomePointForSlot(seed: number, slotId: string): Vector3?
	local center = RegionConfig.getSlotCenter(slotId)
	if center == nil then
		return nil
	end
	local surfaceY = WorldGenModule.getSurfaceWorldY(seed, center.x, center.z)
	-- Place feet a few studs above the surface block to avoid embedding.
	return Vector3.new(center.x, surfaceY + 3, center.z)
end

local function _assignRegionForFirstTime(player: Player, seed: number)
	if PlayerDataService == nil or RegionService == nil then
		return
	end

	-- Wait for the profile to load before reading/writing.
	local ok, _ = PlayerDataService:WaitForProfile(player):await()
	if not ok or not player.Parent then
		return
	end

	local existing = PlayerDataService:Read(player, { "OwnedRegionId" })
	if type(existing) == "string" and existing ~= "" then
		-- Already assigned; ensure cache reflects current ownership and exit.
		return
	end

	local slotId = RegionService:ClaimFreeSlotForPlayer(player)
	if slotId == nil then
		warn(`[SpawnService] No free region slot available for {player.Name}`)
		return
	end

	local home = _computeHomePointForSlot(seed, slotId)
	if home == nil then
		warn(`[SpawnService] Could not compute home point for slot {slotId}`)
		return
	end

	if not player.Parent then
		return
	end

	PlayerDataService:Write(player, { "OwnedRegionId" }, slotId)
	PlayerDataService:Write(player, { "RegionHomePoint" }, { x = home.X, y = home.Y, z = home.Z })

	SpawnService.Client.RegionAssigned:Fire(player, slotId, { x = home.X, y = home.Y, z = home.Z })

	-- Auto-teleport to home is intentionally NOT done here for the same
	-- chunk-not-streamed / falloff-terrain reason as placeOnPlatform.
	-- Player stays on the Hearth platform after first claim; they can
	-- walk to their region using the visible slot pillars.
end

-- Tracks players already bound by bindPlayer to avoid the PlayerAdded +
-- Players:GetPlayers() race in KnitStart: a player joining between Connect
-- and the loop iteration would otherwise be bound twice — duplicate
-- CharacterAdded connection, duplicate first-join claim attempt, double
-- RegionAssigned fire.
local _boundPlayers: { [Player]: boolean } = {}

local function bindPlayer(player: Player, seed: number)
	if _boundPlayers[player] then
		return
	end
	_boundPlayers[player] = true

	player.CharacterAdded:Connect(function(character)
		placeOnPlatform(player, character)
	end)
	if player.Character then
		placeOnPlatform(player, player.Character)
	end
	task.spawn(function()
		_assignRegionForFirstTime(player, seed)
	end)
end

-- Clear the bound flag so a rejoining player gets a fresh bind.
Players.PlayerRemoving:Connect(function(player)
	_boundPlayers[player] = nil
end)

function SpawnService:KnitInit() end

function SpawnService:KnitStart()
	WorldService = Knit.GetService("WorldService")
	PlayerDataService = Knit.GetService("PlayerDataService")
	RegionService = Knit.GetService("RegionService")

	-- Platform is already positioned at module-load time; no heightmap call
	-- needed here. seed is still useful for region-claim home computation.
	local seed = WorldService:GetSeed()

	Players.PlayerAdded:Connect(function(player)
		bindPlayer(player, seed)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player, seed)
	end
end

return SpawnService
