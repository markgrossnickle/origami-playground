--[[
	EmoteController — client-side emote playback, UI wheel, and Motor6D animation.
	Press T / DPadUp to open emote wheel. Presets are free, custom emotes use LLM.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)

local Player = Players.LocalPlayer

-- Responsive detection
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled

-- UI constants
local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(100, 180, 255),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	disabled = Color3.fromRGB(80, 80, 90),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
}

local TEXT_SCALE = if IS_CONSOLE then 1.5 elseif IS_MOBILE then 1.2 else 1.0
local BUTTON_SIZE = if IS_MOBILE then 54 else 44

-- Motor6D name mapping: body part → Motor6D name
local JOINT_TO_MOTOR: { [string]: string } = {
	Neck = "Neck",
	Waist = "Waist",
	RightShoulder = "RightShoulder",
	LeftShoulder = "LeftShoulder",
	RightElbow = "RightElbow",
	LeftElbow = "LeftElbow",
	RightHip = "RightHip",
	LeftHip = "LeftHip",
	RightKnee = "RightKnee",
	LeftKnee = "LeftKnee",
	RightAnkle = "RightAnkle",
	LeftAnkle = "LeftAnkle",
	RightWrist = "RightWrist",
	LeftWrist = "LeftWrist",
	Root = "Root",
}

-- State
local _gui: ScreenGui? = nil
local _wheelFrame: Frame? = nil
local _customInput: TextBox? = nil
local _statusLabel: TextLabel? = nil
local _wheelVisible = false
local _activeAnimation: { stopped: boolean }? = nil

---------- Motor6D Animation Engine ----------

local function findMotor6D(character: Model, motorName: string): Motor6D?
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Motor6D") and desc.Name == motorName then
			return desc :: Motor6D
		end
	end
	return nil
end

local function lerpAngle(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function getJointRotation(joints: { [string]: { number } }?, jointName: string): (number, number, number)?
	if not joints then return nil end
	local rot = joints[jointName]
	if not rot then return nil end
	return rot[1] or 0, rot[2] or 0, rot[3] or 0
end

--- Play keyframe animation on a character. Returns cleanup function.
function _playEmoteOnCharacter(character: Model, emoteData: { [string]: any }): () -> ()
	local keyframes = emoteData.keyframes
	local duration = emoteData.duration or 2
	local shouldLoop = emoteData.loop or false
	local state = { stopped = false }

	-- Store original Motor6D transforms for restoration
	local originals: { [string]: CFrame } = {}
	for jointName, motorName in pairs(JOINT_TO_MOTOR) do
		local motor = findMotor6D(character, motorName)
		if motor then
			originals[motorName] = motor.Transform
		end
	end

	task.spawn(function()
		repeat
			local startTime = os.clock()

			while not state.stopped do
				local elapsed = os.clock() - startTime
				if elapsed >= duration then break end

				-- Find surrounding keyframes
				local prevKF, nextKF = keyframes[1], keyframes[#keyframes]
				for i = 1, #keyframes - 1 do
					if keyframes[i].time <= elapsed and keyframes[i + 1].time >= elapsed then
						prevKF = keyframes[i]
						nextKF = keyframes[i + 1]
						break
					end
				end

				local segmentDuration = nextKF.time - prevKF.time
				local t = if segmentDuration > 0 then math.clamp((elapsed - prevKF.time) / segmentDuration, 0, 1) else 1
				-- Smooth easing
				t = t * t * (3 - 2 * t)

				-- Interpolate each joint
				for jointName, motorName in pairs(JOINT_TO_MOTOR) do
					local motor = findMotor6D(character, motorName)
					if not motor then continue end

					local px, py, pz = getJointRotation(prevKF.joints, jointName)
					local nx, ny, nz = getJointRotation(nextKF.joints, jointName)

					-- Default to zero (rest pose) if joint not in keyframe
					px = px or 0; py = py or 0; pz = pz or 0
					nx = nx or 0; ny = ny or 0; nz = nz or 0

					local rx = math.rad(lerpAngle(px, nx, t))
					local ry = math.rad(lerpAngle(py, ny, t))
					local rz = math.rad(lerpAngle(pz, nz, t))

					motor.Transform = CFrame.Angles(rx, ry, rz)
				end

				RunService.Heartbeat:Wait()
			end
		until not shouldLoop or state.stopped

		-- Restore original transforms
		if character and character.Parent then
			for motorName, original in pairs(originals) do
				local motor = findMotor6D(character, motorName)
				if motor then
					motor.Transform = original
				end
			end
		end
	end)

	return function()
		state.stopped = true
	end
end

---------- Public API ----------

local EmoteController = Knit.CreateController({ Name = "EmoteController" })

--- Play a preset emote on the local player.
function EmoteController:PlayPreset(presetName: string)
	local EmoteService = Knit.GetService("EmoteService")
	EmoteService:PlayPresetEmote(presetName) -- server broadcasts to all
end

--- Play emote data on a specific character (used for remote players).
function EmoteController:PlayOnCharacter(character: Model, keyframeData: { [string]: any })
	-- Stop any active animation on this character
	return _playEmoteOnCharacter(character, keyframeData)
end

---------- UI ----------

local function makeCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
end

local function setStatus(text: string, color: Color3?)
	if _statusLabel then
		_statusLabel.Text = text
		_statusLabel.TextColor3 = color or COLORS.textDim
		task.delay(3, function()
			if _statusLabel and _statusLabel.Text == text then
				_statusLabel.Text = ""
			end
		end)
	end
end

local function toggleWheel()
	_wheelVisible = not _wheelVisible
	if _wheelFrame then
		_wheelFrame.Visible = _wheelVisible
	end
end

local function createEmoteButton(parent: GuiObject, text: string, order: number, callback: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = text
	btn.Size = UDim2.new(1, -8, 0, BUTTON_SIZE)
	btn.BackgroundColor3 = COLORS.bgLight
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = COLORS.text
	btn.TextSize = math.floor(14 * TEXT_SCALE)
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	btn.LayoutOrder = order
	btn.Parent = parent
	makeCorner(btn, 6)

	btn.Activated:Connect(function()
		callback()
		toggleWheel() -- close after selecting
	end)

	return btn
end

local function createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteWheel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Player.PlayerGui
	_gui = gui

	-- Emote wheel panel (hidden by default)
	local wheel = Instance.new("Frame")
	wheel.Name = "WheelFrame"
	wheel.Size = UDim2.fromOffset(200, 0) -- auto-sized by layout
	wheel.Position = UDim2.new(0.5, -100, 1, -200)
	wheel.BackgroundColor3 = COLORS.bg
	wheel.BackgroundTransparency = 0.1
	wheel.BorderSizePixel = 0
	wheel.Visible = false
	wheel.AutomaticSize = Enum.AutomaticSize.Y
	wheel.Parent = gui
	makeCorner(wheel)
	_wheelFrame = wheel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = wheel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = wheel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Text = "Emotes"
	title.TextColor3 = COLORS.accent
	title.TextSize = math.floor(16 * TEXT_SCALE)
	title.Font = Enum.Font.GothamBold
	title.LayoutOrder = 0
	title.Parent = wheel

	-- Preset emote buttons
	createEmoteButton(wheel, "Wave", 1, function()
		EmoteController:PlayPreset("wave")
	end)
	createEmoteButton(wheel, "Celebrate", 2, function()
		EmoteController:PlayPreset("celebration")
	end)
	createEmoteButton(wheel, "Thank You", 3, function()
		EmoteController:PlayPreset("thank_you")
	end)
	createEmoteButton(wheel, "Dance", 4, function()
		EmoteController:PlayPreset("dance")
	end)

	-- Separator
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.BackgroundColor3 = COLORS.textDim
	sep.BackgroundTransparency = 0.5
	sep.BorderSizePixel = 0
	sep.LayoutOrder = 10
	sep.Parent = wheel

	-- Custom emote section
	local customLabel = Instance.new("TextLabel")
	customLabel.Size = UDim2.new(1, 0, 0, 20)
	customLabel.BackgroundTransparency = 1
	customLabel.Text = "Custom (1 Crane)"
	customLabel.TextColor3 = COLORS.textDim
	customLabel.TextSize = math.floor(12 * TEXT_SCALE)
	customLabel.Font = Enum.Font.Gotham
	customLabel.LayoutOrder = 11
	customLabel.Parent = wheel

	local customRow = Instance.new("Frame")
	customRow.Size = UDim2.new(1, 0, 0, BUTTON_SIZE)
	customRow.BackgroundTransparency = 1
	customRow.LayoutOrder = 12
	customRow.Parent = wheel

	local inputBox = Instance.new("TextBox")
	inputBox.Size = UDim2.new(1, -60, 1, 0)
	inputBox.PlaceholderText = "describe emote..."
	inputBox.Text = ""
	inputBox.TextColor3 = COLORS.text
	inputBox.PlaceholderColor3 = COLORS.textDim
	inputBox.BackgroundColor3 = COLORS.bgLight
	inputBox.BorderSizePixel = 0
	inputBox.TextSize = math.floor(13 * TEXT_SCALE)
	inputBox.Font = Enum.Font.Gotham
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = customRow
	makeCorner(inputBox, 6)
	_customInput = inputBox

	local goBtn = Instance.new("TextButton")
	goBtn.Size = UDim2.new(0, 52, 1, 0)
	goBtn.Position = UDim2.new(1, -52, 0, 0)
	goBtn.Text = "Go"
	goBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	goBtn.BackgroundColor3 = COLORS.accent
	goBtn.BorderSizePixel = 0
	goBtn.TextSize = math.floor(14 * TEXT_SCALE)
	goBtn.Font = Enum.Font.GothamBold
	goBtn.AutoButtonColor = true
	goBtn.Parent = customRow
	makeCorner(goBtn, 6)

	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 0, 18)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.TextSize = math.floor(11 * TEXT_SCALE)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.LayoutOrder = 20
	statusLabel.Parent = wheel
	_statusLabel = statusLabel

	-- Custom emote generation
	local function submitCustom()
		if not _customInput then return end
		local prompt = _customInput.Text
		if prompt == "" then
			setStatus("Type an emote description", COLORS.error)
			return
		end

		setStatus("Generating...", COLORS.accent)
		_customInput.Text = ""

		task.spawn(function()
			local EmoteService = Knit.GetService("EmoteService")
			local result = EmoteService:RequestEmote(prompt):await()

			if result and result.success and result.emote then
				setStatus("Playing!", COLORS.success)
				-- Play immediately
				EmoteService:PlayEmote(result.emote)
			else
				setStatus(result and result.error or "Failed", COLORS.error)
			end
		end)
	end

	goBtn.Activated:Connect(submitCustom)
	inputBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitCustom()
		end
	end)

	-- Touch button for mobile (always visible small button)
	if IS_MOBILE then
		local touchBtn = Instance.new("TextButton")
		touchBtn.Name = "EmoteTouchButton"
		touchBtn.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
		touchBtn.Position = UDim2.new(1, -(BUTTON_SIZE + 12), 0.5, 0)
		touchBtn.Text = "E"
		touchBtn.TextColor3 = COLORS.text
		touchBtn.BackgroundColor3 = COLORS.bg
		touchBtn.BackgroundTransparency = 0.3
		touchBtn.BorderSizePixel = 0
		touchBtn.TextSize = 20
		touchBtn.Font = Enum.Font.GothamBold
		touchBtn.AutoButtonColor = true
		touchBtn.Parent = gui
		makeCorner(touchBtn, BUTTON_SIZE / 2)

		touchBtn.Activated:Connect(toggleWheel)
	end
end

---------- Lifecycle ----------

function EmoteController:KnitInit() end

function EmoteController:KnitStart()
	createUI()

	-- Keyboard: T to toggle emote wheel
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.T then
			toggleWheel()
		elseif input.KeyCode == Enum.KeyCode.DPadUp then
			toggleWheel()
		end
	end)

	-- Close wheel when clicking outside
	UserInputService.InputBegan:Connect(function(input, _processed)
		if not _wheelVisible then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- Small delay to let button clicks process first
			task.defer(function()
				if _wheelFrame and _wheelVisible then
					local mouse = UserInputService:GetMouseLocation()
					local pos = _wheelFrame.AbsolutePosition
					local size = _wheelFrame.AbsoluteSize
					if mouse.X < pos.X or mouse.X > pos.X + size.X
						or mouse.Y < pos.Y or mouse.Y > pos.Y + size.Y then
						_wheelVisible = false
						_wheelFrame.Visible = false
					end
				end
			end)
		end
	end)

	-- Listen for remote emote broadcasts
	local EmoteService = Knit.GetService("EmoteService")
	EmoteService.EmotePlayed:Connect(function(emotePlayer: Player, keyframeData: any)
		local character = emotePlayer.Character
		if not character then return end

		-- Stop any active animation
		if _activeAnimation then
			_activeAnimation.stopped = true
		end

		local stopFn = _playEmoteOnCharacter(character, keyframeData)
		if emotePlayer == Player then
			local state = { stopped = false }
			_activeAnimation = state
			-- Auto-stop after duration
			task.delay(keyframeData.duration or 2, function()
				if not state.stopped then
					stopFn()
				end
			end)
		end
	end)
end

return EmoteController
