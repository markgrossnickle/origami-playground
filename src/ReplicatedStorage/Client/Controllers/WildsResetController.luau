--!strict
--[[
	WildsResetController — surfaces the weekly Wilds reset to the player:

	  * A countdown chip (top-left) that appears only inside the final window
	    before a reset (default 15 min), so players in the Wilds know to wrap
	    up / anticipate the fresh-ore rush. Counts down locally and re-syncs
	    from WildsService:GetSecondsUntilReset every 60s to correct drift.

	  * A center banner on the WildsReset signal — "The Wilds have reset —
	    fresh ore!" — that holds briefly then fades. This is the GDD's
	    "scheduled world event with anticipation" payoff.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LocalPlayer = Players.LocalPlayer

local WildsResetController = Knit.CreateController({
	Name = "WildsResetController",
})

-- Only show the chip within this many seconds of the reset.
local COUNTDOWN_VISIBLE_WINDOW = 15 * 60
-- Re-sync the authoritative seconds-remaining this often.
local RESYNC_INTERVAL = 60
local BANNER_HOLD = 4
local BANNER_FADE = 0.8

local COLOR_BG = Color3.fromRGB(20, 20, 30)
local COLOR_WARN = Color3.fromRGB(245, 200, 90)
local COLOR_FRESH = Color3.fromRGB(130, 230, 150)

-- Local mirror of seconds-until-reset; ticked down each frame, re-synced
-- from the server periodically. -1 = unknown (not yet fetched).
local _secondsRemaining = -1
local _lastResync = 0

local _chip: Frame? = nil
local _chipLabel: TextLabel? = nil
local _banner: Frame? = nil
local _bannerLabel: TextLabel? = nil
local _bannerHideAt = 0
local _bannerTween: Tween? = nil

local function _fmt(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local m = math.floor(s / 60)
	local rem = s % 60
	return string.format("%d:%02d", m, rem)
end

local function _createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WildsReset"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Countdown chip, top-left (clear of minimap/HUD/RTB).
	local chip = Instance.new("Frame")
	chip.Name = "Countdown"
	chip.Size = UDim2.fromOffset(190, 32)
	chip.Position = UDim2.new(0, 12, 0, 12)
	chip.BackgroundColor3 = COLOR_BG
	chip.BackgroundTransparency = 0.2
	chip.BorderSizePixel = 0
	chip.Visible = false
	chip.Parent = gui
	_chip = chip

	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 8)
	chipCorner.Parent = chip

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = COLOR_WARN
	accent.BorderSizePixel = 0
	accent.Parent = chip
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = accent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -14, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = chip
	_chipLabel = label

	-- Reset banner, upper-center.
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.fromOffset(360, 52)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 110)
	banner.BackgroundColor3 = COLOR_BG
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	_banner = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner

	local bannerLabel = Instance.new("TextLabel")
	bannerLabel.Name = "Label"
	bannerLabel.Size = UDim2.fromScale(1, 1)
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.TextColor3 = COLOR_FRESH
	bannerLabel.TextTransparency = 1
	bannerLabel.Font = Enum.Font.GothamBold
	bannerLabel.TextSize = 20
	bannerLabel.Text = "The Wilds have reset — fresh ore!"
	bannerLabel.Parent = banner
	_bannerLabel = bannerLabel
end

local function _showBanner()
	if not (_banner and _bannerLabel) then
		return
	end
	if _bannerTween then
		_bannerTween:Cancel()
		_bannerTween = nil
	end
	_banner.Visible = true
	_banner.BackgroundTransparency = 0.15
	_bannerLabel.TextTransparency = 0
	_bannerHideAt = os.clock() + BANNER_HOLD
end

local function _stepBanner()
	if not (_banner and _bannerLabel and _banner.Visible) then
		return
	end
	if os.clock() < _bannerHideAt or _bannerTween then
		return
	end
	local info = TweenInfo.new(BANNER_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	_bannerTween = TweenService:Create(_banner, info, { BackgroundTransparency = 1 })
	local labelTween = TweenService:Create(_bannerLabel, info, { TextTransparency = 1 })
	_bannerTween:Play()
	labelTween:Play()
	_bannerTween.Completed:Connect(function()
		if _banner then
			_banner.Visible = false
		end
		_bannerTween = nil
	end)
end

local function _onHeartbeat(dt: number)
	if _secondsRemaining >= 0 then
		_secondsRemaining = math.max(0, _secondsRemaining - dt)
	end

	if _chip and _chipLabel then
		if _secondsRemaining >= 0 and _secondsRemaining <= COUNTDOWN_VISIBLE_WINDOW then
			_chip.Visible = true
			_chipLabel.Text = "Wilds reset in " .. _fmt(_secondsRemaining)
		else
			_chip.Visible = false
		end
	end

	_stepBanner()
end

function WildsResetController:KnitInit() end

function WildsResetController:KnitStart()
	_createUI()

	local WildsService = Knit.GetService("WildsService")

	local function resync()
		if not WildsService then
			return
		end
		local ok, seconds = WildsService:GetSecondsUntilReset():await()
		if ok and type(seconds) == "number" then
			_secondsRemaining = seconds
		end
	end

	task.spawn(resync)

	if WildsService and WildsService.WildsReset then
		WildsService.WildsReset:Connect(function(_resetTs: number)
			_showBanner()
			-- A reset just happened; the next one is a full week out. Re-pull
			-- so the chip hides immediately instead of ticking to 0 and waiting.
			task.spawn(resync)
		end)
	end

	RunService.Heartbeat:Connect(function(dt: number)
		_onHeartbeat(dt)
		if os.clock() - _lastResync >= RESYNC_INTERVAL then
			_lastResync = os.clock()
			task.spawn(resync)
		end
	end)
end

return WildsResetController
