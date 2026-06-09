--!strict
--[=[
	@class ModelLinkConfig
	Configuration for "bring-your-own-model" (BYOM) + subscription sign-on.

	Players link their own AI provider key on the origami-server website, then
	the game can call their model through the server's proxy. Access to that
	feature is gated behind a Roblox Subscription.

	OWNER SETUP (see also the PR description):
	  1. Create a Subscription in the Roblox Creator Dashboard
	     (Monetization > Subscriptions) and paste its id below as SubscriptionId.
	  2. Flip GateEnabled to true once the Subscription exists. While it is
	     false the gate is bypassed so the feature is usable for testing before
	     the Subscription is live.
	  3. The linking website is served by origami-server itself — LinkPath is
	     appended to the server's public URL (from Server.luau API_URL).
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
}

return ModelLinkConfig
