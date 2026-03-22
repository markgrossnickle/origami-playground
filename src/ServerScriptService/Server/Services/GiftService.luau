--[[
	GiftService — server-side model gifting between players.
	Players can gift their spawned creations to nearby players (1 gift per 10 minutes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local GiftService = Knit.CreateService({
	Name = "GiftService",
	Client = {
		GiftReceived = Knit.CreateSignal(), -- (senderName, modelName)
		GiftSent = Knit.CreateSignal(), -- (receiverName, modelName)
	},
})

-- Rate limit: 1 gift per 10 minutes
local GIFT_COOLDOWN = 600
local _lastGiftTime: { [number]: number } = {}

-- Ownership registry: model instance → owner UserId
local _ownership: { [Instance]: number } = {}

--- Register a model as owned by a player.
function GiftService.Client:RegisterModel(player: Player, model: Instance)
	if not model or not model.Parent then
		return { success = false, error = "Invalid model" }
	end
	_ownership[model] = player.UserId
	model:SetAttribute("OwnerUserId", player.UserId)

	-- Clean up when model is destroyed
	model.Destroying:Once(function()
		_ownership[model] = nil
	end)

	return { success = true }
end

--- Get nearby players within 50 studs.
function GiftService.Client:GetNearbyPlayers(player: Player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return {}
	end

	local nearby = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local otherChar = other.Character
			local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local dist = (rootPart.Position - otherRoot.Position).Magnitude
				if dist <= 50 then
					table.insert(nearby, {
						name = other.DisplayName,
						userId = other.UserId,
					})
				end
			end
		end
	end
	return nearby
end

--- Gift a model to another player. Validates ownership and cooldown.
function GiftService.Client:GiftModel(player: Player, model: Instance, targetUserId: number)
	-- Validate model exists
	if not model or not model.Parent then
		return { success = false, error = "Model no longer exists" }
	end

	-- Validate ownership
	local ownerUserId = _ownership[model]
	if ownerUserId ~= player.UserId then
		return { success = false, error = "You don't own this model" }
	end

	-- Rate limit
	local now = os.clock()
	local lastTime = _lastGiftTime[player.UserId] or 0
	if now - lastTime < GIFT_COOLDOWN then
		local remaining = math.ceil(GIFT_COOLDOWN - (now - lastTime))
		local mins = math.floor(remaining / 60)
		local secs = remaining % 60
		return { success = false, error = string.format("Gift cooldown: %dm %ds", mins, secs) }
	end

	-- Validate target player exists and is nearby
	local targetPlayer = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == targetUserId then
			targetPlayer = p
			break
		end
	end
	if not targetPlayer then
		return { success = false, error = "Player not found" }
	end

	-- Proximity check
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local targetChar = targetPlayer.Character
	local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	if rootPart and targetRoot then
		if (rootPart.Position - targetRoot.Position).Magnitude > 60 then
			return { success = false, error = "Player too far away" }
		end
	end

	-- Transfer ownership
	_ownership[model] = targetUserId
	model:SetAttribute("OwnerUserId", targetUserId)
	_lastGiftTime[player.UserId] = now

	-- Update PlayerData
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local giftsGiven = PlayerDataService:Read(player, { "GiftsGiven" }) or 0
	PlayerDataService:Write(player, { "GiftsGiven" }, giftsGiven + 1)
	local giftsReceived = PlayerDataService:Read(targetPlayer, { "GiftsReceived" }) or 0
	PlayerDataService:Write(targetPlayer, { "GiftsReceived" }, giftsReceived + 1)

	-- Reward Paper Token for gifting
	local paper = PlayerDataService:Read(player, { "Paper" }) or 0
	PlayerDataService:Write(player, { "Paper" }, paper + 1)

	-- Get model name for notifications
	local modelName = "Creation"
	if model:IsA("Model") then
		modelName = model.Name
	end
	local billboard = model:FindFirstChild("NameLabel")
	if billboard and billboard:FindFirstChildOfClass("TextLabel") then
		modelName = billboard:FindFirstChildOfClass("TextLabel").Text
	end

	-- Fire signals
	self.GiftReceived:Fire(targetPlayer, player.DisplayName, modelName)
	self.GiftSent:Fire(player, targetPlayer.DisplayName, modelName)

	return { success = true, modelName = modelName }
end

--- Check remaining cooldown for a player.
function GiftService.Client:GetCooldownRemaining(player: Player): number
	local now = os.clock()
	local lastTime = _lastGiftTime[player.UserId] or 0
	return math.max(0, GIFT_COOLDOWN - (now - lastTime))
end

function GiftService:KnitInit() end
function GiftService:KnitStart() end

return GiftService
