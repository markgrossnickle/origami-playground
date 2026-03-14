-- GameModeController: Horizontal mode bar at top-center of screen
-- Clicking a mode calls GameMode:SetMode(key) which fires Changed signal

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)

local Player = Players.LocalPlayer

local GameModeController = Knit.CreateController({
	Name = "GameModeController",
})

local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(100, 180, 255),
	accentDim = Color3.fromRGB(60, 100, 160),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
}

local _gui: ScreenGui
local _modeButtons: { [string]: TextButton } = {}

local function updateHighlights()
	for key, btn in pairs(_modeButtons) do
		if key == GameMode.Current then
			btn.BackgroundColor3 = COLORS.accent
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
end

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "GameModeBar"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 10
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Bar container at top-center
	local bar = Instance.new("Frame")
	bar.Name = "ModeBar"
	bar.Size = UDim2.new(0, 0, 0, 36)
	bar.Position = UDim2.new(0.5, 0, 0, 8)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundColor3 = COLORS.bg
	bar.BackgroundTransparency = 0.1
	bar.BorderSizePixel = 0
	bar.Parent = _gui

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 10)
	barCorner.Parent = bar

	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0, 4)
	barPadding.PaddingRight = UDim.new(0, 4)
	barPadding.PaddingTop = UDim.new(0, 4)
	barPadding.PaddingBottom = UDim.new(0, 4)
	barPadding.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = bar

	-- Close button (first in layout)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.BackgroundColor3 = COLORS.bgLight
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.textDim
	closeBtn.TextSize = 12
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.AutoButtonColor = true
	closeBtn.LayoutOrder = 0
	closeBtn.Parent = bar

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 6)
	closeBtnCorner.Parent = closeBtn

	closeBtn.Activated:Connect(function()
		GameModeController:Hide()
	end)

	for i, mode in ipairs(GameMode.MODES) do
		local btn = Instance.new("TextButton")
		btn.Name = "Mode_" .. mode.key
		btn.Size = UDim2.new(0, 100, 0, 28)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = mode.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.LayoutOrder = i
		btn.Parent = bar

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_modeButtons[mode.key] = btn

		btn.Activated:Connect(function()
			GameMode.SetMode(mode.key)
		end)
	end

	-- Start hidden (opened via sidebar)
	_gui.Enabled = false
	_gui.Parent = Player.PlayerGui

	-- Listen for mode changes to update highlights
	GameMode.Changed:Connect(function()
		updateHighlights()
	end)

	updateHighlights()
end

function GameModeController:Toggle()
	if _gui then
		_gui.Enabled = not _gui.Enabled
	end
end

function GameModeController:Show()
	if _gui then
		_gui.Enabled = true
	end
end

function GameModeController:Hide()
	if _gui then
		_gui.Enabled = false
	end
end

function GameModeController:IsVisible(): boolean
	return _gui ~= nil and _gui.Enabled
end

function GameModeController:KnitInit() end

function GameModeController:KnitStart()
	createUI()
end

return GameModeController
