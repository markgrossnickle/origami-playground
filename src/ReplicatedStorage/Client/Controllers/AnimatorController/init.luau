local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local KeyframePlayer = require(ReplicatedStorage.Shared.KeyframePlayer)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local Player = Players.LocalPlayer

local AnimatorController = Knit.CreateController({
	Name = "AnimatorController",
})

local _gui: ScreenGui
local _inputBox: TextBox
local _statusLabel: TextLabel
local _animateButton: TextButton
local _clearButton: TextButton
local _spawnButton: TextButton
local _mannequin: Model? = nil
local _currentPlayback: KeyframePlayer.PlaybackHandle? = nil

-- Reuse the same color scheme as CreatorController
local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(100, 180, 255),
	accentDim = Color3.fromRGB(60, 100, 160),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	disabled = Color3.fromRGB(80, 80, 90),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	danger = Color3.fromRGB(200, 60, 60),
	mannequin = Color3.fromRGB(160, 160, 170),
}

-- ============================================================
-- R15 Mannequin Spawner
-- ============================================================

-- Part definitions: { name, size, parentName, jointName, jointC0, jointC1 }
-- C0 = offset from parent's joint point, C1 = offset from child's joint point
local R15_PARTS = {
	-- Root
	{
		name = "HumanoidRootPart",
		size = Vector3.new(2, 2, 1),
		transparency = 1,
	},
	-- Torso
	{
		name = "LowerTorso",
		size = Vector3.new(2, 0.8, 1),
		parent = "HumanoidRootPart",
		joint = "Root",
		c0 = CFrame.new(0, -0.2, 0),
		c1 = CFrame.new(0, 0.4, 0),
	},
	{
		name = "UpperTorso",
		size = Vector3.new(2, 1.2, 1),
		parent = "LowerTorso",
		joint = "Waist",
		c0 = CFrame.new(0, 0.4, 0),
		c1 = CFrame.new(0, -0.6, 0),
	},
	-- Head
	{
		name = "Head",
		size = Vector3.new(1.2, 1.2, 1.2),
		parent = "UpperTorso",
		joint = "Neck",
		c0 = CFrame.new(0, 0.6, 0),
		c1 = CFrame.new(0, -0.6, 0),
	},
	-- Left Arm
	{
		name = "LeftUpperArm",
		size = Vector3.new(0.6, 1.0, 0.6),
		parent = "UpperTorso",
		joint = "LeftShoulder",
		c0 = CFrame.new(-1.3, 0.4, 0),
		c1 = CFrame.new(0, 0.5, 0),
	},
	{
		name = "LeftLowerArm",
		size = Vector3.new(0.5, 1.0, 0.5),
		parent = "LeftUpperArm",
		joint = "LeftElbow",
		c0 = CFrame.new(0, -0.5, 0),
		c1 = CFrame.new(0, 0.5, 0),
	},
	{
		name = "LeftHand",
		size = Vector3.new(0.5, 0.5, 0.5),
		parent = "LeftLowerArm",
		joint = "LeftWrist",
		c0 = CFrame.new(0, -0.5, 0),
		c1 = CFrame.new(0, 0.25, 0),
	},
	-- Right Arm
	{
		name = "RightUpperArm",
		size = Vector3.new(0.6, 1.0, 0.6),
		parent = "UpperTorso",
		joint = "RightShoulder",
		c0 = CFrame.new(1.3, 0.4, 0),
		c1 = CFrame.new(0, 0.5, 0),
	},
	{
		name = "RightLowerArm",
		size = Vector3.new(0.5, 1.0, 0.5),
		parent = "RightUpperArm",
		joint = "RightElbow",
		c0 = CFrame.new(0, -0.5, 0),
		c1 = CFrame.new(0, 0.5, 0),
	},
	{
		name = "RightHand",
		size = Vector3.new(0.5, 0.5, 0.5),
		parent = "RightLowerArm",
		joint = "RightWrist",
		c0 = CFrame.new(0, -0.5, 0),
		c1 = CFrame.new(0, 0.25, 0),
	},
	-- Left Leg
	{
		name = "LeftUpperLeg",
		size = Vector3.new(0.6, 1.2, 0.6),
		parent = "LowerTorso",
		joint = "LeftHip",
		c0 = CFrame.new(-0.5, -0.4, 0),
		c1 = CFrame.new(0, 0.6, 0),
	},
	{
		name = "LeftLowerLeg",
		size = Vector3.new(0.5, 1.2, 0.5),
		parent = "LeftUpperLeg",
		joint = "LeftKnee",
		c0 = CFrame.new(0, -0.6, 0),
		c1 = CFrame.new(0, 0.6, 0),
	},
	{
		name = "LeftFoot",
		size = Vector3.new(0.5, 0.4, 0.8),
		parent = "LeftLowerLeg",
		joint = "LeftAnkle",
		c0 = CFrame.new(0, -0.6, 0),
		c1 = CFrame.new(0, 0.2, -0.15),
	},
	-- Right Leg
	{
		name = "RightUpperLeg",
		size = Vector3.new(0.6, 1.2, 0.6),
		parent = "LowerTorso",
		joint = "RightHip",
		c0 = CFrame.new(0.5, -0.4, 0),
		c1 = CFrame.new(0, 0.6, 0),
	},
	{
		name = "RightLowerLeg",
		size = Vector3.new(0.5, 1.2, 0.5),
		parent = "RightUpperLeg",
		joint = "RightKnee",
		c0 = CFrame.new(0, -0.6, 0),
		c1 = CFrame.new(0, 0.6, 0),
	},
	{
		name = "RightFoot",
		size = Vector3.new(0.5, 0.4, 0.8),
		parent = "RightLowerLeg",
		joint = "RightAnkle",
		c0 = CFrame.new(0, -0.6, 0),
		c1 = CFrame.new(0, 0.2, -0.15),
	},
}

local function spawnMannequin(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "AnimatorMannequin"

	local partsByName: { [string]: BasePart } = {}

	-- Create all parts first
	for _, def in ipairs(R15_PARTS) do
		local part = Instance.new("Part")
		part.Name = def.name
		part.Size = def.size
		part.Anchored = false
		part.CanCollide = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = COLORS.mannequin
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth

		if def.transparency then
			part.Transparency = def.transparency
		end

		if def.name == "HumanoidRootPart" then
			part.Anchored = true
		end

		part.Parent = model
		partsByName[def.name] = part
	end

	-- Set PrimaryPart
	model.PrimaryPart = partsByName["HumanoidRootPart"]

	-- Position the root
	local rootPart = partsByName["HumanoidRootPart"]
	rootPart.CFrame = CFrame.new(position)

	-- Create Motor6D joints and position parts
	for _, def in ipairs(R15_PARTS) do
		if def.parent and def.joint then
			local parentPart = partsByName[def.parent]
			local childPart = partsByName[def.name]

			if parentPart and childPart then
				local motor = Instance.new("Motor6D")
				motor.Name = def.joint
				motor.Part0 = parentPart
				motor.Part1 = childPart
				motor.C0 = def.c0 or CFrame.new()
				motor.C1 = def.c1 or CFrame.new()
				motor.Parent = childPart
			end
		end
	end

	-- Add a name label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameLabel"
	billboard.Size = UDim2.new(0, 200, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 50
	billboard.Adornee = partsByName["Head"]
	billboard.Parent = partsByName["Head"]

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "Mannequin"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	model.Parent = workspace

	return model
end

-- ============================================================
-- UI
-- ============================================================

local function setStatus(text: string, color: Color3?)
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim
	task.delay(5, function()
		if _statusLabel.Text == text then
			_statusLabel.Text = ""
		end
	end)
end

local function updateSpawnButton()
	if _mannequin and _mannequin.Parent then
		_spawnButton.Text = "Respawn"
	else
		_spawnButton.Text = "Spawn"
	end
end

local function destroyMannequin()
	if _currentPlayback then
		_currentPlayback:Stop()
		_currentPlayback = nil
	end
	if _mannequin and _mannequin.Parent then
		_mannequin:Destroy()
	end
	_mannequin = nil
	updateSpawnButton()
end

local function doSpawnMannequin()
	-- Remove existing mannequin
	destroyMannequin()

	local character = Player.Character
	if not character then
		setStatus("No character found", COLORS.error)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		setStatus("No root part found", COLORS.error)
		return
	end

	-- Spawn in front of player
	local forward = rootPart.CFrame.LookVector
	local spawnPos = rootPart.Position + forward * OrigamiConfig.PLACEMENT_DISTANCE
	-- Raise to ground level + half humanoid height
	spawnPos = Vector3.new(spawnPos.X, rootPart.Position.Y, spawnPos.Z)

	_mannequin = spawnMannequin(spawnPos)
	updateSpawnButton()
	setStatus("Mannequin spawned! Enter an animation prompt.", COLORS.success)
end

local function submitAnimation()
	local prompt = _inputBox.Text
	if not prompt or prompt:match("^%s*$") then
		setStatus("Type an animation prompt first!", COLORS.error)
		return
	end

	if not _mannequin or not _mannequin.Parent then
		setStatus("Spawn a mannequin first!", COLORS.error)
		return
	end

	_inputBox.Text = ""
	setStatus("Generating animation...", COLORS.accent)
	_animateButton.BackgroundColor3 = COLORS.disabled
	_animateButton.Text = "..."

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "animation", "origami"):await()

		_animateButton.BackgroundColor3 = COLORS.accent
		_animateButton.Text = "Animate"

		if ok and result and result.success and result.model then
			local modelData = result.model

			-- The model data IS the animation JSON for category="animation"
			local animData = KeyframePlayer.Parse(modelData)
			if not animData then
				setStatus("Invalid animation data returned", COLORS.error)
				return
			end

			-- Stop any current animation
			if _currentPlayback then
				_currentPlayback:Stop()
				_currentPlayback = nil
			end

			-- Play the new animation
			_currentPlayback = KeyframePlayer.Play(_mannequin, animData)

			local animName = animData.name or "Animation"
			local loopText = if animData.loop then " (looping)" else ""
			setStatus("Playing: " .. animName .. loopText, COLORS.success)

			-- Update mannequin label
			local head = _mannequin:FindFirstChild("Head")
			if head then
				local billboard = head:FindFirstChild("NameLabel")
				if billboard then
					local lbl = billboard:FindFirstChildOfClass("TextLabel")
					if lbl then
						lbl.Text = animName
					end
				end
			end
		else
			local errMsg = (ok and result and result.error) or (not ok and tostring(result)) or "Unknown error"
			setStatus("Failed: " .. errMsg:sub(1, 40), COLORS.error)
		end
	end)
end

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "AnimatorPanel"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 6
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Container at top-right of screen
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 320, 0, 170)
	container.Position = UDim2.new(1, -330, 0, 10)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	-- Title row
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 24)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Animator"
	title.TextColor3 = COLORS.accent
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = container

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 24, 0, 24)
	closeBtn.Position = UDim2.new(1, -32, 0, 8)
	closeBtn.BackgroundColor3 = COLORS.bgLight
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.textDim
	closeBtn.TextSize = 12
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = container

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		AnimatorController:Hide()
	end)

	-- Spawn / Respawn button
	_spawnButton = Instance.new("TextButton")
	_spawnButton.Name = "SpawnButton"
	_spawnButton.Size = UDim2.new(0.5, -15, 0, 32)
	_spawnButton.Position = UDim2.new(0, 10, 0, 36)
	_spawnButton.BackgroundColor3 = COLORS.accentDim
	_spawnButton.BorderSizePixel = 0
	_spawnButton.Text = "Spawn"
	_spawnButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_spawnButton.TextSize = 14
	_spawnButton.Font = Enum.Font.GothamBold
	_spawnButton.AutoButtonColor = true
	_spawnButton.Parent = container

	local spawnCorner = Instance.new("UICorner")
	spawnCorner.CornerRadius = UDim.new(0, 8)
	spawnCorner.Parent = _spawnButton

	-- Clear button
	_clearButton = Instance.new("TextButton")
	_clearButton.Name = "ClearButton"
	_clearButton.Size = UDim2.new(0.5, -15, 0, 32)
	_clearButton.Position = UDim2.new(0.5, 5, 0, 36)
	_clearButton.BackgroundColor3 = COLORS.danger
	_clearButton.BorderSizePixel = 0
	_clearButton.Text = "Remove"
	_clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_clearButton.TextSize = 14
	_clearButton.Font = Enum.Font.GothamBold
	_clearButton.AutoButtonColor = true
	_clearButton.Parent = container

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 8)
	clearCorner.Parent = _clearButton

	-- Prompt input
	_inputBox = Instance.new("TextBox")
	_inputBox.Name = "AnimPromptInput"
	_inputBox.Size = UDim2.new(1, -20, 0, 36)
	_inputBox.Position = UDim2.new(0, 10, 0, 78)
	_inputBox.BackgroundColor3 = COLORS.bgLight
	_inputBox.BorderSizePixel = 0
	_inputBox.PlaceholderText = "Describe an animation... (e.g. wave hello)"
	_inputBox.PlaceholderColor3 = COLORS.textDim
	_inputBox.Text = ""
	_inputBox.TextColor3 = COLORS.text
	_inputBox.TextSize = 14
	_inputBox.Font = Enum.Font.Gotham
	_inputBox.ClearTextOnFocus = false
	_inputBox.Parent = container

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = _inputBox

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 10)
	inputPadding.PaddingRight = UDim.new(0, 10)
	inputPadding.Parent = _inputBox

	-- Animate button
	_animateButton = Instance.new("TextButton")
	_animateButton.Name = "AnimateButton"
	_animateButton.Size = UDim2.new(1, -20, 0, 32)
	_animateButton.Position = UDim2.new(0, 10, 0, 122)
	_animateButton.BackgroundColor3 = COLORS.accent
	_animateButton.BorderSizePixel = 0
	_animateButton.Text = "Animate"
	_animateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_animateButton.TextSize = 14
	_animateButton.Font = Enum.Font.GothamBold
	_animateButton.AutoButtonColor = true
	_animateButton.Parent = container

	local animateCorner = Instance.new("UICorner")
	animateCorner.CornerRadius = UDim.new(0, 8)
	animateCorner.Parent = _animateButton

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "StatusLabel"
	_statusLabel.Size = UDim2.new(1, -20, 0, 18)
	_statusLabel.Position = UDim2.new(0, 10, 0, 158)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.TextSize = 11
	_statusLabel.Font = Enum.Font.Gotham
	_statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	_statusLabel.Parent = container

	-- Wire up events
	_spawnButton.Activated:Connect(function()
		doSpawnMannequin()
	end)

	_clearButton.Activated:Connect(function()
		destroyMannequin()
		setStatus("Mannequin removed", COLORS.textDim)
	end)

	_animateButton.Activated:Connect(function()
		submitAnimation()
	end)

	_inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitAnimation()
		end
	end)

	-- Start hidden
	_gui.Enabled = false
	_gui.Parent = Player.PlayerGui
end

function AnimatorController:Toggle()
	if _gui then
		_gui.Enabled = not _gui.Enabled
	end
end

function AnimatorController:Show()
	if _gui then
		_gui.Enabled = true
	end
end

function AnimatorController:Hide()
	if _gui then
		_gui.Enabled = false
	end
end

function AnimatorController:IsVisible(): boolean
	return _gui ~= nil and _gui.Enabled
end

function AnimatorController:KnitInit() end

function AnimatorController:KnitStart()
	createUI()
end

return AnimatorController
