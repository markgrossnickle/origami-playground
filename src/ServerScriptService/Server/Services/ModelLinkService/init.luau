--!strict
--[=[
	@class ModelLinkService

	Bring-your-own-model (BYOM) link flow + moderated model calls.

	The player's AI provider key NEVER touches Roblox. This service only:
	  - asks origami-server to mint a one-time LINK CODE for the player's userId
	    (the player then enters it on the origami-server website to attach their
	    own provider — "Sign in with ChatGPT" for OpenAI, or a pasted Claude
	    API key — stored encrypted server-side);
	  - reports the player's link status (which provider, if any);
	  - calls origami-server's MODEL PROXY on the player's behalf and runs the
	    returned text through Roblox text filtering before it is shown to anyone.

	All origami-server calls are authenticated with the shared secret in
	ServerStorage Server.luau (the same X-Api-Key the rest of the game uses) and
	run server-side only (HttpService is server-only). The secret lives in
	ServerStorage so it is never replicated to clients.
]=]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Server-only: API url + key live in ServerStorage, never replicated to clients.
local ServerConfig = require(ServerStorage.Configuration.Server)
local ModelLinkConfig = require(ReplicatedStorage.Shared.ModelLinkConfig)

local ModelLinkService = Knit.CreateService({
	Name = "ModelLinkService",
	Client = {},
})

local MonetizationService

-- Per-player cooldown for proxy calls (defense in depth; the server also rate
-- limits per userId).
local PROXY_COOLDOWN_SECONDS = 2
local _lastProxyCall: { [number]: number } = {}

local function getApiUrl(): string
	return ServerConfig.API_URL or ""
end

local function getApiKey(): string
	return ServerConfig.API_KEY or ""
end

-- Server-to-server POST helper. Returns (ok, decodedBody | errorString).
local function postJson(path: string, body: { [string]: any }): (boolean, any)
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		return false, "api_not_configured"
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = apiUrl .. path,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["X-Api-Key"] = getApiKey(),
			},
			Body = HttpService:JSONEncode(body),
		})
	end)

	if not ok then
		warn("[ModelLinkService] HTTP request failed:", response)
		return false, "request_failed"
	end

	if not response.Success then
		warn("[ModelLinkService] API error:", response.StatusCode)
		return false, "api_error(" .. tostring(response.StatusCode) .. ")"
	end

	local decodeOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk or not data then
		return false, "parse_error"
	end

	return true, data
end

--- Filter model text for broadcast to all players (mandatory per Roblox ToS).
-- Returns the filtered string, or a safe fallback if filtering fails.
local function filterForBroadcast(text: string, fromUserId: number): string
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, fromUserId)
	end)
	if not ok or not result then
		warn("[ModelLinkService] FilterStringAsync failed:", result)
		return "(message hidden)"
	end

	local broadcastOk, filtered = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not broadcastOk or not filtered then
		warn("[ModelLinkService] GetNonChatStringForBroadcastAsync failed:", filtered)
		return "(message hidden)"
	end
	return filtered
end

--- Mint a one-time link code for the player and return it plus the website URL.
function ModelLinkService.Client:GetLinkCode(player: Player)
	local ok, data = postJson("/api/link/start", { user_id = tostring(player.UserId) })
	if not ok then
		return { success = false, error = data }
	end
	if not data.success then
		return { success = false, error = data.error or "link_failed" }
	end

	local websiteUrl = (data.link_url ~= nil and data.link_url ~= "") and data.link_url
		or (getApiUrl() .. ModelLinkConfig.LinkPath)

	return {
		success = true,
		code = data.code,
		url = websiteUrl,
		expiresIn = data.expires_in,
	}
end

--- Whether the player has a linked model and which provider (no secrets are
-- ever returned by the server).
function ModelLinkService.Client:IsLinked(player: Player)
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		return { success = false, error = "api_not_configured" }
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = apiUrl .. "/api/link/status?user_id=" .. HttpService:UrlEncode(tostring(player.UserId)),
			Method = "GET",
			Headers = { ["X-Api-Key"] = getApiKey() },
		})
	end)
	if not ok or not response.Success then
		return { success = false, error = "request_failed" }
	end

	local decodeOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk or not data then
		return { success = false, error = "parse_error" }
	end

	return {
		success = true,
		linked = data.linked == true,
		provider = data.provider,
		model = data.model_name,
	}
end

--- Demo feature: ask the player's linked model a prompt and return the
-- text-filtered response. Optionally gated behind the model subscription.
function ModelLinkService.Client:AskModel(player: Player, prompt: string)
	-- Subscription gate (bypassed while ModelLinkConfig.GateEnabled is false).
	if not MonetizationService:HasModelSubscription(player) then
		return { success = false, error = "subscription_required" }
	end

	-- Validate input.
	if type(prompt) ~= "string" or prompt == "" then
		return { success = false, error = "empty_prompt" }
	end
	if #prompt > ModelLinkConfig.MaxPromptLength then
		return { success = false, error = "prompt_too_long" }
	end

	-- Per-player cooldown.
	local now = tick()
	local last = _lastProxyCall[player.UserId]
	if last and (now - last) < PROXY_COOLDOWN_SECONDS then
		return { success = false, error = "cooldown" }
	end
	_lastProxyCall[player.UserId] = now

	local ok, data = postJson("/api/model/proxy", {
		user_id = tostring(player.UserId),
		prompt = prompt,
		system = ModelLinkConfig.DemoSystemPrompt,
	})
	if not ok then
		return { success = false, error = data }
	end
	if not data.success then
		-- The server returns a machine-readable code in `error_reason`
		-- (e.g. "not_linked", "rate_limited") and a human message in `error`.
		return {
			success = false,
			error = data.error_reason or "proxy_failed",
			message = data.error,
		}
	end

	local rawText = tostring(data.text or "")
	if #rawText > ModelLinkConfig.MaxResponseLength then
		rawText = rawText:sub(1, ModelLinkConfig.MaxResponseLength)
	end

	-- MANDATORY moderation before showing to any player.
	local filtered = filterForBroadcast(rawText, player.UserId)

	return { success = true, text = filtered }
end

function ModelLinkService:KnitInit()
	MonetizationService = Knit.GetService("MonetizationService")

	Players.PlayerRemoving:Connect(function(player)
		_lastProxyCall[player.UserId] = nil
	end)
end

function ModelLinkService:KnitStart()
	print("[ModelLinkService] Started")
end

return ModelLinkService
