local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local Player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Sounds
local _successSound = Instance.new("Sound")
_successSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
_successSound.Volume = 0.5
_successSound.Parent = SoundService

local _failSound = Instance.new("Sound")
_failSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
_failSound.Volume = 0.4
_failSound.Parent = SoundService

local PlayController = Knit.CreateController({
	Name = "PlayController",
})

-----------------------------------------------------------
-- Constants
-----------------------------------------------------------

local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(100, 180, 255),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	disabled = Color3.fromRGB(80, 80, 90),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	danger = Color3.fromRGB(200, 60, 60),
}

-----------------------------------------------------------
-- State
-----------------------------------------------------------

local _active = false
local _gui = nil
local _building = false

-- Placed models
local _placedModels: { Model } = {}
local _playFolder: Folder? = nil

-- Heartbeat connections for model behaviors
local _behaviorConns: { [Model]: { RBXScriptConnection } } = {}

-- UI elements
local _statusLabel: TextLabel? = nil
local _promptInput: TextBox? = nil
local _buildButton: TextButton? = nil
local _countLabel: TextLabel? = nil
local _clearButton: TextButton? = nil

-----------------------------------------------------------
-- Utility
-----------------------------------------------------------

local function setStatus(text: string, color: Color3?)
	if not _statusLabel then
		return
	end
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim
	task.delay(5, function()
		if _statusLabel and _statusLabel.Text == text then
			_statusLabel.Text = ""
		end
	end)
end

local function updateCount()
	if _countLabel then
		_countLabel.Text = "Objects: " .. #_placedModels
	end
end

-----------------------------------------------------------
-- Placement (raycast from mouse)
-----------------------------------------------------------

local function getPlacementCFrame(): CFrame
	local mouse = Player:GetMouse()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local excludeList = {}
	if Player.Character then
		table.insert(excludeList, Player.Character)
	end
	if _playFolder then
		table.insert(excludeList, _playFolder)
	end
	raycastParams.FilterDescendantsInstances = excludeList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	if result then
		return CFrame.new(result.Position + Vector3.new(0, 0.5, 0))
	end
	-- Fallback: place 30 studs in front of camera
	return CFrame.new(camera.CFrame.Position + camera.CFrame.LookVector * 30)
end

-----------------------------------------------------------
-- Behavior wiring (LLM-driven via attributes)
-----------------------------------------------------------

local function wireBehaviors(model: Model)
	local conns: { RBXScriptConnection } = {}

	-- Force all parts collidable so players interact physically
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = true
		end
	end

	-- Check model-level attributes for behaviors
	local bounceForce = model:GetAttribute("BounceForce")
	local launchForce = model:GetAttribute("LaunchForce")
	local launchDirection = model:GetAttribute("LaunchDirection")
	local spinSpeed = model:GetAttribute("SpinSpeed")
	local slideFriction = model:GetAttribute("SlideFriction")
	local seatHeight = model:GetAttribute("SeatHeight")

	-- Bounce: any part touched applies upward velocity
	if bounceForce then
		local force = tonumber(bounceForce) or 80
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local conn = part.Touched:Connect(function(hit)
					local character = hit.Parent
					if not character then
						return
					end
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					local rootPart = character:FindFirstChild("HumanoidRootPart")
					if humanoid and rootPart then
						rootPart.AssemblyLinearVelocity = Vector3.new(
							rootPart.AssemblyLinearVelocity.X,
							force,
							rootPart.AssemblyLinearVelocity.Z
						)
					end
				end)
				table.insert(conns, conn)
			end
		end
	end

	-- Launch: touched applies velocity in a direction
	if launchForce then
		local force = tonumber(launchForce) or 100
		local dir: Vector3
		if launchDirection and typeof(launchDirection) == "Vector3" then
			dir = launchDirection.Unit
		elseif model.PrimaryPart then
			dir = (model.PrimaryPart.CFrame.LookVector + Vector3.new(0, 0.5, 0)).Unit
		else
			dir = Vector3.new(0, 0.5, -1).Unit
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local conn = part.Touched:Connect(function(hit)
					local character = hit.Parent
					if not character then
						return
					end
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					local rootPart = character:FindFirstChild("HumanoidRootPart")
					if humanoid and rootPart then
						rootPart.AssemblyLinearVelocity = dir * force
					end
				end)
				table.insert(conns, conn)
			end
		end
	end

	-- Spin: continuous Y-axis rotation
	if spinSpeed then
		local speed = tonumber(spinSpeed) or 60
		local conn = RunService.Heartbeat:Connect(function(dt)
			if model.PrimaryPart and model.PrimaryPart.Parent then
				local pivot = model:GetPivot()
				model:PivotTo(pivot * CFrame.Angles(0, math.rad(speed) * dt, 0))
			end
		end)
		table.insert(conns, conn)
	end

	-- Slide: low friction on all surfaces
	if slideFriction then
		local friction = tonumber(slideFriction) or 0.02
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CustomPhysicalProperties = PhysicalProperties.new(0.5, friction, 0.3, 1, 1)
			end
		end
	end

	-- Seat: add invisible seat on top surface
	if seatHeight then
		local topY = -math.huge
		local centerX, centerZ = 0, 0
		local partCount = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local partTop = part.Position.Y + part.Size.Y / 2
				if partTop > topY then
					topY = partTop
				end
				centerX += part.Position.X
				centerZ += part.Position.Z
				partCount += 1
			end
		end
		if partCount > 0 then
			centerX /= partCount
			centerZ /= partCount
			local seat = Instance.new("Seat")
			seat.Size = Vector3.new(2, 0.5, 2)
			seat.Transparency = 1
			seat.CanCollide = true
			seat.Anchored = true
			seat.Position = Vector3.new(centerX, topY + 0.25, centerZ)
			seat.Parent = model
		end
	end

	if #conns > 0 then
		_behaviorConns[model] = conns
	end
end

-----------------------------------------------------------
-- Name label
-----------------------------------------------------------

local function addNameLabel(model: Model)
	if not model.PrimaryPart then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameLabel"
	billboard.Size = UDim2.fromOffset(200, 24)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = model.Name
	label.Parent = billboard
end

-----------------------------------------------------------
-- Clear all
-----------------------------------------------------------

local function clearAll()
	for _, model in _placedModels do
		local conns = _behaviorConns[model]
		if conns then
			for _, conn in conns do
				conn:Disconnect()
			end
			_behaviorConns[model] = nil
		end
		if model.Parent then
			model:Destroy()
		end
	end
	table.clear(_placedModels)
	updateCount()
	setStatus("All cleared!", COLORS.success)
end

-----------------------------------------------------------
-- Build action
-----------------------------------------------------------

local function submitBuild()
	if not _active or not _promptInput or _building then
		return
	end

	local prompt = _promptInput.Text
	if prompt == "" then
		setStatus("Type something to build!", COLORS.error)
		return
	end

	_building = true
	_promptInput.Text = ""
	if _buildButton then
		_buildButton.BackgroundColor3 = COLORS.disabled
		_buildButton.Text = "..."
	end
	setStatus("Building: " .. prompt .. "...", COLORS.accent)

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "building", "lowpoly"):await()

		if not _active then
			_building = false
			return
		end

		if _buildButton then
			_buildButton.BackgroundColor3 = COLORS.accent
			_buildButton.Text = "Build"
		end

		if not ok or not result or not result.success then
			local errMsg = if result and result.error then result.error else "Build failed"
			setStatus("Error: " .. tostring(errMsg), COLORS.error)
			_failSound:Play()
			_building = false
			return
		end

		local modelData = result.model
		local model = OrigamiBuilder.BuildModel(modelData)

		-- Place at raycast position
		local placeCF = getPlacementCFrame()
		model:PivotTo(placeCF)
		model.Parent = _playFolder

		-- Wire LLM-driven behaviors from attributes
		wireBehaviors(model)

		-- Add floating name label
		addNameLabel(model)

		table.insert(_placedModels, model)
		updateCount()
		setStatus("Built: " .. (modelData.name or prompt), COLORS.success)
		_successSound:Play()
		_building = false
	end)
end

-----------------------------------------------------------
-- UI Creation
-----------------------------------------------------------

local function createUI(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayUI"
	gui.DisplayOrder = 15
	gui.ResetOnSpawn = false

	-- Top-left: object count
	_countLabel = Instance.new("TextLabel")
	_countLabel.Size = UDim2.fromOffset(160, 24)
	_countLabel.Position = UDim2.new(0, 12, 0, 12)
	_countLabel.BackgroundTransparency = 1
	_countLabel.TextColor3 = COLORS.text
	_countLabel.TextXAlignment = Enum.TextXAlignment.Left
	_countLabel.Font = Enum.Font.GothamBold
	_countLabel.TextSize = 14
	_countLabel.Text = "Objects: 0"
	_countLabel.Parent = gui

	-- Top-left: Clear All button
	_clearButton = Instance.new("TextButton")
	_clearButton.Size = UDim2.fromOffset(80, 24)
	_clearButton.Position = UDim2.new(0, 12, 0, 40)
	_clearButton.BackgroundColor3 = COLORS.danger
	_clearButton.BackgroundTransparency = 0.2
	_clearButton.TextColor3 = COLORS.text
	_clearButton.Font = Enum.Font.GothamBold
	_clearButton.TextSize = 12
	_clearButton.Text = "Clear All"
	_clearButton.BorderSizePixel = 0
	_clearButton.Parent = gui

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 6)
	clearCorner.Parent = _clearButton

	_clearButton.Activated:Connect(clearAll)

	-- Bottom-center build panel
	local buildPanel = Instance.new("Frame")
	buildPanel.Name = "BuildPanel"
	buildPanel.Size = UDim2.fromOffset(400, 48)
	buildPanel.Position = UDim2.new(0.5, -200, 1, -60)
	buildPanel.BackgroundColor3 = COLORS.bg
	buildPanel.BackgroundTransparency = 0.15
	buildPanel.BorderSizePixel = 0
	buildPanel.Parent = gui

	local buildCorner = Instance.new("UICorner")
	buildCorner.CornerRadius = UDim.new(0, 8)
	buildCorner.Parent = buildPanel

	-- Prompt input
	_promptInput = Instance.new("TextBox")
	_promptInput.Name = "PromptInput"
	_promptInput.Size = UDim2.new(1, -80, 0, 32)
	_promptInput.Position = UDim2.new(0, 8, 0.5, -16)
	_promptInput.BackgroundColor3 = COLORS.bgLight
	_promptInput.BorderSizePixel = 0
	_promptInput.PlaceholderText = "What do you want to build?"
	_promptInput.PlaceholderColor3 = COLORS.textDim
	_promptInput.Text = ""
	_promptInput.TextColor3 = COLORS.text
	_promptInput.Font = Enum.Font.Gotham
	_promptInput.TextSize = 13
	_promptInput.ClearTextOnFocus = false
	_promptInput.Parent = buildPanel

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 6)
	inputCorner.Parent = _promptInput

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 8)
	inputPadding.PaddingRight = UDim.new(0, 8)
	inputPadding.Parent = _promptInput

	-- Build button
	_buildButton = Instance.new("TextButton")
	_buildButton.Name = "BuildButton"
	_buildButton.Size = UDim2.fromOffset(60, 32)
	_buildButton.Position = UDim2.new(1, -68, 0.5, -16)
	_buildButton.BackgroundColor3 = COLORS.accent
	_buildButton.BorderSizePixel = 0
	_buildButton.Text = "Build"
	_buildButton.TextColor3 = COLORS.bg
	_buildButton.Font = Enum.Font.GothamBold
	_buildButton.TextSize = 14
	_buildButton.Parent = buildPanel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = _buildButton

	_buildButton.Activated:Connect(submitBuild)
	_promptInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitBuild()
		end
	end)

	-- Status label (above build panel)
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "Status"
	_statusLabel.Size = UDim2.fromOffset(400, 24)
	_statusLabel.Position = UDim2.new(0.5, -200, 1, -90)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.Font = Enum.Font.GothamBold
	_statusLabel.TextSize = 13
	_statusLabel.Parent = gui

	gui.Parent = Player.PlayerGui
	return gui
end

-----------------------------------------------------------
-- Activate / Cleanup
-----------------------------------------------------------

function PlayController:Activate()
	if _active then
		return
	end
	_active = true

	table.clear(_placedModels)

	_playFolder = Instance.new("Folder")
	_playFolder.Name = "PlayObjects"
	_playFolder.Parent = workspace

	_gui = createUI()
	setStatus("Build anything! Everything is interactive.", COLORS.success)
end

function PlayController:Cleanup()
	_active = false
	_building = false

	-- Disconnect all behavior connections
	for model, conns in _behaviorConns do
		for _, conn in conns do
			conn:Disconnect()
		end
	end
	table.clear(_behaviorConns)

	-- Destroy all placed objects
	if _playFolder then
		_playFolder:Destroy()
		_playFolder = nil
	end

	table.clear(_placedModels)

	-- Destroy UI
	if _gui then
		_gui:Destroy()
		_gui = nil
	end

	_statusLabel = nil
	_promptInput = nil
	_buildButton = nil
	_countLabel = nil
	_clearButton = nil
end

-----------------------------------------------------------
-- Knit lifecycle
-----------------------------------------------------------

function PlayController:KnitInit() end

function PlayController:KnitStart()
	GameMode.Changed:Connect(function(newMode, oldMode)
		if newMode == "play" then
			self:Activate()
		elseif oldMode == "play" then
			self:Cleanup()
		end
	end)
end

return PlayController
