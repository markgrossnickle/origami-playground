local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)
local ServerConfig = require(ReplicatedStorage.Assets.Configuration.Server)

local OrigamiService = Knit.CreateService({
	Name = "OrigamiService",

	-- Server signals
	ModelCreated = Signal.new(),

	-- Client-exposed API
	Client = {
		ModelGenerated = Knit.CreateSignal(),
	},
})

-- Rate limit tracking: playerId -> last request timestamp
local _rateLimits: { [string]: number } = {}

local function getApiUrl(): string
	return ServerConfig.API_URL or OrigamiConfig.API_URL
end

local function getApiKey(): string
	return ServerConfig.API_KEY or OrigamiConfig.API_KEY
end

local function checkRateLimit(player: Player): (boolean, number)
	local playerId = tostring(player.UserId)
	local now = tick()
	local lastRequest = _rateLimits[playerId]

	if lastRequest then
		local elapsed = now - lastRequest
		if elapsed < OrigamiConfig.COOLDOWN_SECONDS then
			local remaining = OrigamiConfig.COOLDOWN_SECONDS - elapsed
			return false, remaining
		end
	end

	_rateLimits[playerId] = now
	return true, 0
end

function OrigamiService.Client:RequestModel(player: Player, prompt: string, category: string)
	-- Rate limit check
	local allowed, cooldownRemaining = checkRateLimit(player)
	if not allowed then
		return {
			success = false,
			error = "cooldown",
			cooldown = math.ceil(cooldownRemaining),
		}
	end

	-- Validate input
	if not prompt or prompt == "" then
		return { success = false, error = "empty_prompt" }
	end

	if #prompt > 100 then
		return { success = false, error = "prompt_too_long" }
	end

	-- Build request
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		warn("[OrigamiService] API_URL not configured. Set it as an Attribute or in OrigamiConfig.")
		return { success = false, error = "api_not_configured" }
	end

	local apiKey = getApiKey()
	local requestBody = {
		prompt = prompt,
		player_id = tostring(player.UserId),
		category = category or nil,
		raw = (category == "raw") or nil,
	}

	-- Call external API
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = apiUrl .. "/api/generate",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["X-Api-Key"] = apiKey,
			},
			Body = HttpService:JSONEncode(requestBody),
		})
	end)

	if not ok then
		warn("[OrigamiService] HTTP request failed:", response)
		return { success = false, error = "request_failed" }
	end

	if not response.Success then
		warn("[OrigamiService] API returned error:", response.StatusCode, response.Body)
		return { success = false, error = "api_error" }
	end

	-- Parse response
	local parseOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not parseOk or not data then
		warn("[OrigamiService] Failed to parse response:", response.Body)
		return { success = false, error = "parse_error" }
	end

	if not data.success then
		return { success = false, error = data.error or "generation_failed" }
	end

	-- Fire signals
	local modelData = data.model
	self.Server.ModelCreated:Fire(player, modelData)
	self.Server.Client.ModelGenerated:Fire(player, modelData)

	return { success = true, model = modelData }
end

function OrigamiService:KnitInit()
	-- Clean up rate limits when players leave
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		_rateLimits[tostring(player.UserId)] = nil
	end)
end

function OrigamiService:KnitStart()
	print("[OrigamiService] Started")
end

return OrigamiService
