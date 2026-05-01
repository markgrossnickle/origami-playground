--!strict
--[[
	RegionToastController — pops a transient banner whenever the local player
	enters a different zone (Hearth / Region / Wilds). Auto-dismisses after a
	short hold + fade.

	Why this exists:
		The RegionHud shows "what region am I in" persistently in the top bar.
		That's good for at-a-glance, but it's easy to walk over a zone boundary
		and miss the change. The toast catches the eye for a couple seconds and
		then fades out, so crossing a boundary always registers visually.

	Triggers:
		* First update after the character spawns (announces wherever they are).
		* Every transition between distinct zone-keys.

	Zone-key encoding (so we can compare last vs current trivially):
		"hearth", "wilds", "regions:r:5"  (regions include slotId)

	The owned-region label flips to "Your Region" once we know the local
	player's slotId. We re-render the toast if ownership lands AFTER the first
	enter — e.g., player crossed into their region before the profile finished
	loading.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ZoneRegistry = require(ReplicatedStorage.Shared.ZoneRegistry)

local LocalPlayer = Players.LocalPlayer

local RegionToastController = Knit.CreateController({
	Name = "RegionToastController",
})

local TOAST_HOLD_SECONDS = 2.5
local TOAST_FADE_SECONDS = 0.6
local POLL_HZ = 4 -- four samples per second is plenty; zones are large

local COLOR_HEARTH = Color3.fromRGB(255, 220, 130)
local COLOR_OWNED = Color3.fromRGB(120, 230, 130)
local COLOR_OTHER = Color3.fromRGB(240, 200, 80)
local COLOR_WILDS = Color3.fromRGB(200, 180, 230)
local COLOR_BG = Color3.fromRGB(20, 20, 30)

local _ownedSlotId: string = ""
local _ownerNames: { [string]: string } = {} -- slotId → display name
local _lastZoneKey: string? = nil
local _gui: ScreenGui? = nil
local _frame: Frame? = nil
local _label: TextLabel? = nil
local _accent: Frame? = nil
local _hideAt: number = 0
local _activeTween: Tween? = nil

local function _zoneKey(wx: number, wz: number): (string, string?)
	local zone = ZoneRegistry.getZone(wx, wz)
	if zone == "hearth" then
		return "hearth", nil
	elseif zone == "regions" then
		local slotId = ZoneRegistry.getRegionAt(wx, wz)
		return string.format("regions:%s", slotId or "?"), slotId
	end
	return "wilds", nil
end

local function _toastTextAndColor(zoneKey: string, slotId: string?): (string, Color3)
	if zoneKey == "hearth" then
		return "The Hearth", COLOR_HEARTH
	elseif zoneKey == "wilds" then
		return "The Wilds", COLOR_WILDS
	end
	-- regions:r:X
	if slotId == nil then
		return "Region", COLOR_OTHER
	end
	local ownerName = _ownerNames[slotId]
	if _ownedSlotId ~= "" and slotId == _ownedSlotId then
		if ownerName ~= nil and ownerName ~= "" then
			return string.format("Your Region — %s", ownerName), COLOR_OWNED
		end
		return "Your Region", COLOR_OWNED
	end
	if ownerName ~= nil and ownerName ~= "" then
		return string.format("%s's Region", ownerName), COLOR_OTHER
	end
	-- Owner not yet known → "Unclaimed Region" reads better than slotId.
	return "Unclaimed Region", COLOR_OTHER
end

local function _createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "RegionToast"
	_gui.ResetOnSpawn = false
	_gui.IgnoreGuiInset = true
	_gui.DisplayOrder = 5
	_gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Sit just below the RegionHud (which is at y=8 with height=36).
	_frame = Instance.new("Frame")
	_frame.Name = "Toast"
	_frame.Size = UDim2.new(0, 280, 0, 44)
	_frame.Position = UDim2.new(0.5, -140, 0, 56)
	_frame.BackgroundColor3 = COLOR_BG
	_frame.BackgroundTransparency = 1 -- start hidden
	_frame.BorderSizePixel = 0
	_frame.Visible = false
	_frame.Parent = _gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = _frame

	-- Coloured accent stripe on the left so you can read the zone at a glance.
	_accent = Instance.new("Frame")
	_accent.Name = "Accent"
	_accent.Size = UDim2.new(0, 4, 1, 0)
	_accent.Position = UDim2.new(0, 0, 0, 0)
	_accent.BackgroundColor3 = COLOR_HEARTH
	_accent.BackgroundTransparency = 1
	_accent.BorderSizePixel = 0
	_accent.Parent = _frame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = _accent

	_label = Instance.new("TextLabel")
	_label.Name = "Label"
	_label.Size = UDim2.new(1, -16, 1, 0)
	_label.Position = UDim2.new(0, 12, 0, 0)
	_label.BackgroundTransparency = 1
	_label.TextColor3 = Color3.fromRGB(240, 240, 240)
	_label.TextTransparency = 1
	_label.Font = Enum.Font.GothamBold
	_label.TextSize = 18
	_label.TextXAlignment = Enum.TextXAlignment.Center
	_label.Text = ""
	_label.Parent = _frame
end

local function _showToast(text: string, accent: Color3)
	if not (_frame and _label and _accent) then
		return
	end
	if _activeTween then
		_activeTween:Cancel()
		_activeTween = nil
	end
	_label.Text = text
	_accent.BackgroundColor3 = accent
	_frame.Visible = true

	-- Snap to fully visible.
	_frame.BackgroundTransparency = 0.15
	_label.TextTransparency = 0
	_accent.BackgroundTransparency = 0

	_hideAt = os.clock() + TOAST_HOLD_SECONDS
end

local function _stepFade()
	if not (_frame and _label and _accent and _frame.Visible) then
		return
	end
	if os.clock() < _hideAt then
		return
	end
	if _activeTween then
		return -- already fading
	end
	local info = TweenInfo.new(TOAST_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	_activeTween = TweenService:Create(_frame, info, { BackgroundTransparency = 1 })
	local labelTween = TweenService:Create(_label, info, { TextTransparency = 1 })
	local accentTween = TweenService:Create(_accent, info, { BackgroundTransparency = 1 })
	_activeTween:Play()
	labelTween:Play()
	accentTween:Play()
	_activeTween.Completed:Connect(function()
		if _frame then
			_frame.Visible = false
		end
		_activeTween = nil
	end)
end

local _accumulator = 0
local function _onHeartbeat(dt: number)
	_accumulator += dt
	local sampleEvery = 1 / POLL_HZ
	if _accumulator < sampleEvery then
		_stepFade()
		return
	end
	_accumulator = 0

	local character = LocalPlayer.Character
	if not character then
		_stepFade()
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		_stepFade()
		return
	end

	local pos = hrp.Position
	local key, slotId = _zoneKey(pos.X, pos.Z)
	if key ~= _lastZoneKey then
		_lastZoneKey = key
		local text, color = _toastTextAndColor(key, slotId)
		_showToast(text, color)
	end
	_stepFade()
end

-- Re-show the toast when ownership info arrives after we already announced
-- "Region N" and now know it's actually "Your Region".
local function _onOwnedSlotResolved(slotId: string)
	if type(slotId) ~= "string" or slotId == "" then
		return
	end
	_ownedSlotId = slotId
	if _lastZoneKey == nil then
		return
	end
	if _lastZoneKey ~= string.format("regions:%s", slotId) then
		return
	end
	-- Player is currently inside their own region; re-toast with the upgraded
	-- label so they don't keep seeing "Region 5" until the next boundary.
	local text, color = _toastTextAndColor(_lastZoneKey, slotId)
	_showToast(text, color)
end

function RegionToastController:KnitInit() end

function RegionToastController:KnitStart()
	_createUI()

	-- Read owned region from profile (returning players already have one).
	task.spawn(function()
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local ok, data = PlayerDataService:Read():await()
		if ok and type(data) == "table" then
			local owned = data.OwnedRegionId
			if type(owned) == "string" and owned ~= "" then
				_onOwnedSlotResolved(owned)
			end
		end
	end)

	-- Listen for first-claim assignment.
	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if SpawnService and SpawnService.RegionAssigned then
			SpawnService.RegionAssigned:Connect(_onOwnedSlotResolved)
		end
	end)

	-- Pull the owner-name table once and stay live on changes. The toast
	-- text re-renders on owner-name arrival when the player is currently
	-- inside the slot whose name just resolved (toast was probably showing
	-- "Unclaimed Region" or stale info).
	task.spawn(function()
		local RegionService = Knit.GetService("RegionService")
		if not RegionService then
			return
		end
		local ok, snapshot = RegionService:GetClaimedSlots():await()
		if ok and type(snapshot) == "table" then
			for slotId, entry in snapshot do
				if type(entry) == "table" and type(entry.ownerName) == "string" then
					_ownerNames[slotId] = entry.ownerName
				end
			end
		end
		if RegionService.SlotOwnerChanged then
			RegionService.SlotOwnerChanged:Connect(function(slotId: string, _userId: number, ownerName: string)
				if type(slotId) ~= "string" or type(ownerName) ~= "string" or ownerName == "" then
					return
				end
				_ownerNames[slotId] = ownerName
				-- If we're currently inside that slot, refresh the toast so
				-- the player sees the updated label without leaving and
				-- re-entering the boundary.
				if _lastZoneKey == string.format("regions:%s", slotId) then
					local text, color = _toastTextAndColor(_lastZoneKey, slotId)
					_showToast(text, color)
				end
			end)
		end
	end)

	RunService.Heartbeat:Connect(_onHeartbeat)
end

return RegionToastController
