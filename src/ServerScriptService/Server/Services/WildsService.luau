--!strict
--[[
	WildsService — orchestrates the GDD's weekly Wilds reset (lines 391-399):
	a scheduled world event that restores all Wilds terrain to its procedural
	base (placed blocks removed, mined blocks + ore pockets restored).

	Mechanics, given the voxel model (base terrain is deterministic from the
	seed; player edits are stored as deltas):
	  * The reset = drop every Wilds chunk's delta. Ore veins are baked into
	    worldgen, so they reappear at their original positions automatically.
	  * WorldService owns the data ops (ResetWildsPersistedDeltas for the
	    DataStore wipe, ResetWildsInMemory for live chunks). This service owns
	    the schedule + cross-server coordination.

	Coordination (many servers share one world):
	  * Schedule is a fixed weekly boundary (UTC weekday + hour) every server
	    computes locally — no DataStore needed for the countdown.
	  * When a boundary passes, servers race to claim it via an atomic
	    UpdateAsync on an election key. Exactly one wins and performs the
	    DataStore wipe, then publishes to MessagingService.
	  * Every server (winner directly, others via the message OR by noticing
	    the election key already advanced) resets its own in-memory Wilds
	    chunks so live players everywhere see fresh terrain and no server
	    re-persists the cleared deltas.

	Auto-returning player-placed creatures/items in the Wilds (GDD) is a
	follow-up — there's no Wilds creature-placement system wired yet, so
	there's nothing to return today. Hooked here when that lands.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local WildsService = Knit.CreateService({
	Name = "WildsService",
	Client = {
		-- Fired on every server when a reset completes. Payload: resetTs (the
		-- boundary unix time). Clients show a "fresh ore" banner.
		WildsReset = Knit.CreateSignal(),
	},
})

-- Weekly boundary: Sunday 08:00 UTC (morning across NA, midday EU). os.date
-- wday is 1=Sunday .. 7=Saturday.
local RESET_WDAY = 1
local RESET_HOUR = 8

local ELECTION_STORE = "WildsReset_v1"
local ELECTION_KEY = "LastResetTs"
local MESSAGING_TOPIC = "WildsReset"

-- How often each server checks whether a reset boundary has passed. The
-- MessagingService publish makes the winner's peers react in ~1s; this poll
-- is the backstop if a message is dropped.
local CHECK_INTERVAL = 30

local WorldService

local _electionStore: DataStore? = nil
-- Highest reset boundary this server has already accounted for (claimed,
-- applied, or read from the election key at startup). Trigger compares the
-- due boundary against this so we act exactly once per boundary.
local _lastResetTs = 0

local function _isStudio(): boolean
	return RunService:IsStudio()
end

-- Most recent reset boundary at or before `now`.
local function _previousResetTime(now: number): number
	local t = os.date("!*t", now)
	local daysSince = (t.wday - RESET_WDAY) % 7
	local midnightUTC = now - (t.hour * 3600 + t.min * 60 + t.sec)
	local candidate = midnightUTC - daysSince * 86400 + RESET_HOUR * 3600
	if candidate > now then
		candidate -= 7 * 86400
	end
	return candidate
end

local function _nextResetTime(now: number): number
	return _previousResetTime(now) + 7 * 86400
end

-- Apply the reset to THIS server: regenerate loaded Wilds chunks + tell our
-- clients. Idempotent per boundary via _lastResetTs.
function WildsService:_applyResetLocally(resetTs: number)
	if resetTs <= _lastResetTs then
		return
	end
	_lastResetTs = resetTs

	local count = 0
	if WorldService then
		count = WorldService:ResetWildsInMemory()
	end
	print(string.format("[WildsService] Wilds reset applied locally (%d chunks regenerated)", count))

	self.Client.WildsReset:FireAll(resetTs)
end

local function _publishReset(resetTs: number)
	if _isStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(MESSAGING_TOPIC, {
				resetTs = resetTs,
				senderJobId = game.JobId,
			})
		end)
		if not ok then
			warn("[WildsService] PublishAsync failed:", err)
		end
	end)
end

local function _subscribeMessaging(self)
	if _isStudio() then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(MESSAGING_TOPIC, function(message)
				local payload = message and message.Data
				if type(payload) ~= "table" then
					return
				end
				-- Skip our own publish — the winner applies locally directly.
				if payload.senderJobId == game.JobId then
					return
				end
				local resetTs = payload.resetTs
				if type(resetTs) == "number" then
					self:_applyResetLocally(resetTs)
				end
			end)
		end)
		if not ok then
			warn("[WildsService] SubscribeAsync failed:", err)
		end
	end)
end

-- Try to claim the right to perform the wipe for boundary `dueTs`.
-- Returns "won" | "already_done" | "error".
local function _claimReset(dueTs: number): string
	if _isStudio() or _electionStore == nil then
		return "won" -- single authoritative server in Studio
	end
	local won = false
	local ok, err = pcall(function()
		(_electionStore :: DataStore):UpdateAsync(ELECTION_KEY, function(stored)
			local prev = (type(stored) == "number") and stored or 0
			if prev >= dueTs then
				won = false
				return nil -- abort the write — already claimed
			end
			won = true
			return dueTs
		end)
	end)
	if not ok then
		warn("[WildsService] Reset claim failed:", err)
		return "error"
	end
	return won and "won" or "already_done"
end

function WildsService:_checkSchedule()
	local now = os.time()
	local dueTs = _previousResetTime(now)
	if dueTs <= _lastResetTs then
		return -- already handled this boundary
	end

	local outcome = _claimReset(dueTs)
	if outcome == "won" then
		print("[WildsService] Won reset election for", dueTs, "— wiping Wilds deltas")
		if WorldService then
			local cleared = WorldService:ResetWildsPersistedDeltas()
			print(string.format("[WildsService] Cleared %d persisted Wilds chunk deltas", cleared))
		end
		_publishReset(dueTs)
		self:_applyResetLocally(dueTs)
	elseif outcome == "already_done" then
		-- Another server wiped the DataStore; our in-memory copy is now stale.
		-- Sync it even if we never received the MessagingService publish.
		self:_applyResetLocally(dueTs)
	end
	-- "error" → leave _lastResetTs untouched so the next poll retries.
end

-- Client-facing: seconds until the next reset, for the countdown UI. Pure
-- local computation — no DataStore round trip.
function WildsService.Client:GetSecondsUntilReset(_player: Player): number
	return math.max(0, _nextResetTime(os.time()) - os.time())
end

function WildsService:GetSecondsUntilReset(): number
	return math.max(0, _nextResetTime(os.time()) - os.time())
end

-- Manual trigger for testing (Studio only). Regenerates Wilds in-memory and
-- banners clients without touching the schedule's election state.
function WildsService:ForceReset()
	local count = 0
	if WorldService then
		count = WorldService:ResetWildsInMemory()
	end
	print(string.format("[WildsService] ForceReset: %d chunks regenerated", count))
	self.Client.WildsReset:FireAll(os.time())
end

function WildsService.Client:RequestForceReset(_player: Player)
	if not RunService:IsStudio() then
		return { success = false, error = "studio_only" }
	end
	WildsService:ForceReset()
	return { success = true }
end

function WildsService:KnitInit() end

function WildsService:KnitStart()
	WorldService = Knit.GetService("WorldService")

	if not _isStudio() then
		_electionStore = DataStoreService:GetDataStore(ELECTION_STORE)
	end

	-- Seed _lastResetTs so a freshly-started server doesn't think the current
	-- period's reset is still pending. Prefer the persisted election value;
	-- fall back to the most recent boundary (nothing to reset on first boot).
	local now = os.time()
	_lastResetTs = _previousResetTime(now)
	if _electionStore then
		local ok, stored = pcall(function()
			return (_electionStore :: DataStore):GetAsync(ELECTION_KEY)
		end)
		if ok and type(stored) == "number" and stored > _lastResetTs then
			_lastResetTs = stored
		end
	end

	_subscribeMessaging(self)

	-- Schedule poll loop.
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local ok, err = pcall(function()
				self:_checkSchedule()
			end)
			if not ok then
				warn("[WildsService] schedule check errored:", err)
			end
		end
	end)
end

return WildsService
