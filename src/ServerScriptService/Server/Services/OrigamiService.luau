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

-- Server-side vehicle seats per player (needed because Sit() requires server authority)
local _vehicleSeats: { [number]: { any } } = {}

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

function OrigamiService.Client:RequestModel(player: Player, prompt: string, category: string, style: string?, model: string?)
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
	local isRaw = category == "raw"
	local requestBody = {
		prompt = prompt,
		player_id = tostring(player.UserId),
		category = if isRaw then nil else category,
		style = style or "origami",
		model = model or "haiku",
		raw = if isRaw then true else nil,
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
		return { success = false, error = "request_failed: " .. tostring(response) }
	end

	if not response.Success then
		warn("[OrigamiService] API returned error:", response.StatusCode, response.Body)
		-- Try to extract detail from response body
		local detail = ""
		local decodeOk, errBody = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if decodeOk and errBody then
			if errBody.detail then
				if type(errBody.detail) == "string" then
					detail = errBody.detail
				elseif type(errBody.detail) == "table" and errBody.detail[1] then
					detail = errBody.detail[1].msg or ""
				end
			elseif errBody.error then
				detail = errBody.error
			end
		end
		return { success = false, error = "api_error(" .. response.StatusCode .. "): " .. detail }
	end

	-- Parse response
	local parseOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not parseOk or not data then
		warn("[OrigamiService] Failed to parse response:", response.Body)
		return { success = false, error = "parse_error: " .. tostring(data) }
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

	-- R15 body part name fallbacks for R6 characters
	local R15_TO_R6 = {
		UpperTorso = "Torso",
		LowerTorso = "Torso",
		LeftUpperArm = "Left Arm",
		LeftLowerArm = "Left Arm",
		LeftHand = "Left Arm",
		RightUpperArm = "Right Arm",
		RightLowerArm = "Right Arm",
		RightHand = "Right Arm",
		LeftUpperLeg = "Left Leg",
		LeftLowerLeg = "Left Leg",
		LeftFoot = "Left Leg",
		RightUpperLeg = "Right Leg",
		RightLowerLeg = "Right Leg",
		RightFoot = "Right Leg",
	}

	-- Resolve a body part name to an actual part in the character
	local function findBodyPart(bodyPartName: string): BasePart?
		-- Try exact match first (R15)
		local found = character:FindFirstChild(bodyPartName)
		if found and found:IsA("BasePart") then
			return found
		end
		-- Try R6 fallback
		local r6Name = R15_TO_R6[bodyPartName]
		if r6Name then
			found = character:FindFirstChild(r6Name)
			if found and found:IsA("BasePart") then
				return found
			end
		end
		return nil
	end

	-- Check if model data has body_part fields (rigged avatar)
	local partsData = modelData.parts or {}
	local hasBodyParts = false
	for _, pd in ipairs(partsData) do
		if pd.body_part then
			hasBodyParts = true
			break
		end
	end

	-- Undo OrigamiBuilder's 180° Y flip — avatar uses body-part-local coordinates, not world space
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CFrame = CFrame.Angles(0, math.pi, 0) * child.CFrame
		end
	end

	-- Weld origami parts to character
	local builtParts = model:GetDescendants()
	local partsByName = {}
	for _, part in ipairs(builtParts) do
		if part:IsA("BasePart") then
			partsByName[part.Name] = part
		end
	end

	if hasBodyParts then
		-- RIGGED MODE: weld each part to its mapped body part
		for _, pd in ipairs(partsData) do
			local partName = pd.name
			local bodyPartName = pd.body_part
			local part = partsByName[partName]
			if not part or not bodyPartName then
				continue
			end

			local targetPart = findBodyPart(bodyPartName)
			if not targetPart then
				-- Fallback to HumanoidRootPart
				targetPart = rootPart
			end

			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part:SetAttribute("OrigamiAvatar", true)

			-- Position part relative to the target body part
			-- The LLM positions parts relative to [0,0,0] of each body part
			local offset = CFrame.new(part.Position)
			local partRot = part.CFrame - part.CFrame.Position
			part.CFrame = targetPart.CFrame * offset * partRot
			part.Parent = character

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = targetPart
			weld.Part1 = part
			weld.Parent = part
		end
	else
		-- LEGACY MODE: weld everything to HumanoidRootPart with 180° flip
		local modelCenter = model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero
		local flip = CFrame.Angles(0, math.rad(180), 0)

		for _, part in ipairs(builtParts) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.Massless = true
				part:SetAttribute("OrigamiAvatar", true)

				local localCF = CFrame.new(-modelCenter) * part.CFrame
				part.CFrame = rootPart.CFrame * flip * localCF
				part.Parent = character

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = part
				weld.Parent = part
			end
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

function OrigamiService.Client:CreateVehicleSeat(player: Player, position: Vector3, lookY: number, modelName: string, modelSizeData: { X: number, Y: number, Z: number })
	print("[OrigamiService] CreateVehicleSeat called by", player.Name, "at", position)

	-- Create VehicleSeat on server so Sit() works
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.CFrame = CFrame.new(position) * CFrame.Angles(0, lookY, 0)
	seat.Anchored = true -- stays anchored until client welds visual parts and calls ReadyVehicle
	seat.CanCollide = true
	seat.Transparency = 1
	seat.MaxSpeed = 50
	seat.Torque = 40
	seat.TurnSpeed = 8
	seat.Material = Enum.Material.SmoothPlastic
	seat:SetAttribute("OrigamiVehicle", true)
	seat:SetAttribute("OwnerUserId", player.UserId)
	seat.Parent = workspace

	-- Collision plate at ground level for traction/ground contact
	local modelSize = Vector3.new(modelSizeData.X or 4, modelSizeData.Y or 2, modelSizeData.Z or 4)
	local collisionPlate = Instance.new("Part")
	collisionPlate.Name = "CollisionPlate"
	collisionPlate.Size = Vector3.new(math.min(modelSize.X * 0.8, 14), 0.5, math.min(modelSize.Z * 0.8, 16))
	collisionPlate.Transparency = 1
	collisionPlate.CanCollide = true
	collisionPlate.Massless = false -- needs mass for ground friction/traction
	collisionPlate.Anchored = false
	collisionPlate.Material = Enum.Material.SmoothPlastic
	-- Seat is ~1 stud above ground; plate sits at ground level just below the seat
	collisionPlate.CFrame = seat.CFrame * CFrame.new(0, -1, 0)
	collisionPlate.Parent = workspace

	local plateWeld = Instance.new("WeldConstraint")
	plateWeld.Part0 = seat
	plateWeld.Part1 = collisionPlate
	plateWeld.Parent = collisionPlate

	-- ProximityPrompt with line-of-sight disabled (visual parts surround the seat)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = modelName or "Vehicle"
	prompt.ActionText = "Drive"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	prompt.Triggered:Connect(function(triggerPlayer: Player)
		print("[OrigamiService] ProximityPrompt triggered by", triggerPlayer.Name)
		local character = triggerPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			print("[OrigamiService] Sitting", triggerPlayer.Name, "in seat")
			-- Transfer network ownership so the client can control vehicle physics
			seat:SetNetworkOwner(triggerPlayer)
			seat:Sit(humanoid)
			print("[OrigamiService] Occupant after Sit:", seat.Occupant)
		else
			warn("[OrigamiService] No humanoid for", triggerPlayer.Name)
		end
	end)

	-- Track for cleanup
	if not _vehicleSeats[player.UserId] then
		_vehicleSeats[player.UserId] = {}
	end
	table.insert(_vehicleSeats[player.UserId], { seat = seat, plate = collisionPlate })

	print("[OrigamiService] Vehicle seat created, seat:", seat, "plate:", collisionPlate)
	return seat
end

function OrigamiService.Client:DestroyVehicleSeats(player: Player)
	local seats = _vehicleSeats[player.UserId]
	if seats then
		for _, entry in ipairs(seats) do
			if entry.seat and entry.seat.Parent then
				entry.seat:Destroy()
			end
			if entry.plate and entry.plate.Parent then
				entry.plate:Destroy()
			end
		end
		_vehicleSeats[player.UserId] = nil
		print("[OrigamiService] Destroyed all vehicle seats for", player.Name)
	end
end

function OrigamiService.Client:ReadyVehicle(player: Player, seat: VehicleSeat)
	if seat and seat.Parent and seat:GetAttribute("OwnerUserId") == player.UserId then
		print("[OrigamiService] Unanchoring vehicle seat for", player.Name)
		seat.Anchored = false
		-- Give the owner network ownership so physics are client-controlled
		seat:SetNetworkOwner(player)
	end
end

function OrigamiService.Client:FetchCatalog(player: Player, search: string?)
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		return { success = false, error = "api_not_configured" }
	end

	local apiKey = getApiKey()
	local url = apiUrl .. "/api/catalog"
	if search and search ~= "" then
		url = url .. "?search=" .. HttpService:UrlEncode(search)
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = {
				["X-Api-Key"] = apiKey,
			},
		})
	end)

	if not ok then
		warn("[OrigamiService] Catalog fetch failed:", response)
		return { success = false, error = "request_failed" }
	end

	if not response.Success then
		return { success = false, error = "api_error(" .. response.StatusCode .. ")" }
	end

	local parseOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not parseOk or not data then
		return { success = false, error = "parse_error" }
	end

	return { success = true, items = data.items or {} }
end

function OrigamiService.Client:FetchCatalogItem(player: Player, itemId: string)
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		return { success = false, error = "api_not_configured" }
	end

	local apiKey = getApiKey()

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = apiUrl .. "/api/catalog/" .. itemId,
			Method = "GET",
			Headers = {
				["X-Api-Key"] = apiKey,
			},
		})
	end)

	if not ok then
		return { success = false, error = "request_failed" }
	end

	if not response.Success then
		return { success = false, error = "api_error(" .. response.StatusCode .. ")" }
	end

	local parseOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not parseOk or not data then
		return { success = false, error = "parse_error" }
	end

	return { success = true, item = data }
end

function OrigamiService:KnitInit()
	-- Clean up rate limits, avatar state, and vehicle seats when players leave
	Players.PlayerRemoving:Connect(function(player)
		_rateLimits[tostring(player.UserId)] = nil
		_originalAvatars[player.UserId] = nil
		-- Clean up server vehicle seats
		local seats = _vehicleSeats[player.UserId]
		if seats then
			for _, entry in ipairs(seats) do
				if entry.seat and entry.seat.Parent then
					entry.seat:Destroy()
				end
				if entry.plate and entry.plate.Parent then
					entry.plate:Destroy()
				end
			end
			_vehicleSeats[player.UserId] = nil
		end
	end)
end

function OrigamiService:KnitStart()
	print("[OrigamiService] Started")
end

return OrigamiService
