local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
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

-- Avatar state: store original character parts to restore later
local _originalAvatars: { [number]: { [string]: any } } = {}

local SHAPE_MAP = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

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

function OrigamiService.Client:ApplyAvatar(player: Player, modelData)
	local character = player.Character
	if not character then
		return { success = false, error = "no_character" }
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return { success = false, error = "no_humanoid" }
	end

	-- Clean up previous origami avatar if one exists
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrigamiAvatar") then
			child:Destroy()
		end
	end

	-- Save original appearance if not already saved
	if not _originalAvatars[player.UserId] then
		local saved = {}
		-- Save transparency of all body parts
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				saved[part.Name] = { Transparency = part.Transparency }
			end
		end
		-- Stash accessories (reparent to nil, don't destroy)
		saved._accessories = {}
		for _, acc in ipairs(character:GetChildren()) do
			if acc:IsA("Accessory") then
				table.insert(saved._accessories, acc)
			end
		end
		-- Save shirt/pants templates
		local shirt = character:FindFirstChildOfClass("Shirt")
		local pants = character:FindFirstChildOfClass("Pants")
		saved._shirtTemplate = shirt and shirt.ShirtTemplate or nil
		saved._pantsTemplate = pants and pants.PantsTemplate or nil
		_originalAvatars[player.UserId] = saved
	end

	-- Hide all existing body parts (make invisible)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Transparency = 1
		end
	end

	-- Hide accessories
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle then
				handle.Transparency = 1
			end
		end
	end

	-- Hide shirt/pants
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then shirt.ShirtTemplate = "" end
	local pants = character:FindFirstChildOfClass("Pants")
	if pants then pants.PantsTemplate = "" end

	-- Build the origami model using OrigamiBuilder
	local model = OrigamiBuilder.BuildModel(modelData)

	-- Weld the entire origami model to HumanoidRootPart
	-- All parts become children of character, welded to rootPart
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part:SetAttribute("OrigamiAvatar", true)

			-- Position relative to rootPart
			local offset = part.CFrame - (model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero)
			part.CFrame = rootPart.CFrame * offset

			part.Parent = character

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	model:Destroy() -- Empty shell, parts moved to character

	return { success = true }
end

function OrigamiService.Client:ResetAvatar(player: Player)
	local character = player.Character
	if not character then
		return { success = false }
	end

	local saved = _originalAvatars[player.UserId]
	if not saved then
		return { success = false, error = "no_saved_avatar" }
	end

	-- Remove all origami avatar parts
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrigamiAvatar") then
			child:Destroy()
		end
	end

	-- Restore body part visibility
	for partName, data in pairs(saved) do
		if type(data) == "table" and data.Transparency then
			local bodyPart = character:FindFirstChild(partName)
			if bodyPart and bodyPart:IsA("BasePart") then
				bodyPart.Transparency = data.Transparency
			end
		end
	end

	-- Restore accessories
	if saved._accessories then
		for _, acc in ipairs(saved._accessories) do
			if acc then
				local handle = acc:FindFirstChild("Handle")
				if handle then
					handle.Transparency = 0
				end
			end
		end
	end

	-- Restore shirt/pants
	if saved._shirtTemplate then
		local shirt = character:FindFirstChildOfClass("Shirt")
		if shirt then shirt.ShirtTemplate = saved._shirtTemplate end
	end
	if saved._pantsTemplate then
		local pants = character:FindFirstChildOfClass("Pants")
		if pants then pants.PantsTemplate = saved._pantsTemplate end
	end

	_originalAvatars[player.UserId] = nil

	return { success = true }
end

function OrigamiService:KnitInit()
	-- Clean up rate limits and avatar state when players leave
	Players.PlayerRemoving:Connect(function(player)
		_rateLimits[tostring(player.UserId)] = nil
		_originalAvatars[player.UserId] = nil
	end)
end

function OrigamiService:KnitStart()
	print("[OrigamiService] Started")
end

return OrigamiService
