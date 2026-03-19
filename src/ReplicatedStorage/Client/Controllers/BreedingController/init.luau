--[[
	BreedingController — client-side breeding UI, egg display, and hatch timer.
	Scans for nearby creatures from other players, shows breed prompt.
	Eggs sit visibly in the world with a countdown billboard.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)
local VFXUtil = require(ReplicatedStorage.Shared.VFXUtil)

local Player = Players.LocalPlayer

local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	accent = Color3.fromRGB(100, 180, 255),
	text = Color3.fromRGB(230, 230, 240),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	egg = Color3.fromRGB(255, 235, 200),
	eggReady = Color3.fromRGB(100, 255, 150),
}

-- State
local _eggModels: { { model: Model, eggIndex: number } } = {}
local _eggTimers: { [number]: number } = {} -- eggIndex → remaining seconds (local countdown)
local _breedPrompt = nil
local _pendingBreed = false

---------- Egg Model ----------

-- Hardcoded egg shape (no LLM call needed)
local EGG_MODEL_DATA = {
	name = "Egg",
	category = "prop",
	parts = {
		{ name = "egg_body", shape = "Ball", position = { 0, 0.8, 0 }, size = { 1.5, 2, 1.5 }, rotation = { 0, 0, 0 }, color = { 255, 235, 200 }, material = "SmoothPlastic", transparency = 0 },
		{ name = "egg_spot1", shape = "Ball", position = { 0.3, 1.2, 0.4 }, size = { 0.4, 0.4, 0.4 }, rotation = { 0, 0, 0 }, color = { 255, 200, 150 }, material = "SmoothPlastic", transparency = 0 },
		{ name = "egg_spot2", shape = "Ball", position = { -0.4, 0.6, -0.3 }, size = { 0.35, 0.35, 0.35 }, rotation = { 0, 0, 0 }, color = { 255, 210, 160 }, material = "SmoothPlastic", transparency = 0 },
	},
	animation = "breathe",
}

local function formatTime(seconds: number): string
	if seconds <= 0 then
		return "Ready!"
	end
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	else
		return string.format("%ds", s)
	end
end

local function spawnEggInWorld(eggIndex: number, eggInfo: { [string]: any })
	local character = Player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Place egg near the player, offset to the side so it doesn't stack
	local offset = Vector3.new(3 + (eggIndex - 1) * 3, 0, 3)
	local eggPos = rootPart.Position + offset

	-- Build egg model
	local model = OrigamiBuilder.BuildModel(EGG_MODEL_DATA)
	if not model then return end

	model.Name = "Egg_" .. eggIndex
	model.Parent = workspace

	-- Place on ground
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, model }
	local ray = workspace:Raycast(eggPos + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), rayParams)
	local groundY = if ray then ray.Position.Y else rootPart.Position.Y - 3

	model:PivotTo(CFrame.new(eggPos.X, groundY + 1, eggPos.Z))

	-- Anchor egg parts so it stays in place
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
		end
	end

	-- Apply breathing animation
	OrigamiBuilder.ApplyAnimation(model, "breathe")

	-- Billboard with countdown timer
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EggTimer"
	billboard.Size = UDim2.new(0, 160, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 40

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = (eggInfo.parent1Name or "?") .. " x " .. (eggInfo.parent2Name or "?")
	nameLabel.TextColor3 = COLORS.egg
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboard

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0, 22)
	timerLabel.Position = UDim2.fromOffset(0, 20)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = formatTime(eggInfo.remainingSeconds or 0)
	timerLabel.TextColor3 = if (eggInfo.remainingSeconds or 0) <= 0 then COLORS.eggReady else COLORS.text
	timerLabel.TextStrokeTransparency = 0.5
	timerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	timerLabel.TextSize = 16
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = billboard

	local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if target then
		billboard.Adornee = target
		billboard.Parent = target
	end

	-- Hatch prompt (only when ready)
	if eggInfo.ready then
		local hatchPrompt = Instance.new("ProximityPrompt")
		hatchPrompt.ObjectText = "Egg"
		hatchPrompt.ActionText = "Hatch!"
		hatchPrompt.HoldDuration = 1
		hatchPrompt.MaxActivationDistance = 15
		hatchPrompt.RequiresLineOfSight = false
		hatchPrompt.Parent = target

		hatchPrompt.Triggered:Connect(function()
			hatchEgg(eggIndex, model)
		end)
	end

	_eggTimers[eggIndex] = eggInfo.remainingSeconds or 0
	table.insert(_eggModels, { model = model, eggIndex = eggIndex })
end

function hatchEgg(eggIndex: number, eggModel: Model?)
	task.spawn(function()
		local BreedingService = Knit.GetService("BreedingService")
		local result = BreedingService:HatchEgg(eggIndex):await()

		if result and result.success and result.offspringData then
			-- Hatch VFX
			if eggModel and eggModel.Parent then
				local eggPos = eggModel:GetPivot().Position
				VFXUtil.sparkle(eggPos, COLORS.eggReady, 30, 2)
				VFXUtil.risingText(eggPos + Vector3.new(0, 2, 0), "Hatched!", COLORS.success)
				eggModel:Destroy()
			end

			-- Remove from tracking
			for i, entry in ipairs(_eggModels) do
				if entry.eggIndex == eggIndex then
					table.remove(_eggModels, i)
					break
				end
			end

			-- Spawn the offspring creature
			local builtModel = OrigamiBuilder.BuildModel(result.offspringData)
			if builtModel then
				local CreatorController = Knit.GetController("CreatorController")
				-- Place where the egg was
				builtModel.Parent = workspace
				local character = Player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local pos = rootPart.Position + rootPart.CFrame.LookVector * 8
					builtModel:PivotTo(CFrame.new(pos.X, rootPart.Position.Y, pos.Z))
				end

				local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
				CreatureAI.Start(builtModel, result.offspringData, builtModel:GetPivot().Position, { builtModel, character })
			end
		end
	end)
end

local function clearEggs()
	for _, entry in ipairs(_eggModels) do
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
	end
	_eggModels = {}
end

local function refreshEggs()
	clearEggs()

	task.spawn(function()
		local BreedingService = Knit.GetService("BreedingService")
		local success, eggs = BreedingService:CheckEggs():await()

		if not success or type(eggs) ~= "table" then return end
		for _, eggInfo in ipairs(eggs) do
			spawnEggInWorld(eggInfo.index, eggInfo)
		end
	end)
end

local function startTimerLoop()
	-- Local 1-second countdown (no server calls)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, entry in ipairs(_eggModels) do
				if entry.model and entry.model.Parent then
					local remaining = _eggTimers[entry.eggIndex] or 0
					remaining = math.max(0, remaining - 1)
					_eggTimers[entry.eggIndex] = remaining

					local billboard = entry.model:FindFirstChild("EggTimer", true)
					if billboard then
						local timerLabel = billboard:FindFirstChild("TimerLabel")
						if timerLabel and timerLabel:IsA("TextLabel") then
							timerLabel.Text = formatTime(remaining)
							timerLabel.TextColor3 = if remaining <= 0 then COLORS.eggReady else COLORS.text

							-- Add hatch prompt when timer hits zero
							if remaining <= 0 then
								local target = entry.model.PrimaryPart or entry.model:FindFirstChildWhichIsA("BasePart")
								if target and not target:FindFirstChildOfClass("ProximityPrompt") then
									local hatchPrompt = Instance.new("ProximityPrompt")
									hatchPrompt.ObjectText = "Egg"
									hatchPrompt.ActionText = "Hatch!"
									hatchPrompt.HoldDuration = 1
									hatchPrompt.MaxActivationDistance = 15
									hatchPrompt.RequiresLineOfSight = false
									hatchPrompt.Parent = target

									hatchPrompt.Triggered:Connect(function()
										hatchEgg(entry.eggIndex, entry.model)
									end)
								end
							end
						end
					end
				end
			end
		end
	end)

	-- Server sync every 30s (corrects drift)
	task.spawn(function()
		while true do
			task.wait(30)
			if #_eggModels == 0 then continue end

			local BreedingService = Knit.GetService("BreedingService")
			local ok, eggs = BreedingService:CheckEggs():await()
			if not ok or type(eggs) ~= "table" then continue end
			for _, eggInfo in ipairs(eggs) do
				_eggTimers[eggInfo.index] = eggInfo.remainingSeconds or 0
			end
		end
	end)
end

---------- Breed Proximity ----------

local function startBreedProximityLoop()
	task.spawn(function()
		while true do
			task.wait(2) -- 0.5Hz — proximity check doesn't need to be fast

			if _pendingBreed then continue end

			local character = Player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			-- Check if any other player's creature is near our creature
			-- We look for models with OwnerUserId attribute set to other players
			local hasNearbyBreedable = false

			for _, other in ipairs(Players:GetPlayers()) do
				if other == Player then continue end
				local otherChar = other.Character
				local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
				if not otherRoot then continue end
				if (rootPart.Position - otherRoot.Position).Magnitude <= 20 then
					hasNearbyBreedable = true
					break
				end
			end

			-- Show/hide breed prompt on our creatures
			-- For simplicity, add a ProximityPrompt to the first creature we own
			if hasNearbyBreedable and not _breedPrompt then
				-- Find our first creature model
				local CreatorController = Knit.GetController("CreatorController")
				-- We can't easily access _spawnedModels from here, so use workspace scan
				for _, child in ipairs(workspace:GetChildren()) do
					if child:IsA("Model") and child:GetAttribute("OwnerUserId") == Player.UserId then
						local target = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
						if target and not target:FindFirstChild("BreedPrompt") then
							local prompt = Instance.new("ProximityPrompt")
							prompt.Name = "BreedPrompt"
							prompt.ObjectText = child.Name
							prompt.ActionText = "Breed (2 Cranes)"
							prompt.HoldDuration = 0.5
							prompt.MaxActivationDistance = 15
							prompt.RequiresLineOfSight = false
							prompt.Parent = target
							_breedPrompt = prompt

							prompt.Triggered:Connect(function()
								_pendingBreed = true
								task.spawn(function()
									local BreedingService = Knit.GetService("BreedingService")
									local creatureName = child.Name
									local billboard = child:FindFirstChild("NameLabel", true)
									if billboard then
										local lbl = billboard:FindFirstChildOfClass("TextLabel")
										if lbl then creatureName = lbl.Text end
									end

									local result = BreedingService:RequestBreed(creatureName):await()

									if result and result.success then
										if result.matched then
											-- Egg created! Refresh eggs in world
											refreshEggs()
										end
										-- If not matched, we're waiting
									end
									_pendingBreed = false
								end)
							end)
							break
						end
					end
				end
			elseif not hasNearbyBreedable and _breedPrompt then
				-- Remove breed prompt
				if _breedPrompt.Parent then
					_breedPrompt:Destroy()
				end
				_breedPrompt = nil
			end
		end
	end)
end

---------- Lifecycle ----------

local BreedingController = Knit.CreateController({ Name = "BreedingController" })

function BreedingController:KnitInit() end

function BreedingController:KnitStart()
	-- Spawn existing eggs on join
	task.delay(3, function()
		refreshEggs()
	end)

	-- Start loops
	startTimerLoop()
	startBreedProximityLoop()
end

return BreedingController
