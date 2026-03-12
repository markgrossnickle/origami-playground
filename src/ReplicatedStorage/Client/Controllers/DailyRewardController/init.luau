--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)

local MonetizationConfig = require(ReplicatedStorage.Shared.MonetizationConfig)

local Player = Knit.Player
local PlayerGui = Player:WaitForChild("PlayerGui")

local IS_MOBILE = UserInputService.TouchEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()
local BUTTON_MIN_SIZE = 48

--[=[
	@class DailyRewardController
	Client UI for daily login rewards. Shows 7-day calendar popup on join.
]=]
local DailyRewardController = Knit.CreateController({
	Name = "DailyRewardController",
})

DailyRewardController._trove = Trove.new()
DailyRewardController._gui = nil :: ScreenGui?

-- ============================================================================
-- Helpers
-- ============================================================================

local function createTextSize(): number
	if IS_CONSOLE then
		return 24
	elseif IS_MOBILE then
		return 16
	end
	return 18
end

local function createInstance<T>(className: string, props: { [string]: any }): T
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst :: any
end

-- ============================================================================
-- UI
-- ============================================================================

function DailyRewardController:_showRewardPopup(
	currentDay: number,
	reward: MonetizationConfig.DailyReward,
	claimed: boolean
)
	-- Destroy existing popup
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end

	local textSize = createTextSize()
	local totalDays = #MonetizationConfig.DailyRewards
	local dayIndex = ((currentDay - 1) % totalDays) + 1

	local gui = createInstance("ScreenGui", {
		Name = "DailyRewardGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Parent = PlayerGui,
	}) :: ScreenGui
	self._gui = gui

	-- Overlay
	createInstance("Frame", {
		Name = "Overlay",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = gui,
	})

	-- Container
	local container = createInstance("Frame", {
		Name = "Container",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if IS_MOBILE then UDim2.fromScale(0.9, 0.5) else UDim2.fromScale(0.5, 0.45),
		BackgroundColor3 = Color3.fromRGB(30, 30, 45),
		Parent = gui,
	}) :: Frame
	createInstance("UICorner", { CornerRadius = UDim.new(0, 12), Parent = container })

	-- Title
	createInstance("TextLabel", {
		Name = "Title",
		Text = "Daily Rewards",
		Font = Enum.Font.GothamBold,
		TextSize = textSize + 6,
		TextColor3 = Color3.fromRGB(255, 215, 0),
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 8),
		BackgroundTransparency = 1,
		Parent = container,
	})

	-- Streak text
	createInstance("TextLabel", {
		Name = "Streak",
		Text = `Day {currentDay} Streak!`,
		Font = Enum.Font.GothamMedium,
		TextSize = textSize,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 48),
		BackgroundTransparency = 1,
		Parent = container,
	})

	-- Day cards frame
	local daysFrame = createInstance("Frame", {
		Name = "Days",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.new(1, -16, 0, if IS_MOBILE then 80 else 100),
		Position = UDim2.new(0.5, 0, 0, 78),
		BackgroundTransparency = 1,
		Parent = container,
	}) :: Frame
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		Parent = daysFrame,
	})

	for i = 1, totalDays do
		local dayReward = MonetizationConfig.DailyRewards[i]
		local isPast = i < dayIndex
		local isCurrent = i == dayIndex
		local isFuture = i > dayIndex

		local bgColor = if isPast
			then Color3.fromRGB(40, 80, 40)
			elseif isCurrent then Color3.fromRGB(80, 80, 200)
			else Color3.fromRGB(50, 50, 60)

		local card = createInstance("Frame", {
			Name = `Day{i}`,
			Size = UDim2.new(1 / totalDays, -6, 1, 0),
			BackgroundColor3 = bgColor,
			Parent = daysFrame,
		}) :: Frame
		createInstance("UICorner", { CornerRadius = UDim.new(0, 6), Parent = card })

		createInstance("TextLabel", {
			Name = "DayLabel",
			Text = `Day {i}`,
			Font = Enum.Font.GothamBold,
			TextSize = textSize - 4,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.new(0, 0, 0, 4),
			BackgroundTransparency = 1,
			Parent = card,
		})

		createInstance("TextLabel", {
			Name = "Reward",
			Text = dayReward.Description,
			Font = Enum.Font.Gotham,
			TextSize = textSize - 6,
			TextColor3 = if isFuture then Color3.fromRGB(120, 120, 120) else Color3.new(1, 1, 1),
			Size = UDim2.new(1, -4, 0, 30),
			Position = UDim2.new(0, 2, 0, 24),
			BackgroundTransparency = 1,
			TextWrapped = true,
			Parent = card,
		})

		-- Check mark for past days
		if isPast then
			createInstance("TextLabel", {
				Name = "Check",
				Text = "✓",
				Font = Enum.Font.GothamBold,
				TextSize = textSize,
				TextColor3 = Color3.fromRGB(100, 255, 100),
				Size = UDim2.new(1, 0, 0, 20),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -4),
				BackgroundTransparency = 1,
				Parent = card,
			})
		end
	end

	-- Claim button
	local claimBtn = createInstance("TextButton", {
		Name = "Claim",
		Text = if claimed then "Claimed!" else `Claim: {reward.Description}`,
		Font = Enum.Font.GothamBold,
		TextSize = textSize,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0.6, 0, 0, math.max(BUTTON_MIN_SIZE, 44)),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		BackgroundColor3 = if claimed then Color3.fromRGB(80, 80, 80) else Color3.fromRGB(60, 180, 60),
		Active = not claimed,
		Parent = container,
	}) :: TextButton
	createInstance("UICorner", { CornerRadius = UDim.new(0, 8), Parent = claimBtn })

	if not claimed then
		self._trove:Connect(claimBtn.Activated, function()
			claimBtn.Active = false
			claimBtn.Text = "..."
			claimBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

			task.spawn(function()
				local MonetizationService = Knit.GetService("MonetizationService")
				local ok, success = MonetizationService:ClaimLoginReward():await()
				if ok and success then
					claimBtn.Text = "Claimed!"
					claimBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
					-- Auto-dismiss after 2s
					task.wait(2)
					self:_dismiss()
				else
					claimBtn.Text = "Error - Try Again"
					claimBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
					claimBtn.Active = true
				end
			end)
		end)
	else
		-- Auto-dismiss claimed popup after 3s
		task.delay(3, function()
			self:_dismiss()
		end)
	end
end

function DailyRewardController:_dismiss()
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function DailyRewardController:KnitInit() end

function DailyRewardController:KnitStart()
	local MonetizationService = Knit.GetService("MonetizationService")

	-- Listen for login reward signal from server
	MonetizationService.LoginRewardReady:Connect(function(day: number, reward: any)
		self:_showRewardPopup(day, reward, false)
	end)

	-- Also check on start in case signal was missed
	task.spawn(function()
		task.wait(2) -- Give server time to process
		local ok, result = MonetizationService:GetLoginReward():await()
		if ok and result and not result.claimed then
			self:_showRewardPopup(result.day, result.reward, false)
		end
	end)
end

return DailyRewardController
