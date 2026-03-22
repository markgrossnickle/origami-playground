--[[
	ShopKeepers — spawns shopkeeper creatures at fixed positions with ProximityPrompts
	and speech bubble BillboardGuis. Called from ShopKeeperService:KnitStart().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local ShopkeeperData = require(ReplicatedStorage.Shared.ShopkeeperData)

local ShopKeepers = {}

local FOLDER_NAME = "Shopkeepers"

-- Theme colors per shop type
local SHOP_COLORS = {
	browse = Color3.fromRGB(200, 170, 80), -- warm gold for pawn shop
	create_lite = Color3.fromRGB(100, 150, 220), -- blue for workshop
	create_pro = Color3.fromRGB(160, 100, 220), -- purple for atelier
}

----------------------------------------------------------------------
-- Billboard helpers
----------------------------------------------------------------------

local function addShopNameSign(parent: Instance, shopName: string, shopType: string)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShopName"
	bb.StudsOffset = Vector3.new(0, 10, 0)
	bb.Size = UDim2.new(0, 220, 0, 40)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = SHOP_COLORS[shopType] or Color3.new(1, 1, 1)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = false
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Text = shopName
	label.TextWrapped = true
	label.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	bb.Adornee = parent
	bb.Parent = parent
	return bb
end

local function addSpeechBubble(parent: Instance, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"
	bb.StudsOffset = Vector3.new(0, 7.5, 0)
	bb.Size = UDim2.new(0, 240, 0, 60)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 40

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 0.1
	frame.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
	frame.BorderSizePixel = 0
	frame.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(180, 160, 120)
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 1, -8)
	label.Position = UDim2.new(0, 6, 0, 4)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(60, 50, 40)
	label.TextScaled = false
	label.TextSize = 11
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = frame

	bb.Adornee = parent
	bb.Parent = parent
	return bb
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

function ShopKeepers.Build(service)
	ShopKeepers.Clear()

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace

	for _, shopInfo in ipairs(ShopkeeperData.SHOPS) do
		local modelData = shopInfo.modelData
		if not modelData or not modelData.parts then
			warn("[ShopKeepers] Missing model data for shop: " .. shopInfo.id)
			continue
		end

		-- Build the creature model
		local buildOk, model = pcall(function()
			return OrigamiBuilder.BuildModel(modelData)
		end)

		if not buildOk or not model then
			warn("[ShopKeepers] Failed to build shopkeeper: " .. shopInfo.id)
			continue
		end

		-- Anchor all parts
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end

		-- Position at world coordinates
		local pos = shopInfo.position
		model:PivotTo(CFrame.new(pos[1], pos[2], pos[3]))
		model.Name = "Shopkeeper_" .. shopInfo.id
		model.Parent = folder

		-- Apply idle animation
		local animType = modelData.animation or "idle_bob"
		if animType ~= "none" then
			pcall(function()
				OrigamiBuilder.ApplyAnimation(model, animType)
			end)
		end

		-- Add billboards to primary part
		local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if target then
			addShopNameSign(target, shopInfo.name, shopInfo.shopType)
			addSpeechBubble(target, shopInfo.speechText)

			-- Add ProximityPrompt
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = shopInfo.shopkeeperName
			prompt.ActionText = shopInfo.promptText
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 15
			prompt.RequiresLineOfSight = false
			prompt.Parent = target

			-- Wire to service signal
			if service then
				prompt.Triggered:Connect(function(triggerPlayer: Player)
					service.Client.ShopOpened:Fire(triggerPlayer, shopInfo.id, shopInfo.shopType, shopInfo.lockedModel)
				end)
			end
		end

		local partCount = #modelData.parts
		print(
			string.format(
				"[ShopKeepers] Spawned %s (%d parts) at (%d, %d, %d)",
				shopInfo.shopkeeperName,
				partCount,
				pos[1],
				pos[2],
				pos[3]
			)
		)
	end

	-- Build display models (if any)
	for _, displayInfo in ipairs(ShopkeeperData.DISPLAY_MODELS) do
		local dModelData = displayInfo.modelData
		if not dModelData or not dModelData.parts then
			continue
		end

		local buildOk, dModel = pcall(function()
			return OrigamiBuilder.BuildModel(dModelData)
		end)

		if buildOk and dModel then
			for _, part in dModel:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end

			local dPos = displayInfo.position
			dModel:PivotTo(CFrame.new(dPos[1], dPos[2], dPos[3]))
			dModel.Parent = folder

			local dAnimType = dModelData.animation or "idle_bob"
			if dAnimType ~= "none" then
				pcall(function()
					OrigamiBuilder.ApplyAnimation(dModel, dAnimType)
				end)
			end
		end
	end

	print(string.format("[ShopKeepers] All shopkeepers spawned (%d shops)", #ShopkeeperData.SHOPS))
end

function ShopKeepers.Clear()
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

return ShopKeepers
