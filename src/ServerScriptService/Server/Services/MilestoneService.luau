--!strict
--[[
	MilestoneService — First* milestone bookkeeping + onboarding funnel bumps
	for Origami Expedition.

	Pattern: every RecordFirstX method reads the milestone flag from
	PlayerData.Milestones, returns early if it's already set, otherwise writes
	the flag and fires the corresponding analytics event through
	AnalyticsService. Each call site at the trigger location is a one-liner.

	The onboarding funnel measures the GDD's "10-Minute Hook" (spawn -> mine ->
	find ore -> open the workbench -> craft -> claim). Funnel bumps are
	monotonic: a write only happens when the new step index strictly exceeds
	the persisted one. Funnel state lives under PlayerData.Funnels.Onboarding.

	NO retention funnel — Roblox tracks D1/D7/D30 retention natively, so a
	custom one is redundant. NO daily-prompt milestone — Origami has no daily
	prompt mechanic.

	NO PII: call sites must never pass DisplayName, prompt text, or any
	user-generated string. Numeric values + enum strings only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local MilestoneService = Knit.CreateService({
	Name = "MilestoneService",
	Client = {},
})

-- Onboarding funnel step indices. Keep ascending + contiguous so the
-- analytics dashboard reads drop-off left to right.
local FUNNEL = {
	SpawnedIn = 1,
	BlockMined = 2,
	OreFound = 3,
	CraftStarted = 4,
	CraftClaimed = 5,
}

-- Session-start timestamps used to compute SessionSummary.durationSec.
local _sessionStartClock: { [Player]: number } = {}
-- Phase the player was last seen in ("surface" | "regions" | "wilds" | etc).
-- Updated by NotePhase, read by RecordSessionSummary so the endPhase field
-- reflects "where did they quit from". Defaults to "spawn".
local _lastPhase: { [Player]: string } = {}
-- Guards the dual subscribe (ProfileReady + WaitForProfile fallback) from
-- double-firing PlayerJoined for the same player.
local _joinHandled: { [Player]: boolean } = {}

-- ── Internal helpers ───────────────────────────────────────────────────────

local function getAnalytics()
	return Knit.GetService("AnalyticsService")
end

local function getPlayerData()
	return Knit.GetService("PlayerDataService")
end

local function readMilestone(player: Player, name: string): boolean
	local PlayerDataService = getPlayerData()
	local milestones = PlayerDataService:Read(player, { "Milestones" })
	if type(milestones) ~= "table" then
		return false
	end
	return milestones[name] == true
end

local function writeMilestone(player: Player, name: string)
	local PlayerDataService = getPlayerData()
	local milestones = PlayerDataService:Read(player, { "Milestones" })
	if type(milestones) ~= "table" then
		milestones = {}
	end
	milestones[name] = true
	PlayerDataService:Write(player, { "Milestones" }, milestones)
end

local function readOnboarding(player: Player): number
	local PlayerDataService = getPlayerData()
	local funnels = PlayerDataService:Read(player, { "Funnels" })
	if type(funnels) ~= "table" then
		return 0
	end
	local v = funnels.Onboarding
	return if type(v) == "number" then v else 0
end

local function writeOnboarding(player: Player, value: number)
	local PlayerDataService = getPlayerData()
	local funnels = PlayerDataService:Read(player, { "Funnels" })
	if type(funnels) ~= "table" then
		funnels = { Onboarding = 0 }
	end
	funnels.Onboarding = value
	PlayerDataService:Write(player, { "Funnels" }, funnels)
end

-- Fire a First* milestone event. `funnelStep`/`funnelStepName` optional — if
-- supplied, also bumps the onboarding funnel. Returns true if this was the
-- first time (so callers can chain one-shot side effects).
local function fireFirst(
	player: Player,
	milestoneName: string,
	eventName: string,
	value: number,
	customFields: { [string]: any }?,
	funnelStep: number?,
	funnelStepName: string?
): boolean
	if readMilestone(player, milestoneName) then
		return false
	end
	writeMilestone(player, milestoneName)
	getAnalytics():LogCustomEvent(player, eventName, value, customFields)
	if funnelStep and funnelStepName then
		MilestoneService:BumpOnboardingFunnel(player, funnelStep, funnelStepName)
	end
	return true
end

-- ── Onboarding funnel ──────────────────────────────────────────────────────

function MilestoneService:BumpOnboardingFunnel(player: Player, targetStep: number, stepName: string)
	if type(targetStep) ~= "number" or targetStep < 1 or targetStep > 100 then
		return
	end
	if type(stepName) ~= "string" or #stepName == 0 then
		return
	end
	local current = readOnboarding(player)
	if targetStep <= current then
		return
	end
	writeOnboarding(player, targetStep)
	getAnalytics():LogOnboardingFunnelStep(player, targetStep, stepName)
end

function MilestoneService:GetOnboardingStep(player: Player): number
	return readOnboarding(player)
end

-- ── Phase tracking (consumed by SessionSummary) ────────────────────────────

function MilestoneService:NotePhase(player: Player, phase: string)
	if type(phase) == "string" and #phase > 0 then
		_lastPhase[player] = phase
	end
end

-- ── PlayerJoined / SessionSummary ──────────────────────────────────────────

function MilestoneService:RecordPlayerJoined(player: Player)
	if _joinHandled[player] then
		return
	end
	_joinHandled[player] = true

	_sessionStartClock[player] = os.clock()
	_lastPhase[player] = "spawn"

	-- Funnel baseline: everyone who loads in is step 1. Drop-off from here is
	-- the first thing the dashboard should show.
	self:BumpOnboardingFunnel(player, FUNNEL.SpawnedIn, "SpawnedIn")
end

function MilestoneService:RecordSessionSummary(player: Player)
	local startClock = _sessionStartClock[player]
	local durationSec = if startClock then math.floor(os.clock() - startClock) else 0
	local endPhase = _lastPhase[player] or "spawn"

	getAnalytics():LogCustomEvent(player, "SessionSummary", durationSec, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "endPhase=" .. endPhase,
	})

	_sessionStartClock[player] = nil
	_lastPhase[player] = nil
end

-- ── First* milestone records ───────────────────────────────────────────────

function MilestoneService:RecordFirstBlockMined(player: Player, blockTypeId: number)
	fireFirst(player, "FirstBlockMined", "FirstBlockMined", blockTypeId, nil, FUNNEL.BlockMined, "BlockMined")
end

function MilestoneService:RecordFirstOreFound(player: Player, oreItemId: string)
	-- oreItemId is a canonical item id (e.g. "inkdrop"), NOT user content —
	-- safe to log as a custom field for per-ore funnel breakdowns.
	fireFirst(player, "FirstOreFound", "FirstOreFound", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "ore=" .. tostring(oreItemId),
	}, FUNNEL.OreFound, "OreFound")
end

function MilestoneService:RecordFirstBlockPlaced(player: Player)
	fireFirst(player, "FirstBlockPlaced", "FirstBlockPlaced", 1)
end

function MilestoneService:RecordFirstRegionClaimed(player: Player)
	fireFirst(player, "FirstRegionClaimed", "FirstRegionClaimed", 1)
end

function MilestoneService:RecordFirstReturnToBase(player: Player)
	fireFirst(player, "FirstReturnToBase", "FirstReturnToBase", 1)
end

function MilestoneService:RecordFirstCraftStarted(player: Player, recipeId: string)
	fireFirst(player, "FirstCraftStarted", "FirstCraftStarted", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "recipe=" .. tostring(recipeId),
	}, FUNNEL.CraftStarted, "CraftStarted")
end

function MilestoneService:RecordFirstCraftClaimed(player: Player, itemType: string)
	fireFirst(player, "FirstCraftClaimed", "FirstCraftClaimed", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "itemType=" .. tostring(itemType),
	}, FUNNEL.CraftClaimed, "CraftClaimed")
end

function MilestoneService:RecordFirstGiftSent(player: Player)
	fireFirst(player, "FirstGiftSent", "FirstGiftSent", 1)
end

-- ── Client API ─────────────────────────────────────────────────────────────

function MilestoneService.Client:GetOnboardingStep(player: Player): number
	return self.Server:GetOnboardingStep(player)
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function MilestoneService:KnitInit() end

function MilestoneService:KnitStart()
	local PlayerDataService = getPlayerData()

	-- Fire RecordPlayerJoined AFTER the profile is loaded — Read/Write are
	-- no-ops (they yield-then-expect) otherwise.
	PlayerDataService.ProfileReady:Connect(function(player: Player)
		self:RecordPlayerJoined(player)
	end)

	-- Catch profiles that loaded before this service finished KnitStart.
	-- _joinHandled guards against the ProfileReady connection double-firing.
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			local ok = PlayerDataService:WaitForProfile(player):await()
			if ok and player.Parent then
				self:RecordPlayerJoined(player)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		if _sessionStartClock[player] then
			self:RecordSessionSummary(player)
		end
		_joinHandled[player] = nil
	end)
end

return MilestoneService
