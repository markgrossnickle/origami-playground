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

function SpawnService:KnitInit()
	-- Nothing to init
end

function SpawnService:KnitStart()
	WorldService = Knit.GetService("WorldService")

	local seed = WorldService:GetSeed()
	local spawnPos = WorldGenModule.getSpawnPosition(seed)

	-- Create a spawn platform at the terrain surface
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		spawnLocation.Position = Vector3.new(spawnPos.X, spawnPos.Y - 1, spawnPos.Z)
	else
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Size = Vector3.new(8, 1, 8)
		spawnLocation.Position = Vector3.new(spawnPos.X, spawnPos.Y - 1, spawnPos.Z)
		spawnLocation.Anchored = true
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.Color = Color3.fromRGB(245, 235, 220) -- paper white
		spawnLocation.TopSurface = Enum.SurfaceType.Smooth
		spawnLocation.CanCollide = true
		spawnLocation.Parent = workspace
	end

	-- Teleport players who spawn at default position to surface
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Wait for physics to settle
			task.defer(function()
				if not player.Parent then
					return
				end
				local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
				if not rootPart then
					return
				end
				-- If player is near default origin (0,0,0), teleport to spawn
				if rootPart.Position.Y < 5 and math.abs(rootPart.Position.X) < 20 and math.abs(rootPart.Position.Z) < 20 then
					rootPart.CFrame = CFrame.new(spawnPos)
				end
			end)
		end)
	end)
end

return SpawnService
