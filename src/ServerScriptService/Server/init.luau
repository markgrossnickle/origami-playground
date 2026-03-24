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

	-- Mining portal near spawn
	if not workspace:FindFirstChild("MiningPortal") then
		local portal = Instance.new("Model")
		portal.Name = "MiningPortal"

		-- Left pillar
		local leftPillar = Instance.new("Part")
		leftPillar.Name = "LeftPillar"
		leftPillar.Size = Vector3.new(2, 10, 2)
		leftPillar.Position = Vector3.new(20, 5, -15)
		leftPillar.Anchored = true
		leftPillar.Material = Enum.Material.SmoothPlastic
		leftPillar.Color = Color3.fromRGB(180, 150, 110)
		leftPillar.CastShadow = true
		leftPillar.Parent = portal

		-- Right pillar
		local rightPillar = Instance.new("Part")
		rightPillar.Name = "RightPillar"
		rightPillar.Size = Vector3.new(2, 10, 2)
		rightPillar.Position = Vector3.new(26, 5, -15)
		rightPillar.Anchored = true
		rightPillar.Material = Enum.Material.SmoothPlastic
		rightPillar.Color = Color3.fromRGB(180, 150, 110)
		rightPillar.CastShadow = true
		rightPillar.Parent = portal

		-- Top arch
		local arch = Instance.new("Part")
		arch.Name = "Arch"
		arch.Size = Vector3.new(8, 2, 2)
		arch.Position = Vector3.new(23, 11, -15)
		arch.Anchored = true
		arch.Material = Enum.Material.SmoothPlastic
		arch.Color = Color3.fromRGB(180, 150, 110)
		arch.CastShadow = true
		arch.Parent = portal

		-- Neon glow inside
		local glow = Instance.new("Part")
		glow.Name = "Glow"
		glow.Size = Vector3.new(4, 8, 0.5)
		glow.Position = Vector3.new(23, 5, -15)
		glow.Anchored = true
		glow.Material = Enum.Material.Neon
		glow.Color = Color3.fromRGB(120, 200, 255)
		glow.Transparency = 0.3
		glow.CanCollide = false
		glow.CastShadow = false
		glow.Parent = portal

		-- ProximityPrompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Enter Mine"
		prompt.ObjectText = "Mining World"
		prompt.MaxActivationDistance = 8
		prompt.HoldDuration = 0
		prompt.Parent = glow

		-- Label
		local billboardGui = Instance.new("BillboardGui")
		billboardGui.Size = UDim2.new(0, 200, 0, 50)
		billboardGui.StudsOffset = Vector3.new(0, 8, 0)
		billboardGui.AlwaysOnTop = true
		billboardGui.Parent = arch

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "Mining World"
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.5
		label.TextSize = 22
		label.Font = Enum.Font.GothamBold
		label.Parent = billboardGui

		portal.PrimaryPart = glow
		portal.Parent = workspace
	end

	-- Create MiningWorld folder
	if not workspace:FindFirstChild("MiningWorld") then
		local miningWorld = Instance.new("Folder")
		miningWorld.Name = "MiningWorld"
		miningWorld.Parent = workspace
	end

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
			-- Spawn demo showcase models
			local DemoShowcaseSpawner = require(ReplicatedStorage.Shared.DemoShowcaseSpawner)
			DemoShowcaseSpawner.Build()

			vServerStatus.Value = "Started"
		end)
		:catch(function(msg: string)
			warn(msg)
			vServerStatus.Value = "Crashed"
		end)
end

return Server
