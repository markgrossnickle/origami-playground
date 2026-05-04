--!strict
--[[
	ReturnToBaseController — bottom-center "Return to Base" button.

	Hold to channel for 2.5 seconds; on completion, fires the server RPC
	which validates and teleports the player to their region's inner edge
	(same point used for initial spawn). After a successful teleport, a
	60-second cooldown locks the button.

	Channel cancels:
		* Mouse-up / touch-end before the channel completes.
		* HRP horizontal displacement > 1.5 studs from the start position.
		  XZ-only so jumping in place / falling on a redrawn chunk doesn't
		  cancel — only player-driven walking does.
		* Humanoid health decrease (any damage source). Today nothing in
		  the game causes damage, so this is a dormant hook waiting for
		  combat to land. When it does, channeling-while-being-attacked
		  will already cancel — no follow-up needed.

	State machine, top to bottom in priority:
		* No region claimed             → button hidden
		* Inside own region (no-op)     → "Already at base", disabled
		* Cooldown active               → "Wait Ns", disabled, fill bar shows
		                                   remaining cooldown
		* Channeling                    → "Returning..." with progress fill
		* Idle                          → "Return to Base" with hint
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ZoneRegistry = require(ReplicatedStorage.Shared.ZoneRegistry)

local LocalPlayer = Players.LocalPlayer

local ReturnToBaseController = Knit.CreateController({
	Name = "ReturnToBaseController",
})

local CHANNEL_SECONDS = 2.5
local CANCEL_DISTANCE = 1.5 -- XZ studs of movement before we cancel
local BUTTON_WIDTH = 240
local BUTTON_HEIGHT = 52

local COLOR_BG = Color3.fromRGB(20, 20, 30)
local COLOR_BG_DISABLED = Color3.fromRGB(40, 40, 50)
local COLOR_FILL_CHANNEL = Color3.fromRGB(120, 200, 255)
local COLOR_FILL_COOLDOWN = Color3.fromRGB(160, 160, 175)
local COLOR_TEXT = Color3.fromRGB(240, 240, 240)
local COLOR_TEXT_DISABLED = Color3.fromRGB(170, 170, 180)
local COLOR_BORDER = Color3.fromRGB(120, 120, 140)
local COLOR_FAIL = Color3.fromRGB(220, 130, 120)

local _ownedSlotId: string = ""
local _cooldownEndsAt: number = 0 -- client os.clock() based
local _cooldownDuration: number = 60 -- mirrors server constant after first probe

-- Channel state. nil when not channeling.
local _channelStart: number? = nil
local _channelStartPos: Vector3? = nil
local _channelHumanoid: Humanoid? = nil
local _channelStartHealth: number? = nil
local _channelDamageConn: RBXScriptConnection? = nil
local _channelHumanoidConn: RBXScriptConnection? = nil

-- UI handles.
local _gui: ScreenGui? = nil
local _button: TextButton? = nil
local _fill: Frame? = nil
local _label: TextLabel? = nil
local _hint: TextLabel? = nil

-- Brief banner for transient errors ("on cooldown", "no region yet").
local _flashUntil: number = 0
local _flashText: string = ""

local function _now(): number
	return os.clock()
end

local function _setFill(progress: number, color: Color3)
	if not _fill then
		return
	end
	local clamped = math.clamp(progress, 0, 1)
	_fill.Size = UDim2.new(clamped, 0, 1, 0)
	_fill.BackgroundColor3 = color
end

local function _setLabel(text: string, color: Color3?)
	if _label then
		_label.Text = text
		if color then
			_label.TextColor3 = color
		end
	end
end

local function _setHint(text: string)
	if _hint then
		_hint.Text = text
	end
end

local function _setBackground(color: Color3)
	if _button then
		_button.BackgroundColor3 = color
	end
end

local function _flashError(message: string, duration: number?)
	_flashText = message
	_flashUntil = _now() + (duration or 1.6)
end

-- Detach any per-character connections we set up at channel start.
local function _disconnectChannelHooks()
	if _channelHumanoidConn then
		_channelHumanoidConn:Disconnect()
		_channelHumanoidConn = nil
	end
	if _channelDamageConn then
		_channelDamageConn:Disconnect()
		_channelDamageConn = nil
	end
	_channelHumanoid = nil
	_channelStartHealth = nil
end

local function _cancelChannel(reason: string?)
	if _channelStart == nil then
		return
	end
	_channelStart = nil
	_channelStartPos = nil
	_disconnectChannelHooks()
	if reason then
		_flashError(reason)
	end
end

local function _isInOwnRegion(hrp: BasePart): boolean
	if _ownedSlotId == "" then
		return false
	end
	local pos = hrp.Position
	return ZoneRegistry.getRegionAt(pos.X, pos.Z) == _ownedSlotId
end

local function _humanoidOf(character: Model?): Humanoid?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function _hrpOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function _tryStartChannel()
	if _channelStart ~= nil then
		return
	end
	if _ownedSlotId == "" then
		_flashError("Claim a region first")
		return
	end
	if _now() < _cooldownEndsAt then
		_flashError("Cooling down")
		return
	end
	local character = LocalPlayer.Character
	local hrp = _hrpOf(character)
	if not hrp then
		_flashError("No character")
		return
	end
	if _isInOwnRegion(hrp) then
		_flashError("Already at base")
		return
	end

	_channelStart = _now()
	_channelStartPos = hrp.Position

	-- Damage hook. Today nothing damages the player but combat is on the
	-- roadmap; subscribing now means the cancel-on-attack contract is live
	-- the day combat lands.
	local humanoid = _humanoidOf(character)
	if humanoid then
		_channelHumanoid = humanoid
		_channelStartHealth = humanoid.Health
		_channelDamageConn = humanoid.HealthChanged:Connect(function(newHealth)
			if _channelStart == nil then
				return
			end
			local prev = _channelStartHealth or newHealth
			if newHealth < prev - 0.01 then
				_cancelChannel("Channel broken")
			end
			_channelStartHealth = newHealth
		end)
		-- Death also cancels (HealthChanged fires before Died on most
		-- damage paths but we belt-and-suspender it).
		_channelHumanoidConn = humanoid.Died:Connect(function()
			_cancelChannel(nil)
		end)
	end
end

local function _completeChannel()
	if _channelStart == nil then
		return
	end
	_channelStart = nil
	_channelStartPos = nil
	_disconnectChannelHooks()

	-- Fire-and-forget: the RPC call itself yields ~600ms inside the server
	-- (chunk pre-subscribe). Keep the UI showing "Returning..." until the
	-- response lands.
	_setLabel("Returning...", COLOR_TEXT)
	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if not SpawnService then
			_flashError("Service unavailable")
			return
		end
		local ok, response = SpawnService:RequestReturnToBase():await()
		if not ok then
			_flashError("Teleport failed")
			return
		end
		if type(response) ~= "table" or response.success ~= true then
			local err = response and response.error or "unknown"
			if err == "cooldown" then
				local remaining = (response and response.remainingCooldown) or 0
				_cooldownEndsAt = _now() + remaining
				if response and type(response.cooldownSeconds) == "number" then
					_cooldownDuration = response.cooldownSeconds
				end
				_flashError("Cooling down")
			elseif err == "no_region" then
				_flashError("No region claimed")
			else
				_flashError("Teleport failed")
			end
			return
		end
		local remaining = response.remainingCooldown or 0
		_cooldownEndsAt = _now() + remaining
		if type(response.cooldownSeconds) == "number" then
			_cooldownDuration = response.cooldownSeconds
		end
	end)
end

local function _onHeartbeat(_dt: number)
	if not _gui or not _button then
		return
	end

	local character = LocalPlayer.Character
	local hrp = _hrpOf(character)

	-- Step the channel even if the HRP went nil — the cancel path handles
	-- the missing-character case.
	if _channelStart ~= nil then
		if not hrp then
			_cancelChannel(nil)
		elseif _channelStartPos then
			local dx = hrp.Position.X - _channelStartPos.X
			local dz = hrp.Position.Z - _channelStartPos.Z
			if dx * dx + dz * dz > CANCEL_DISTANCE * CANCEL_DISTANCE then
				_cancelChannel("Hold still")
			end
		end
	end

	if _channelStart ~= nil then
		local elapsed = _now() - _channelStart
		if elapsed >= CHANNEL_SECONDS then
			_completeChannel()
		end
	end

	-- Compute the current visual state.
	local now = _now()
	local cooldownLeft = _cooldownEndsAt - now
	if cooldownLeft < 0 then
		cooldownLeft = 0
	end

	-- Hide the button entirely until the player has a region; until then
	-- there's literally nowhere to teleport to.
	if _ownedSlotId == "" then
		_button.Visible = false
		return
	end
	_button.Visible = true

	if _flashUntil > now then
		_setLabel(_flashText, COLOR_FAIL)
		_setHint("")
		_setBackground(COLOR_BG_DISABLED)
		_setFill(0, COLOR_FILL_CHANNEL)
		return
	end

	if hrp and _isInOwnRegion(hrp) and _channelStart == nil then
		_setLabel("Already at base", COLOR_TEXT_DISABLED)
		_setHint("")
		_setBackground(COLOR_BG_DISABLED)
		_setFill(0, COLOR_FILL_CHANNEL)
		return
	end

	if cooldownLeft > 0 and _channelStart == nil then
		_setLabel(string.format("Wait %ds", math.ceil(cooldownLeft)), COLOR_TEXT_DISABLED)
		_setHint("Return to Base")
		_setBackground(COLOR_BG_DISABLED)
		-- Visualise cooldown drain: bar empties as time passes.
		local progress = cooldownLeft / math.max(_cooldownDuration, 0.001)
		_setFill(progress, COLOR_FILL_COOLDOWN)
		return
	end

	if _channelStart ~= nil then
		local elapsed = _now() - _channelStart
		_setLabel("Returning...", COLOR_TEXT)
		_setHint("Hold still")
		_setBackground(COLOR_BG)
		_setFill(elapsed / CHANNEL_SECONDS, COLOR_FILL_CHANNEL)
		return
	end

	-- Idle.
	_setLabel("Return to Base", COLOR_TEXT)
	_setHint("Hold to channel")
	_setBackground(COLOR_BG)
	_setFill(0, COLOR_FILL_CHANNEL)
end

local function _createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "ReturnToBase"
	_gui.ResetOnSpawn = false
	_gui.IgnoreGuiInset = true
	_gui.DisplayOrder = 5
	_gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -24)
	button.BackgroundColor3 = COLOR_BG
	button.BackgroundTransparency = 0.15
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = _gui
	_button = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_BORDER
	stroke.Thickness = 1
	stroke.Parent = button

	-- Progress fill sits behind the text, anchored bottom-left so it sweeps
	-- from left to right.
	_fill = Instance.new("Frame")
	_fill.Name = "Fill"
	_fill.Size = UDim2.new(0, 0, 1, 0)
	_fill.AnchorPoint = Vector2.new(0, 0)
	_fill.Position = UDim2.fromScale(0, 0)
	_fill.BackgroundColor3 = COLOR_FILL_CHANNEL
	_fill.BackgroundTransparency = 0.55
	_fill.BorderSizePixel = 0
	_fill.ZIndex = 1
	_fill.Parent = button

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 10)
	fillCorner.Parent = _fill

	_label = Instance.new("TextLabel")
	_label.Name = "Label"
	_label.Size = UDim2.new(1, -16, 0.6, 0)
	_label.Position = UDim2.new(0, 8, 0, 4)
	_label.BackgroundTransparency = 1
	_label.TextColor3 = COLOR_TEXT
	_label.Font = Enum.Font.GothamBold
	_label.TextSize = 18
	_label.TextXAlignment = Enum.TextXAlignment.Center
	_label.Text = "Return to Base"
	_label.ZIndex = 2
	_label.Parent = button

	_hint = Instance.new("TextLabel")
	_hint.Name = "Hint"
	_hint.Size = UDim2.new(1, -16, 0.4, 0)
	_hint.Position = UDim2.new(0, 8, 0.6, -4)
	_hint.BackgroundTransparency = 1
	_hint.TextColor3 = COLOR_TEXT_DISABLED
	_hint.Font = Enum.Font.Gotham
	_hint.TextSize = 12
	_hint.TextXAlignment = Enum.TextXAlignment.Center
	_hint.Text = "Hold to channel"
	_hint.ZIndex = 2
	_hint.Parent = button

	-- Press / release hooks. Both mouse and touch route through these on a
	-- TextButton, so we don't need separate input branches.
	button.MouseButton1Down:Connect(_tryStartChannel)
	button.MouseButton1Up:Connect(function()
		_cancelChannel(nil)
	end)
	-- Belt-and-suspender for touch: if the user drags off the button before
	-- lifting, MouseButton1Up doesn't always fire reliably. Watch global
	-- input-end events too.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			_cancelChannel(nil)
		end
	end)
end

function ReturnToBaseController:KnitInit() end

function ReturnToBaseController:KnitStart()
	_createUI()

	-- Pull the current owned region.
	task.spawn(function()
		local PlayerDataService = Knit.GetService("PlayerDataService")
		if PlayerDataService then
			local ok, data = PlayerDataService:Read():await()
			if ok and type(data) == "table" then
				local owned = data.OwnedRegionId
				if type(owned) == "string" and owned ~= "" then
					_ownedSlotId = owned
				end
			end
		end
	end)

	-- Keep the owned slot id fresh after first claim.
	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if not SpawnService then
			return
		end
		if SpawnService.RegionAssigned then
			SpawnService.RegionAssigned:Connect(function(slotId: string)
				if type(slotId) == "string" then
					_ownedSlotId = slotId
				end
			end)
		end
		-- Hydrate the cooldown in case the controller starts up mid-cooldown
		-- (e.g. character respawn or controller hot-reload during dev).
		local ok, state = SpawnService:GetReturnToBaseState():await()
		if ok and type(state) == "table" then
			if type(state.cooldownSeconds) == "number" then
				_cooldownDuration = state.cooldownSeconds
			end
			if type(state.remainingCooldown) == "number" and state.remainingCooldown > 0 then
				_cooldownEndsAt = _now() + state.remainingCooldown
			end
		end
	end)

	RunService.Heartbeat:Connect(_onHeartbeat)
end

return ReturnToBaseController
