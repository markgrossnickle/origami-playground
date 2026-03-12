--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxAnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerDataService

-- Session tracking per player
local sessionStartTimes: { [Player]: number } = {}
local serverStartTime = os.clock()

--[=[
	@class AnalyticsService
	Lightweight analytics using Roblox's built-in AnalyticsService.
	Tracks sessions, custom events, funnels, and economy flows.
]=]
local AnalyticsService = Knit.CreateService({
	Name = "AnalyticsService",
	Client = {},
})

-- ============================================================================
-- Session Tracking
-- ============================================================================

function AnalyticsService:_onPlayerJoined(player: Player)
	sessionStartTimes[player] = os.clock()

	PlayerDataService:WaitForProfile(player)
		:andThen(function()
			local today = os.date("!%Y-%m-%d", os.time())

			-- Update session count
			local sessionCount = PlayerDataService:Read(player, { "SessionCount" }) or 0
			PlayerDataService:Write(player, { "SessionCount" }, sessionCount + 1)

			-- Set first join date if not set
			local firstJoinDate = PlayerDataService:Read(player, { "FirstJoinDate" })
			if not firstJoinDate or firstJoinDate == "" then
				PlayerDataService:Write(player, { "FirstJoinDate" }, today)
			end

			-- Record session start time
			PlayerDataService:Write(player, { "LastSessionStart" }, os.time())

			-- Log join event
			self:TrackEvent(player, "Session", "PlayerJoined", nil, nil)
		end)
		:catch(function(err)
			warn(`AnalyticsService: Session setup error for {player.Name}: {err}`)
		end)
end

function AnalyticsService:_onPlayerLeft(player: Player)
	local startTime = sessionStartTimes[player]
	if startTime then
		local sessionDuration = math.floor(os.clock() - startTime)
		sessionStartTimes[player] = nil

		-- Update total play time
		PlayerDataService:WaitForProfile(player)
			:andThen(function()
				local totalPlayTime = PlayerDataService:Read(player, { "TotalPlayTime" }) or 0
				PlayerDataService:Write(player, { "TotalPlayTime" }, totalPlayTime + sessionDuration)
			end)
			:catch(function() end) -- Player may already be gone

		-- Log leave event with duration
		self:TrackEvent(player, "Session", "PlayerLeft", nil, sessionDuration)
	end
end

-- ============================================================================
-- Custom Events
-- ============================================================================

function AnalyticsService:TrackEvent(player: Player, category: string, action: string, label: string?, value: number?)
	local eventName = `{category}_{action}`
	local customFields: { [string]: any } = {}
	if label then
		customFields["label"] = label
	end

	pcall(function()
		RobloxAnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
	end)
end

function AnalyticsService:TrackFunnel(player: Player, funnelName: string, step: number, stepName: string?)
	local sessionId = HttpService:GenerateGUID(false)
	pcall(function()
		RobloxAnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName or `Step{step}`, {})
	end)
end

function AnalyticsService:TrackEconomy(
	player: Player,
	currency: string,
	amount: number,
	flowType: string,
	context: string
)
	local economyFlowType = if flowType == "Source"
		then Enum.AnalyticsEconomyFlowType.Source
		else Enum.AnalyticsEconomyFlowType.Sink

	-- Read current balance for endingBalance
	local balance = PlayerDataService:Read(player, { currency }) or 0

	pcall(function()
		RobloxAnalyticsService:LogEconomyEvent(player, economyFlowType, currency, amount, balance, context, context, {})
	end)
end

-- ============================================================================
-- Pre-built Event Helpers
-- ============================================================================

function AnalyticsService:LevelUp(player: Player, level: number)
	self:TrackEvent(player, "Progression", "LevelUp", nil, level)
	pcall(function()
		RobloxAnalyticsService:LogOnboardingFunnelStepEvent(player, level, `Level{level}`, {})
	end)
end

function AnalyticsService:ItemPurchased(player: Player, item: string, currency: string, amount: number)
	self:TrackEvent(player, "Economy", "ItemPurchased", item, amount)
	self:TrackEconomy(player, currency, amount, "Sink", `ShopPurchase_{item}`)
end

function AnalyticsService:StageCompleted(player: Player, stage: string, time: number)
	self:TrackEvent(player, "Progression", "StageCompleted", stage, time)
end

function AnalyticsService:PlayerDied(player: Player, cause: string)
	self:TrackEvent(player, "Gameplay", "PlayerDied", cause, nil)
end

-- ============================================================================
-- Server Stats
-- ============================================================================

function AnalyticsService:GetServerStats(): { [string]: any }
	return {
		PlayerCount = #Players:GetPlayers(),
		Uptime = math.floor(os.clock() - serverStartTime),
		ServerStartTime = serverStartTime,
	}
end

-- ============================================================================
-- Client API
-- ============================================================================

function AnalyticsService.Client:GetServerStats(_player: Player)
	return self.Server:GetServerStats()
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function AnalyticsService:KnitInit()
	PlayerDataService = Knit.GetService("PlayerDataService")

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:_onPlayerJoined(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerLeft(player)
	end)
end

function AnalyticsService:KnitStart()
	-- Handle players already in game
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_onPlayerJoined(player)
		end)
	end
end

return AnalyticsService
