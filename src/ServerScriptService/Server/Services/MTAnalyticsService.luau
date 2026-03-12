local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)

type AnalyticsEconomyFlowType = Enum.AnalyticsEconomyFlowType
type AnalyticsProgressionType = Enum.AnalyticsProgressionType
type Dictionary = { [string]: any }

--[=[
    @class MTAnalyticsService
    
    Wrapper for Roblox's Analytics Service.
    Used for tracking player behavior throughout the game.
]=]
local MTAnalyticsService = Knit.CreateService({
	Name = "MTAnalyticsService",
	Client = {},
})

local playerEventCounts = {}
local RATE_LIMIT = 10
local RATE_WINDOW = 60
--[=[
    Logs an event used to track custom metrics of a user in experience.
    
    @param player -- Player to track
    @param eventName -- Custom event name
    @param value -- Numeric value associated with the event
    @param customFields -- Optional additional data
]=]
function MTAnalyticsService:LogCustomEvent(
	player: Player,
	eventName: string,
	value: number,
	customFields: Dictionary?
): ()
	local userId = player.UserId
	local currentTime = os.time()

	if not playerEventCounts[userId] then
		playerEventCounts[userId] = { count = 0, windowStart = currentTime }
	end

	local playerData = playerEventCounts[userId]
	if currentTime - playerData.windowStart >= RATE_WINDOW then
		playerData.count = 0
		playerData.windowStart = currentTime
	end

	playerData.count += 1
	if playerData.count > RATE_LIMIT then
		return
	end

	if type(eventName) ~= "string" or #eventName > 50 then
		return
	end
	if type(value) ~= "number" or value ~= value then
		return
	end

	if customFields and #HttpService:JSONEncode(customFields) > 1000 then
		return
	end

	AnalyticsService:LogCustomEvent(player, eventName, value, customFields or {})
end

--[=[
    @class MTAnalyticsService.Client
    Client-side interface for analytics tracking
]=]

--[=[
    Client-facing method to log a custom event.
    
    @param player -- Player to track (automatically provided by Knit)
    @param eventName -- Custom event name
    @param value -- Numeric value associated with the event
    @param customFields -- Optional additional data
]=]
function MTAnalyticsService.Client:LogCustomEvent(
	player: Player,
	eventName: string,
	value: number,
	customFields: Dictionary?
): ()
	return self.Server:LogCustomEvent(player, eventName, value, customFields)
end

--[=[
    Logs an event used to track player actions related to in-game economy.
    
    @param player -- Player to track
    @param flowType -- Type of economy flow (e.g. SINK, SOURCE)
    @param currencyType -- Type of currency being used
    @param amount -- Amount of currency involved
    @param endingBalance -- Player's balance after transaction
    @param transactionType -- Description of transaction type
    @param itemSku -- Identifier for the item involved
    @param customFields -- Optional additional data
]=]
function MTAnalyticsService:LogEconomyEvent(
	player: Player,
	flowType: AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string,
	customFields: Dictionary?
): ()
	AnalyticsService:LogEconomyEvent(
		player,
		flowType,
		currencyType,
		amount,
		endingBalance,
		transactionType,
		itemSku,
		customFields or {}
	)
end

--[=[
    Logs an event used to track user actions stepping through a pre-planned funnel.
    
    @param player -- Player to track
    @param funnelName -- Name of the funnel
    @param funnelSessionId -- Unique identifier for this funnel session
    @param step -- Current step number in the funnel
    @param stepName -- Name of the current step
    @param customFields -- Optional additional data
]=]
function MTAnalyticsService:LogFunnelStepEvent(
	player: Player,
	funnelName: string,
	funnelSessionId: string,
	step: number,
	stepName: string,
	customFields: Dictionary?
): ()
	AnalyticsService:LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields or {})
end

--[=[
    Logs an event used to track user actions stepping through an onboarding funnel.
    
    @param player -- Player to track
    @param step -- Current step number in the onboarding process
    @param stepName -- Name of the current step
    @param customFields -- Optional additional data
]=]
function MTAnalyticsService:LogOnboardingFunnelStepEvent(
	player: Player,
	step: number,
	stepName: string,
	customFields: Dictionary?
): ()
	AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, customFields or {})
end

function MTAnalyticsService:KnitInit()
	Players.PlayerRemoving:Connect(function(player: Player)
		playerEventCounts[player.UserId] = nil
	end)
end

return MTAnalyticsService
