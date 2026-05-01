--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

--[=[
	@class SpawnService
	Region-aware spawn flow.

	* Every CharacterAdded: place the player on the central Hearth platform
	  immediately (no race with heightmap init).
	* If the player owns a region, kick off a background task that
	  pre-subscribes the chunks at the inner edge of their slot, waits for
	  those chunks to be ready, then teleports the character to that edge
	  point. This avoids the previous death-loop where teleporting to
	  ungenerated geometry dropped the player below FallenPartsDestroyHeight.
	* On first join (OwnedRegionId == "") asks RegionService to claim a free
	  slot and persists both the slotId and a HomePoint at the slot's surface,
	  then runs the same edge-teleport.
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

-- After spawning on the platform, owners get teleported to the inner edge
-- of their slot — the side closest to the Hearth. This is the natural
-- "front door" of their region: easy to wander out into the Hearth or
-- deeper into their own land. We pull the spawn point a few studs INSIDE
-- the slot boundary so zone permission checks see them as inside the
-- region (not the boundary line).
local EDGE_INSET = 16

-- How long to wait after pre-subscribing the edge chunks before yanking the
-- character there. Server side, Subscribe yields until the chunk exists.
-- Client side it still has to receive the ChunkData message and render
-- meshes — this delay covers that round trip + a render frame.
local EDGE_TELEPORT_DELAY = 2.5

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

-- Compute a "front door" point at the inner edge of the slot — the boundary
-- side that faces the Hearth. We push EDGE_INSET studs back into the slot
-- so zone checks classify the position as "regions" rather than ambiguous.
local function _computeRegionEdgePoint(seed: number, slotId: string): Vector3?
	local center = RegionConfig.getSlotCenter(slotId)
	if center == nil then
		return nil
	end
	local mag = math.sqrt(center.x * center.x + center.z * center.z)
	if mag <= 0 then
		return nil
	end
	-- Unit vector from slot center pointing back toward the Hearth.
	local towardHearthX = -center.x / mag
	local towardHearthZ = -center.z / mag
	-- Walk SLOT_HALF_EDGE studs from the center toward the hearth, then
	-- step EDGE_INSET back inside the slot.
	local edgeX = center.x + towardHearthX * (RegionConfig.SLOT_HALF_EDGE - EDGE_INSET)
	local edgeZ = center.z + towardHearthZ * (RegionConfig.SLOT_HALF_EDGE - EDGE_INSET)
	local surfaceY = WorldGenModule.getSurfaceWorldY(seed, edgeX, edgeZ)
	return Vector3.new(edgeX, surfaceY + 4, edgeZ)
end

-- Force-subscribe the chunks around `pos` so the player's client renders
-- terrain there before we teleport. Subscribe yields per-chunk on first call
-- (cold DataStore read), so this both warms the cache and pushes ChunkData
-- to the client. Subscribed chunks aren't tracked by ChunkStreamService's
-- requiredSet so its 0.5s poll won't unsubscribe them out from under us.
local function _preSubscribeChunksAtPosition(player: Player, pos: Vector3)
	if WorldService == nil then
		return
	end
	local pcx, pcy, pcz = ChunkUtil.worldToChunk(pos.X, pos.Y, pos.Z)
	for dx = -1, 1 do
		for dz = -1, 1 do
			-- Slightly more depth than height so the column under the
			-- player is solid before they land.
			for dy = -3, 1 do
				local cx, cy, cz = pcx + dx, pcy + dy, pcz + dz
				if ChunkUtil.isInMineBounds(cx, cz) then
					local key = ChunkUtil.chunkKey(cx, cy, cz)
					WorldService:Subscribe(player, key)
				end
			end
		end
	end
end

local function _scheduleEdgeTeleport(player: Player, slotId: string, seed: number)
	task.spawn(function()
		local edgePos = _computeRegionEdgePoint(seed, slotId)
		if edgePos == nil then
			warn(`[SpawnService] Could not compute edge point for slot {slotId}`)
			return
		end
		if not player.Parent then
			return
		end

		-- Pre-warm + subscribe the chunks the player is about to land in.
		-- Subscribe yields, so this can take a moment; we still pad the
		-- delay below for client-side render time.
		_preSubscribeChunksAtPosition(player, edgePos)

		task.wait(EDGE_TELEPORT_DELAY)
		if not player.Parent then
			return
		end
		local character = player.Character
		if not character or not character.Parent then
			return
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			return
		end

		-- Re-look up surface in case anything mutated; cheap.
		local refreshed = _computeRegionEdgePoint(seed, slotId)
		if refreshed then
			edgePos = refreshed
		end
		rootPart.CFrame = CFrame.new(edgePos)
	end)
end

-- Returns the slotId the player ends up owning (existing or freshly claimed),
-- or nil if assignment failed (e.g. all slots full).
local function _assignRegionForFirstTime(player: Player, seed: number): string?
	if PlayerDataService == nil or RegionService == nil then
		return nil
	end

	-- Wait for the profile to load before reading/writing.
	local ok, _ = PlayerDataService:WaitForProfile(player):await()
	if not ok or not player.Parent then
		return nil
	end

	local existing = PlayerDataService:Read(player, { "OwnedRegionId" })
	if type(existing) == "string" and existing ~= "" then
		return existing
	end

	local slotId = RegionService:ClaimFreeSlotForPlayer(player)
	if slotId == nil then
		warn(`[SpawnService] No free region slot available for {player.Name}`)
		return nil
	end

	local home = _computeHomePointForSlot(seed, slotId)
	if home == nil then
		warn(`[SpawnService] Could not compute home point for slot {slotId}`)
		return nil
	end

	if not player.Parent then
		return nil
	end

	PlayerDataService:Write(player, { "OwnedRegionId" }, slotId)
	PlayerDataService:Write(player, { "RegionHomePoint" }, { x = home.X, y = home.Y, z = home.Z })

	SpawnService.Client.RegionAssigned:Fire(player, slotId, { x = home.X, y = home.Y, z = home.Z })

	return slotId
end

local function _onCharacterSpawned(player: Player, character: Model, seed: number)
	-- Step 1: always land on the Hearth platform first. Immediate, no race.
	placeOnPlatform(player, character)

	-- Step 2: if we already know their region (returning player), schedule a
	-- background teleport to its inner edge.
	task.spawn(function()
		if PlayerDataService == nil then
			return
		end
		local ok, _ = PlayerDataService:WaitForProfile(player):await()
		if not ok or not player.Parent then
			return
		end
		local owned = PlayerDataService:Read(player, { "OwnedRegionId" })
		if type(owned) == "string" and owned ~= "" then
			_scheduleEdgeTeleport(player, owned, seed)
		end
	end)
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
		_onCharacterSpawned(player, character, seed)
	end)
	if player.Character then
		_onCharacterSpawned(player, player.Character, seed)
	end

	task.spawn(function()
		local slotId = _assignRegionForFirstTime(player, seed)
		-- For BRAND-NEW players _assignRegionForFirstTime fires
		-- RegionAssigned and we want to immediately teleport them to their
		-- new slot's edge. Returning players already had their teleport
		-- queued in _onCharacterSpawned; this is a no-op for them since
		-- _scheduleEdgeTeleport is idempotent enough — a second teleport
		-- to the same point is harmless.
		if slotId and player.Parent and player.Character then
			_scheduleEdgeTeleport(player, slotId, seed)
		end
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
