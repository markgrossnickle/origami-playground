--!strict
--[=[
	@class ModelLinkConfig
	Configuration for "bring-your-own-model" (BYOM) + subscription sign-on.

	Players link their own AI provider on the origami-server website using a
	one-time code, then the game can call their model through the server's
	proxy. Two providers are supported (the choice is made on the website):
	  - OpenAI — "Sign in with ChatGPT" (subscription OAuth web flow)
	  - Claude — paste an Anthropic API key
	Keys/tokens are stored encrypted server-side and NEVER reach the Roblox
	client. Access to the feature can optionally be gated behind a Roblox
	Subscription.

	OWNER SETUP (see also the PR description):
	  1. (Optional) Create a Subscription in the Roblox Creator Dashboard
	     (Monetization > Subscriptions) and paste its id below as SubscriptionId.
	  2. Flip GateEnabled to true once the Subscription exists. While it is
	     false the gate is bypassed so the feature is usable for testing before
	     the Subscription is live.
	  3. The linking website is served by origami-server itself — LinkPath is
	     appended to the server's public URL (from ServerStorage Server.luau).
]=]

export type ModelLinkConfigType = {
	-- Subscription gate
	GateEnabled: boolean,
	SubscriptionId: string,

	-- Linking website (served by origami-server). The full URL is built at
	-- runtime as `API_URL .. LinkPath`.
	LinkPath: string,

	-- Demo "Ask AI" feature
	DemoSystemPrompt: string,
	MaxPromptLength: number,
	MaxResponseLength: number,

	-- Maps a provider id from /api/link/status into a friendly display label.
	ProviderLabel: (provider: string?) -> string,
}

local ModelLinkConfig: ModelLinkConfigType = {
	-- Gate is OFF by default so the feature works before the owner has created
	-- the Roblox Subscription. Set to true (and fill SubscriptionId) to enforce.
	GateEnabled = false,
	-- Paste the Roblox Subscription id here, e.g. "EXP-1234567890123456".
	SubscriptionId = "",

	LinkPath = "/link",

	DemoSystemPrompt = "You are a friendly origami shopkeeper NPC in a kids' Roblox game. "
		.. "Reply in one or two short, cheerful, G-rated sentences.",
	MaxPromptLength = 200,
	MaxResponseLength = 400,

	-- Friendly label for the provider the player linked. The server returns
	-- "openai" for the Sign-in-with-ChatGPT flow and a Claude/Anthropic id for
	-- the pasted-API-key flow; unknown ids fall back to a capitalized form so
	-- new providers still render sensibly.
	ProviderLabel = function(provider: string?): string
		if provider == nil or provider == "" then
			return "Not linked"
		end
		local key = string.lower(provider)
		if key == "openai" or key == "chatgpt" then
			return "ChatGPT (OpenAI)"
		elseif key == "claude" or key == "anthropic" then
			return "Claude (Anthropic)"
		end
		return provider:sub(1, 1):upper() .. provider:sub(2)
	end,
}

return ModelLinkConfig
