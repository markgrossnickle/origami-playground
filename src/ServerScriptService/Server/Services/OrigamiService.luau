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
	if not humanoid then
		return { success = false, error = "no_humanoid" }
	end

	-- Save original appearance if not already saved
	if not _originalAvatars[player.UserId] then
		local saved = {}
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				saved[part.Name] = {
					Color = part.Color,
					Material = part.Material,
					Size = part.Size,
					Transparency = part.Transparency,
				}
			end
		end
		-- Save accessories
		saved._accessories = {}
		for _, acc in ipairs(character:GetChildren()) do
			if acc:IsA("Accessory") and not acc:GetAttribute("OrigamiHat") then
				table.insert(saved._accessories, acc)
				acc.Parent = nil -- Hide, don't destroy
			end
		end
		-- Save shirt/pants/body colors
		saved._shirt = character:FindFirstChildOfClass("Shirt")
		saved._pants = character:FindFirstChildOfClass("Pants")
		saved._bodyColors = character:FindFirstChildOfClass("BodyColors")
		_originalAvatars[player.UserId] = saved
	end

	-- Hide shirt/pants
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then shirt.ShirtTemplate = "" end
	local pants = character:FindFirstChildOfClass("Pants")
	if pants then pants.PantsTemplate = "" end

	-- Remove non-origami accessories
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and not child:GetAttribute("OrigamiHat") then
			child.Parent = nil
		end
	end

	-- Build origami model to get part data
	local parts = modelData.parts or {}

	-- Map origami parts to character body parts by name matching
	local bodyPartMap = {
		head = "Head",
		torso = "Torso", body = "Torso", chest = "Torso",
		["left arm"] = "Left Arm", ["left_arm"] = "Left Arm", leftarm = "Left Arm",
		["right arm"] = "Right Arm", ["right_arm"] = "Right Arm", rightarm = "Right Arm",
		["left leg"] = "Left Leg", ["left_leg"] = "Left Leg", leftleg = "Left Leg",
		["right leg"] = "Right Leg", ["right_leg"] = "Right Leg", rightleg = "Right Leg",
	}

	-- Apply colors/materials from origami parts to matching body parts
	local appliedParts = {}
	for _, partData in ipairs(parts) do
		local partName = (partData.name or ""):lower()
		local bodyPartName = bodyPartMap[partName]

		if bodyPartName then
			local bodyPart = character:FindFirstChild(bodyPartName)
			if bodyPart and bodyPart:IsA("BasePart") then
				if partData.color then
					local r = partData.color[1] or partData.color.r or 255
					local g = partData.color[2] or partData.color.g or 255
					local b = partData.color[3] or partData.color.b or 255
					bodyPart.Color = Color3.fromRGB(r, g, b)
				end
				if partData.material then
					local mat = Enum.Material.SmoothPlastic
					pcall(function() mat = Enum.Material[partData.material] end)
					bodyPart.Material = mat
				end
				appliedParts[bodyPartName] = true
			end
		end
	end

	-- For any body part without a match, use the first part's color as default
	if parts[1] and parts[1].color then
		local defaultColor = Color3.fromRGB(
			parts[1].color[1] or 255,
			parts[1].color[2] or 255,
			parts[1].color[3] or 255
		)
		for _, bodyPartName in pairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
			if not appliedParts[bodyPartName] then
				local bodyPart = character:FindFirstChild(bodyPartName)
				if bodyPart and bodyPart:IsA("BasePart") then
					bodyPart.Color = defaultColor
					bodyPart.Material = Enum.Material.SmoothPlastic
				end
			end
		end
	end

	-- Add origami decoration parts (accessories, details) that don't map to body parts
	-- Tag them for cleanup
	for _, partData in ipairs(parts) do
		local partName = (partData.name or ""):lower()
		if not bodyPartMap[partName] then
			-- This is a decoration part (hat detail, cape, wings, etc)
			-- Attach to nearest body part
			local attachTo = character:FindFirstChild("Torso") or character:FindFirstChild("Head")
			if attachTo and attachTo:IsA("BasePart") then
				local decor = Instance.new("Part")
				decor.Name = "OrigamiDecor_" .. (partData.name or "detail")
				decor:SetAttribute("OrigamiDecor", true)
				decor.Anchored = false
				decor.CanCollide = false

				if partData.size then
					decor.Size = Vector3.new(
						partData.size[1] or partData.size.x or 1,
						partData.size[2] or partData.size.y or 1,
						partData.size[3] or partData.size.z or 1
					)
				else
					decor.Size = Vector3.new(1, 1, 1)
				end

				if partData.color then
					decor.Color = Color3.fromRGB(
						partData.color[1] or 255,
						partData.color[2] or 255,
						partData.color[3] or 255
					)
				end

				if partData.material then
					pcall(function() decor.Material = Enum.Material[partData.material] end)
				end

				-- Position relative to attach point
				local offset = Vector3.new(0, 0, 0)
				if partData.position then
					offset = Vector3.new(
						partData.position[1] or 0,
						partData.position[2] or 0,
						partData.position[3] or 0
					)
					-- Scale down since these are relative to model center, not body
					offset = offset * 0.3
				end

				decor.Parent = character
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = attachTo
				weld.Part1 = decor
				weld.Parent = decor
				decor.CFrame = attachTo.CFrame * CFrame.new(offset)
			end
		end
	end

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

	-- Restore body part colors/materials/sizes
	for partName, data in pairs(saved) do
		if partName ~= "_accessories" and partName ~= "_shirt" and partName ~= "_pants" and partName ~= "_bodyColors" then
			local bodyPart = character:FindFirstChild(partName)
			if bodyPart and bodyPart:IsA("BasePart") then
				bodyPart.Color = data.Color
				bodyPart.Material = data.Material
				bodyPart.Transparency = data.Transparency
			end
		end
	end

	-- Restore accessories
	if saved._accessories then
		for _, acc in ipairs(saved._accessories) do
			if acc then
				acc.Parent = character
			end
		end
	end

	-- Restore shirt/pants
	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt and saved._shirt then
		shirt.ShirtTemplate = saved._shirt.ShirtTemplate
	end
	local pants = character:FindFirstChildOfClass("Pants")
	if pants and saved._pants then
		pants.PantsTemplate = saved._pants.PantsTemplate
	end

	-- Remove origami decoration parts
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrigamiDecor") then
			child:Destroy()
		end
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
