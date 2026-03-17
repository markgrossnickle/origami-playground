--[[
	BreedingService — server-side creature breeding.
	Two players bring creatures near each other, both confirm, pay Cranes,
	LLM generates offspring → egg spawns with 8-hour hatch timer.
	Players start with 1 egg slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local BreedingService = Knit.CreateService({
	Name = "BreedingService",
	Client = {
		BreedRequestReceived = Knit.CreateSignal(), -- (requestId, requesterName, creatureName)
		EggReady = Knit.CreateSignal(), -- (eggIndex)
	},
})

local HATCH_TIME = 8 * 60 * 60 -- 8 hours in seconds
local MAX_EGGS = 1 -- players start with 1 egg slot
local REQUEST_EXPIRY = 30 -- pending requests expire after 30 seconds

-- Pending breed requests: requestId → { player, creatureModel, creatureData, timestamp }
local _breedRequests: { [string]: { player: Player, creatureName: string, creatureStyle: string, timestamp: number } } = {}
local _nextRequestId = 0

local function generateRequestId(): string
	_nextRequestId += 1
	return "breed_" .. tostring(_nextRequestId)
end

local function cleanExpiredRequests()
	local now = os.clock()
	for id, req in pairs(_breedRequests) do
		if now - req.timestamp > REQUEST_EXPIRY then
			_breedRequests[id] = nil
		end
	end
end

--- Request to breed a creature. Looks for a nearby pending request from another player.
function BreedingService.Client:RequestBreed(player: Player, creatureName: string, creatureStyle: string?)
	-- Check egg capacity
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	if #(data.PendingEggs or {}) >= MAX_EGGS then
		return { success = false, error = "No egg slots available (max " .. MAX_EGGS .. ")" }
	end

	-- Check cost
	local cost = OrigamiConfig.BREEDING_COST or 2
	if (data.Cranes or 0) < cost then
		return { success = false, error = "Need " .. cost .. " Cranes to breed" }
	end

	cleanExpiredRequests()

	-- Look for a pending request from a different player
	local matchId: string? = nil
	local matchReq = nil
	for id, req in pairs(_breedRequests) do
		if req.player ~= player and req.player.Parent then -- different player, still connected
			matchId = id
			matchReq = req
			break
		end
	end

	if matchReq and matchId then
		-- Match found — remove from pending and start breed
		_breedRequests[matchId] = nil

		-- Deduct cost from both players
		local otherData = PlayerDataService:Read(matchReq.player)
		if not otherData or (otherData.Cranes or 0) < cost then
			return { success = false, error = "Other player can't afford breeding" }
		end

		-- Check other player also has egg slot
		if #(otherData.PendingEggs or {}) >= MAX_EGGS then
			return { success = false, error = "Other player has no egg slots" }
		end

		local playerCranes = PlayerDataService:Read(player, { "Cranes" }) or 0
		PlayerDataService:Write(player, { "Cranes" }, playerCranes - cost)
		local otherCranes = PlayerDataService:Read(matchReq.player, { "Cranes" }) or 0
		PlayerDataService:Write(matchReq.player, { "Cranes" }, otherCranes - cost)

		-- Generate offspring via LLM
		local parent1Name = creatureName or "Creature"
		local parent2Name = matchReq.creatureName or "Creature"
		local style = creatureStyle or matchReq.creatureStyle or "origami"

		local breedPrompt = string.format(
			"Create a baby creature offspring that blends traits of two parents: '%s' and '%s'. "
			.. "Combine their body shapes, colors, and features into a cute smaller offspring. Category: creature.",
			parent1Name, parent2Name
		)

		-- Call LLM (server-side call to Client method with player)
		local OrigamiService = Knit.GetService("OrigamiService")
		local result = OrigamiService.Client:RequestModel(player, breedPrompt, "creature", style)

		local offspringData = nil
		if result and result.success and result.model then
			offspringData = result.model
		end

		-- Create egg for both players (average colors from parent names as fallback)
		local hatchTime = os.time() + HATCH_TIME
		local egg = {
			parent1Name = parent1Name,
			parent2Name = parent2Name,
			hatchTime = hatchTime,
			offspringData = offspringData, -- nil if LLM failed; will retry on hatch
			breedPrompt = breedPrompt,
			style = style,
		}

		-- Both players get an egg
		local playerEggs = data.PendingEggs or {}
		table.insert(playerEggs, egg)
		PlayerDataService:Write(player, { "PendingEggs" }, playerEggs)

		local egg2 = {
			parent1Name = parent1Name,
			parent2Name = parent2Name,
			hatchTime = hatchTime,
			offspringData = offspringData,
			breedPrompt = breedPrompt,
			style = style,
		}
		local otherEggs = otherData.PendingEggs or {}
		table.insert(otherEggs, egg2)
		PlayerDataService:Write(matchReq.player, { "PendingEggs" }, otherEggs)

		return {
			success = true,
			matched = true,
			partnerName = matchReq.player.DisplayName,
			parent1 = parent1Name,
			parent2 = parent2Name,
			hatchTime = hatchTime,
		}
	else
		-- No match — store as pending
		local requestId = generateRequestId()
		_breedRequests[requestId] = {
			player = player,
			creatureName = creatureName or "Creature",
			creatureStyle = creatureStyle or "origami",
			timestamp = os.clock(),
		}

		return {
			success = true,
			matched = false,
			requestId = requestId,
			message = "Waiting for another player to breed nearby...",
		}
	end
end

--- Cancel a pending breed request.
function BreedingService.Client:CancelBreed(player: Player)
	for id, req in pairs(_breedRequests) do
		if req.player == player then
			_breedRequests[id] = nil
			return { success = true }
		end
	end
	return { success = false, error = "No pending request" }
end

--- Check eggs and their readiness.
function BreedingService.Client:CheckEggs(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end

	local now = os.time()
	local eggs = {}
	for i, egg in ipairs(data.PendingEggs or {}) do
		table.insert(eggs, {
			index = i,
			parent1Name = egg.parent1Name,
			parent2Name = egg.parent2Name,
			hatchTime = egg.hatchTime,
			ready = now >= egg.hatchTime,
			remainingSeconds = math.max(0, egg.hatchTime - now),
		})
	end
	return eggs
end

--- Hatch an egg that's ready.
function BreedingService.Client:HatchEgg(player: Player, eggIndex: number)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local eggs = data.PendingEggs or {}
	if eggIndex < 1 or eggIndex > #eggs then
		return { success = false, error = "Invalid egg index" }
	end

	local egg = eggs[eggIndex]
	if os.time() < egg.hatchTime then
		local remaining = egg.hatchTime - os.time()
		local hours = math.floor(remaining / 3600)
		local mins = math.floor((remaining % 3600) / 60)
		return { success = false, error = string.format("Not ready yet: %dh %dm remaining", hours, mins) }
	end

	-- If offspring data wasn't generated earlier (LLM failure), try again now
	if not egg.offspringData and egg.breedPrompt then
		local OrigamiService = Knit.GetService("OrigamiService")
		local result = OrigamiService.Client:RequestModel(player, egg.breedPrompt, "creature", egg.style or "origami")
		if result and result.success and result.model then
			egg.offspringData = result.model
		end
	end

	if not egg.offspringData then
		return { success = false, error = "Offspring generation failed. Try again." }
	end

	-- Move to hatched creatures
	local offspring = egg.offspringData
	local hatched = data.HatchedCreatures or {}
	table.insert(hatched, offspring)
	PlayerDataService:Write(player, { "HatchedCreatures" }, hatched)

	local pendingEggs = data.PendingEggs or {}
	table.remove(pendingEggs, eggIndex)
	PlayerDataService:Write(player, { "PendingEggs" }, pendingEggs)

	return {
		success = true,
		offspringData = offspring,
		name = offspring.name or ("Baby " .. egg.parent1Name),
	}
end

function BreedingService:KnitInit() end
function BreedingService:KnitStart() end

return BreedingService
