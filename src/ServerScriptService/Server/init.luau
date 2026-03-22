local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local vServerStatus = Instance.new("StringValue")
vServerStatus.Name = "ServerStatus"
vServerStatus.Value = "Loading"
vServerStatus.Parent = ReplicatedStorage

local Server = {}

function Server:Main()
	self:_setupWorld()
	self:Start()
end

function Server:_setupWorld()
	-- Terrain disabled for now (TerrainBuilder.Build() available when ready)
	-- local TerrainBuilder = require(ReplicatedStorage.Shared.TerrainBuilder)
	-- TerrainBuilder.Build()

	-- Spawn location (flat baseplate)
	if not workspace:FindFirstChildOfClass("SpawnLocation") then
		local spawn = Instance.new("SpawnLocation")
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Position = Vector3.new(0, 1, 0)
		spawn.Anchored = true
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.CanCollide = true
		spawn.Parent = workspace
	end

	-- Simple flat baseplate
	if not workspace:FindFirstChild("Baseplate") then
		local base = Instance.new("Part")
		base.Name = "Baseplate"
		base.Size = Vector3.new(768, 4, 768)
		base.Position = Vector3.new(0, -2, 0)
		base.Anchored = true
		base.Material = Enum.Material.SmoothPlastic
		base.Color = Color3.fromRGB(91, 154, 76) -- green
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.Parent = workspace
	end

	-- Competition grid disabled — replaced by shopkeeper NPCs
	-- Shopkeepers are spawned by ShopKeeperService:KnitStart()
	-- local CompetitionGrid = require(ReplicatedStorage.Shared.CompetitionGrid)
	-- CompetitionGrid.Build()

	-- Lighting — warm afternoon light for paper aesthetic
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(160, 155, 145)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 155, 145)
end

function Server:_loadComponentsIn(container: Instance)
	for _, instance in container:GetDescendants() do
		if instance:IsA("ModuleScript") and instance.Name:sub(#instance.Name - 8, #instance.Name) == "Component" then
			require(instance)
		end
	end
end

function Server:Start()
	Knit.AddServices(script.Services)
	return Knit:Start()
		:andThenCall(self._loadComponentsIn, self, script.Components)
		:andThenCall(self._loadComponentsIn, self, ReplicatedStorage.Shared.Components)
		:andThen(function()
			vServerStatus.Value = "Started"
		end)
		:catch(function(msg: string)
			warn(msg)
			vServerStatus.Value = "Crashed"
		end)
end

return Server
