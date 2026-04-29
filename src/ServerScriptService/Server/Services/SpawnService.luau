--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)

--[=[
	@class SpawnService
	Handles player spawning on the procedural terrain surface.
]=]
local SpawnService = Knit.CreateService({
	Name = "SpawnService",
	Client = {},
})

local WorldService

-- WorldGenModule.getSpawnPosition returns Y = top_of_surface_block + BLOCK_SIZE
-- (i.e. one block of headroom above the visible ground), so to put the
-- platform's top FLUSH with the visible terrain we sink it one full block.
-- PLATFORM_LIFT subtracts BLOCK_SIZE plus half the platform thickness so:
--   platform_top_Y == top_of_surface_block (visible ground level)
-- Slight overlap into the surface block is unavoidable but the platform
-- bottom is inside opaque terrain so it's not visible.
-- Spawn-clear radius in WorldGenModule already keeps trees away.
local BLOCK_SIZE = 5
local PLATFORM_THICKNESS = 1
local PLATFORM_LIFT = -BLOCK_SIZE - PLATFORM_THICKNESS / 2 -- -5.5
-- Platform footprint (big enough to catch a drifting spawn while chunks load)
local PLATFORM_SIZE = Vector3.new(24, PLATFORM_THICKNESS, 24)

function SpawnService:KnitInit() end

function SpawnService:KnitStart()
	WorldService = Knit.GetService("WorldService")

	local seed = WorldService:GetSeed()
	local surfacePos = WorldGenModule.getSpawnPosition(seed)
	-- Lift platform high above terrain so trees / structures can't poke
	-- through it, and so the player lands on it even before nearby chunks
	-- stream in.
	local platformPos = Vector3.new(surfacePos.X, surfacePos.Y + PLATFORM_LIFT, surfacePos.Z)
	-- Where the player's feet should end up — just above the platform top.
	local standPos = platformPos + Vector3.new(0, PLATFORM_SIZE.Y * 0.5 + 3, 0)

	-- Make sure falling to -inf doesn't insta-kill during chunk streaming.
	-- Roblox's default FallenPartsDestroyHeight can wipe a character before
	-- chunks load if the spawn briefly overlaps empty space.
	-- selene: allow(incorrect_standard_library_use)
	pcall(function()
		(workspace :: any).FallenPartsDestroyHeight = -5000
	end)

	-- Create a large, elevated spawn platform at the terrain surface
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		spawnLocation.Size = PLATFORM_SIZE
		spawnLocation.Position = platformPos
		spawnLocation.Anchored = true
		spawnLocation.CanCollide = true
	else
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Size = PLATFORM_SIZE
		spawnLocation.Position = platformPos
		spawnLocation.Anchored = true
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.Color = Color3.fromRGB(245, 235, 220) -- paper white
		spawnLocation.TopSurface = Enum.SurfaceType.Smooth
		spawnLocation.CanCollide = true
		spawnLocation.Parent = workspace
	end
	spawnLocation.Name = "SpawnPlatform"

	-- Teleport every newly spawned character onto the platform. Using
	-- CharacterAdded + an immediate CFrame snap beats any "spawned at 0,0,0
	-- and fell through empty world" race before chunks stream in.
	local function placeOnPlatform(character: Model)
		local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if not rootPart then
			return
		end
		rootPart.CFrame = CFrame.new(standPos)
		-- Nudge once more on the next frame in case the default spawn
		-- system repositions the character after ours.
		task.defer(function()
			if rootPart.Parent then
				rootPart.CFrame = CFrame.new(standPos)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(placeOnPlatform)
		if player.Character then
			placeOnPlatform(player.Character)
		end
	end)

	-- Handle any players already in the server
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(placeOnPlatform)
		if player.Character then
			placeOnPlatform(player.Character)
		end
	end
end

return SpawnService
