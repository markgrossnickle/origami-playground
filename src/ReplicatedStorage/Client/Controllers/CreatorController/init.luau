local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local Player = Players.LocalPlayer

-- Sound effects
local _successSound = Instance.new("Sound")
_successSound.SoundId = "rbxassetid://9125402735"
_successSound.Volume = 0.5
_successSound.Parent = SoundService

local _failSound = Instance.new("Sound")
_failSound.SoundId = "rbxassetid://9118869788"
_failSound.Volume = 0.5
_failSound.Parent = SoundService

local CreatorController = Knit.CreateController({
	Name = "CreatorController",
})

local _trove = Trove.new()
local _selectedCategory = "creature"
local _gui: ScreenGui
local _inputBox: TextBox
local _statusLabel: TextLabel
local _createButton: TextButton
local _clearButton: TextButton
local _categoryButtons: { [string]: TextButton } = {}
local _queueFrame: Frame
local _queueEntries: { { frame: Frame, label: TextLabel, dot: TextLabel } } = {}
local _nextQueueId = 0

-- Track all spawned creations for Clear
local _spawnedModels: { Model } = {}
local _equippedTool: Tool? = nil
local _equippedHat: Accessory? = nil
local _activeVehicle: Model? = nil
local _vehicleSeat: VehicleSeat? = nil
local _avatarApplied = false

-- Colors
local COLORS = {
	bg = Color3.fromRGB(30, 30, 40),
	bgLight = Color3.fromRGB(45, 45, 60),
	accent = Color3.fromRGB(100, 180, 255),
	accentDim = Color3.fromRGB(60, 100, 160),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	disabled = Color3.fromRGB(80, 80, 90),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	danger = Color3.fromRGB(200, 60, 60),
}

local function createUI()
	-- Main ScreenGui
	_gui = Instance.new("ScreenGui")
	_gui.Name = "OrigamiCreator"
	_gui.ResetOnSpawn = false
	_gui.DisplayOrder = 5
	_gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Container at bottom of screen
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0.6, 0, 0, 120)
	container.Position = UDim2.new(0.2, 0, 1, -200)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	-- Category buttons row
	local categoryRow = Instance.new("Frame")
	categoryRow.Name = "CategoryRow"
	categoryRow.Size = UDim2.new(1, -20, 0, 32)
	categoryRow.Position = UDim2.new(0, 10, 0, 10)
	categoryRow.BackgroundTransparency = 1
	categoryRow.Parent = container

	local categoryLayout = Instance.new("UIListLayout")
	categoryLayout.FillDirection = Enum.FillDirection.Horizontal
	categoryLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	categoryLayout.Padding = UDim.new(0, 6)
	categoryLayout.Parent = categoryRow

	for _, cat in ipairs(OrigamiConfig.CATEGORIES) do
		local btn = Instance.new("TextButton")
		btn.Name = "Cat_" .. cat.key
		btn.Size = UDim2.new(0, 72, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = cat.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = categoryRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_categoryButtons[cat.key] = btn

		btn.MouseButton1Click:Connect(function()
			_selectedCategory = cat.key
			updateCategoryHighlights()
		end)
	end

	-- Input row
	local inputRow = Instance.new("Frame")
	inputRow.Name = "InputRow"
	inputRow.Size = UDim2.new(1, -20, 0, 40)
	inputRow.Position = UDim2.new(0, 10, 0, 52)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = container

	-- Text input box
	_inputBox = Instance.new("TextBox")
	_inputBox.Name = "PromptInput"
	_inputBox.Size = UDim2.new(1, -180, 1, 0)
	_inputBox.Position = UDim2.new(0, 0, 0, 0)
	_inputBox.BackgroundColor3 = COLORS.bgLight
	_inputBox.BorderSizePixel = 0
	_inputBox.PlaceholderText = "Type anything..."
	_inputBox.PlaceholderColor3 = COLORS.textDim
	_inputBox.Text = ""
	_inputBox.TextColor3 = COLORS.text
	_inputBox.TextSize = 16
	_inputBox.Font = Enum.Font.Gotham
	_inputBox.ClearTextOnFocus = false
	_inputBox.Parent = inputRow

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 8)
	inputCorner.Parent = _inputBox

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 12)
	inputPadding.PaddingRight = UDim.new(0, 12)
	inputPadding.Parent = _inputBox

	-- Create button
	_createButton = Instance.new("TextButton")
	_createButton.Name = "CreateButton"
	_createButton.Size = UDim2.new(0, 88, 1, 0)
	_createButton.Position = UDim2.new(1, -168, 0, 0)
	_createButton.BackgroundColor3 = COLORS.accent
	_createButton.BorderSizePixel = 0
	_createButton.Text = "Create"
	_createButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_createButton.TextSize = 16
	_createButton.Font = Enum.Font.GothamBold
	_createButton.AutoButtonColor = true
	_createButton.Parent = inputRow

	local createCorner = Instance.new("UICorner")
	createCorner.CornerRadius = UDim.new(0, 8)
	createCorner.Parent = _createButton

	-- Clear button
	_clearButton = Instance.new("TextButton")
	_clearButton.Name = "ClearButton"
	_clearButton.Size = UDim2.new(0, 72, 1, 0)
	_clearButton.Position = UDim2.new(1, -72, 0, 0)
	_clearButton.BackgroundColor3 = COLORS.danger
	_clearButton.BorderSizePixel = 0
	_clearButton.Text = "Clear"
	_clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	_clearButton.TextSize = 16
	_clearButton.Font = Enum.Font.GothamBold
	_clearButton.AutoButtonColor = true
	_clearButton.Parent = inputRow

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 8)
	clearCorner.Parent = _clearButton

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "StatusLabel"
	_statusLabel.Size = UDim2.new(1, -20, 0, 20)
	_statusLabel.Position = UDim2.new(0, 10, 0, 96)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.TextSize = 12
	_statusLabel.Font = Enum.Font.Gotham
	_statusLabel.Parent = container

	-- Wire up submit
	_createButton.MouseButton1Click:Connect(function()
		submitPrompt()
	end)

	_inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitPrompt()
		end
	end)

	-- Wire up clear
	_clearButton.MouseButton1Click:Connect(function()
		clearAllCreations()
	end)

	-- Queue panel (right side of screen)
	_queueFrame = Instance.new("Frame")
	_queueFrame.Name = "QueuePanel"
	_queueFrame.Size = UDim2.new(0, 240, 0, 300)
	_queueFrame.Position = UDim2.new(1, -250, 0.5, -150)
	_queueFrame.AnchorPoint = Vector2.new(0, 0)
	_queueFrame.BackgroundColor3 = COLORS.bg
	_queueFrame.BackgroundTransparency = 0.15
	_queueFrame.BorderSizePixel = 0
	_queueFrame.Visible = false
	_queueFrame.AutomaticSize = Enum.AutomaticSize.Y
	_queueFrame.Parent = _gui

	local queueCorner = Instance.new("UICorner")
	queueCorner.CornerRadius = UDim.new(0, 10)
	queueCorner.Parent = _queueFrame

	local queueLayout = Instance.new("UIListLayout")
	queueLayout.FillDirection = Enum.FillDirection.Vertical
	queueLayout.Padding = UDim.new(0, 4)
	queueLayout.SortOrder = Enum.SortOrder.LayoutOrder
	queueLayout.Parent = _queueFrame

	local queuePadding = Instance.new("UIPadding")
	queuePadding.PaddingTop = UDim.new(0, 8)
	queuePadding.PaddingBottom = UDim.new(0, 8)
	queuePadding.PaddingLeft = UDim.new(0, 8)
	queuePadding.PaddingRight = UDim.new(0, 8)
	queuePadding.Parent = _queueFrame

	_gui.Parent = Player.PlayerGui

	updateCategoryHighlights()
end

function updateCategoryHighlights()
	for key, btn in pairs(_categoryButtons) do
		if key == _selectedCategory then
			btn.BackgroundColor3 = COLORS.accent
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
end

function clearAllCreations()
	-- Remove all spawned models from workspace
	for _, model in ipairs(_spawnedModels) do
		if model and model.Parent then
			model:Destroy()
		end
	end
	_spawnedModels = {}

	-- Remove equipped tool
	if _equippedTool then
		_equippedTool:Destroy()
		_equippedTool = nil
	end

	-- Remove equipped hat parts
	_equippedHat = nil

	-- Remove active vehicle
	if _activeVehicle then
		_activeVehicle:Destroy()
		_activeVehicle = nil
		_vehicleSeat = nil
	end

	-- Reset avatar
	if _avatarApplied then
		local OrigamiService = Knit.GetService("OrigamiService")
		OrigamiService:ResetAvatar():await()
		_avatarApplied = false
	end

	-- Also remove any leftover origami tools from backpack/character
	local character = Player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("OrigamiTool") then
				child:Destroy()
			end
			if child:GetAttribute("OrigamiHat") then
				child:Destroy()
			end
		end
	end

	local backpack = Player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("OrigamiTool") then
				child:Destroy()
			end
		end
	end

	setStatus("All creations cleared!", COLORS.textDim)
end

function addQueueEntry(prompt: string, category: string): number
	_nextQueueId += 1
	local id = _nextQueueId

	local entry = Instance.new("Frame")
	entry.Name = "QueueEntry_" .. id
	entry.Size = UDim2.new(1, 0, 0, 28)
	entry.BackgroundColor3 = COLORS.bgLight
	entry.BackgroundTransparency = 0.3
	entry.BorderSizePixel = 0
	entry.LayoutOrder = id
	entry.Parent = _queueFrame

	local entryCorner = Instance.new("UICorner")
	entryCorner.CornerRadius = UDim.new(0, 6)
	entryCorner.Parent = entry

	-- Status dot
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.Position = UDim2.new(0, 6, 0.5, -4)
	dot.BackgroundColor3 = COLORS.accent
	dot.BorderSizePixel = 0
	dot.Parent = entry

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	-- Label
	local shortPrompt = prompt:sub(1, 22) .. (if #prompt > 22 then "..." else "")
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 20, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = shortPrompt .. "  Folding..."
	label.TextColor3 = COLORS.text
	label.TextSize = 11
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = entry

	_queueEntries[id] = { frame = entry, label = label, dot = dot, prompt = prompt }
	_queueFrame.Visible = true

	return id
end

function updateQueueEntry(id: number, status: string, color: Color3)
	local entry = _queueEntries[id]
	if not entry then
		return
	end

	local shortPrompt = entry.prompt:sub(1, 22) .. (if #entry.prompt > 22 then "..." else "")
	entry.label.Text = shortPrompt .. "  " .. status
	entry.dot.BackgroundColor3 = color
end

function removeQueueEntry(id: number)
	local entry = _queueEntries[id]
	if not entry then
		return
	end

	task.delay(5, function()
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
		_queueEntries[id] = nil

		-- Hide queue panel if empty
		local hasEntries = false
		for _ in pairs(_queueEntries) do
			hasEntries = true
			break
		end
		if not hasEntries then
			_queueFrame.Visible = false
		end
	end)
end

function submitPrompt()
	local prompt = _inputBox.Text
	if not prompt or prompt:match("^%s*$") then
		setStatus("Type something first!", COLORS.error)
		return
	end

	local category = _selectedCategory
	_inputBox.Text = ""

	local queueId = addQueueEntry(prompt, category)

	-- Run async so multiple requests can fly in parallel
	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, category):await()

		if ok and result and result.success and result.model then
			local modelData = result.model
			local cat = modelData.category or category

			local buildOk, buildErr = pcall(function()
				local model = OrigamiBuilder.BuildModel(modelData)

				if cat == "tool" then
					equipAsTool(model, modelData)
				elseif cat == "hat" then
					equipAsHat(model, modelData)
				elseif cat == "vehicle" then
					spawnVehicle(model, modelData)
				elseif cat == "avatar" then
					applyAvatar(model, modelData)
				elseif cat == "building" then
					placeBuilding(model, modelData)
				elseif cat == "creature" then
					spawnCreature(model, modelData)
				else
					placeModel(model, modelData)
				end

				if cat ~= "tool" and cat ~= "hat" and cat ~= "vehicle" and cat ~= "avatar" and cat ~= "creature" then
					local animType = modelData.animation or "idle_bob"
					OrigamiBuilder.ApplyAnimation(model, animType)
				end
			end)

			if buildOk then
				local modelName = modelData.name or "Creation"
				updateQueueEntry(queueId, modelName, COLORS.success)
				_successSound:Play()
			else
				warn("[OrigamiCreator] Build/place error:", buildErr)
				updateQueueEntry(queueId, "Build error", COLORS.error)
				_failSound:Play()
			end
		else
			local errMsg = (ok and result and result.error) or (not ok and tostring(result)) or "Unknown error"
			updateQueueEntry(queueId, "Failed: " .. errMsg:sub(1, 30), COLORS.error)
			_failSound:Play()
		end

		removeQueueEntry(queueId)
	end)
end

function equipAsTool(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		return
	end

	-- Remove previous origami tool (only one at a time)
	if _equippedTool then
		_equippedTool:Destroy()
		_equippedTool = nil
	end

	-- Also remove from backpack
	local backpack = Player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("OrigamiTool") then
				child:Destroy()
			end
		end
	end

	-- Create a Roblox Tool
	local tool = Instance.new("Tool")
	tool.Name = modelData.name or "Tool"
	tool:SetAttribute("OrigamiTool", true)
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	-- Create handle from the model parts
	-- Weld all parts to a single Handle part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Parent = tool

	-- Move model parts into the tool and weld to handle
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
			part.Parent = tool
		end
	end

	-- Set grip so it's held properly (handle at bottom)
	tool.GripPos = Vector3.new(0, -0.5, 0)

	model:Destroy() -- Parts moved out, clean up empty model

	-- Put in backpack (auto-equips if only tool)
	tool.Parent = backpack or character
	_equippedTool = tool

	-- Track for clear
	table.insert(_spawnedModels, tool)

	-- Auto-equip
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

function equipAsHat(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	-- Remove previous origami hat parts
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("OrigamiHat") then
			child:Destroy()
		end
	end
	_equippedHat = nil

	-- Get model bounds and scale down if too large
	local MAX_HAT_SIZE = 3
	local _, modelSize = model:GetBoundingBox()
	local maxDim = math.max(modelSize.X, modelSize.Y, modelSize.Z)
	local scale = if maxDim > MAX_HAT_SIZE then MAX_HAT_SIZE / maxDim else 1

	local modelCenter = Vector3.zero
	if model.PrimaryPart then
		modelCenter = model.PrimaryPart.Position
	end

	-- Position on top of head
	local headTop = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0)

	-- Collect parts before reparenting
	local partsToMove = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(partsToMove, part)
		end
	end

	-- Weld each part directly to the head
	for _, part in ipairs(partsToMove) do
		if scale < 1 then
			part.Size = part.Size * scale
		end

		local offset = (part.Position - modelCenter) * scale
		local partRotation = part.CFrame - part.CFrame.Position

		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		part:SetAttribute("OrigamiHat", true)
		part.CFrame = headTop * CFrame.new(offset) * partRotation
		part.Parent = character

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
	end

	model:Destroy()

	_equippedHat = head -- marker; cleanup uses OrigamiHat attribute
end

function spawnVehicle(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Remove previous vehicle
	if _activeVehicle then
		_activeVehicle:Destroy()
		_activeVehicle = nil
		_vehicleSeat = nil
	end

	-- Place vehicle in front of player
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	placementPos = Vector3.new(placementPos.X, rootPart.Position.Y, placementPos.Z)

	-- Create VehicleSeat as the driver seat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.Anchored = true -- Keep anchored until positioned
	seat.CanCollide = true
	seat.Transparency = 1
	seat.MaxSpeed = 50
	seat.Torque = 10
	seat.TurnSpeed = 8
	seat.Material = Enum.Material.SmoothPlastic
	seat.Parent = model

	-- Make seat the PrimaryPart so the model pivots around it
	model.PrimaryPart = seat

	-- Position the whole model first (while still anchored)
	local _, lookY, _ = rootPart.CFrame:ToEulerAnglesYXZ()
	model.Parent = workspace
	model:PivotTo(CFrame.new(placementPos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, lookY, 0))

	-- Weld all visual parts to the seat — massless so they don't tip it
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= seat then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seat
			weld.Part1 = part
			weld.Parent = part
		end
	end

	-- Add an invisible collision plate at the bottom for ground contact
	local _, modelSize = model:GetBoundingBox()
	local collisionPlate = Instance.new("Part")
	collisionPlate.Name = "CollisionPlate"
	collisionPlate.Size = Vector3.new(math.min(modelSize.X * 0.8, 14), 0.5, math.min(modelSize.Z * 0.8, 16))
	collisionPlate.Transparency = 1
	collisionPlate.CanCollide = true
	collisionPlate.Massless = true
	collisionPlate.Anchored = false
	collisionPlate.Material = Enum.Material.SmoothPlastic
	-- Position at bottom of model
	collisionPlate.CFrame = seat.CFrame * CFrame.new(0, -modelSize.Y / 2 + 0.25, 0)
	collisionPlate.Parent = model

	local plateWeld = Instance.new("WeldConstraint")
	plateWeld.Part0 = seat
	plateWeld.Part1 = collisionPlate
	plateWeld.Parent = collisionPlate

	-- Un-anchor seat last so everything is welded before physics kicks in
	seat.Anchored = false

	-- Add BillboardGui with name + "Sit to drive" hint
	local modelName = modelData.name or "Vehicle"
	addNameLabel(model, modelName .. " (Walk up to drive)")

	-- Add ProximityPrompt — walks the player to the seat so auto-sit triggers
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = modelName
	prompt.ActionText = "Drive"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 20
	prompt.Parent = seat

	prompt.Triggered:Connect(function()
		local char = Player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:MoveTo(seat.Position)
		end
	end)

	_activeVehicle = model
	_vehicleSeat = seat

	-- Track for clear
	table.insert(_spawnedModels, model)

end

function applyAvatar(model: Model, modelData: { [string]: any })
	-- Send model data to server to apply as avatar skin
	local OrigamiService = Knit.GetService("OrigamiService")
	local ok, result = OrigamiService:ApplyAvatar(modelData):await()

	-- Destroy the built model — server applies directly to character
	model:Destroy()

	if ok and result and result.success then
		_avatarApplied = true
		local modelName = modelData.name or "Avatar"
		setStatus("Transformed into: " .. modelName, COLORS.success)
	else
		setStatus("Failed to apply avatar", COLORS.error)
	end
end

function setStatus(text: string, color: Color3?)
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim

	-- Auto-clear after 5 seconds
	task.delay(5, function()
		if _statusLabel.Text == text then
			_statusLabel.Text = ""
		end
	end)
end


function spawnCreature(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	-- Place in front of player
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	placementPos = Vector3.new(placementPos.X, rootPart.Position.Y, placementPos.Z)

	-- Parent and position
	model.Parent = workspace
	if model.PrimaryPart then
		local _, size = model:GetBoundingBox()
		local halfHeight = size.Y / 2
		model:PivotTo(CFrame.new(placementPos.X, placementPos.Y + halfHeight, placementPos.Z))
	end

	-- Add name label
	local modelName = modelData.name or "Creature"
	addNameLabel(model, modelName)
	table.insert(_spawnedModels, model)

	-- Start wandering behavior
	local spawnPos = placementPos
	local wanderRadius = 20
	local moveSpeed = 4
	local stopped = false

	-- Bob animation while walking
	local startTime = tick()
	local bobConnection: RBXScriptConnection
	local origins = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			origins[part] = part.Position - (model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero)
		end
	end

	model.Destroying:Connect(function()
		stopped = true
		if bobConnection then
			bobConnection:Disconnect()
		end
	end)

	task.spawn(function()
		while not stopped and model and model.Parent do
			-- Pick a random point within wander radius of spawn
			local angle = math.random() * math.pi * 2
			local dist = math.random() * wanderRadius
			local targetX = spawnPos.X + math.cos(angle) * dist
			local targetZ = spawnPos.Z + math.sin(angle) * dist

			-- Raycast to find ground at target
			local rayResult = workspace:Raycast(
				Vector3.new(targetX, spawnPos.Y + 50, targetZ),
				Vector3.new(0, -200, 0),
				(function()
					local p = RaycastParams.new()
					p.FilterType = Enum.RaycastFilterType.Exclude
					p.FilterDescendantsInstances = { model, character }
					return p
				end)()
			)
			local groundY = if rayResult then rayResult.Position.Y else spawnPos.Y

			local targetPos = Vector3.new(targetX, groundY, targetZ)

			if not model or not model.Parent or not model.PrimaryPart then
				break
			end

			-- Move toward target
			local startPos = model.PrimaryPart.Position
			local direction = (targetPos - startPos)
			local flatDir = Vector3.new(direction.X, 0, direction.Z)
			local distance = flatDir.Magnitude

			if distance > 1 then
				-- Face the target
				local lookCF = CFrame.lookAt(startPos, Vector3.new(targetPos.X, startPos.Y, targetPos.Z))
				local _, modelSize = model:GetBoundingBox()
				local halfH = modelSize.Y / 2
				local steps = math.max(1, math.floor(distance / (moveSpeed * 0.03)))

				for step = 1, steps do
					if stopped or not model or not model.Parent or not model.PrimaryPart then
						break
					end

					local t = step / steps
					local pos = startPos:Lerp(targetPos, t)

					-- Raycast for ground at this position
					local midRay = workspace:Raycast(
						Vector3.new(pos.X, spawnPos.Y + 50, pos.Z),
						Vector3.new(0, -200, 0),
						(function()
							local p = RaycastParams.new()
							p.FilterType = Enum.RaycastFilterType.Exclude
							p.FilterDescendantsInstances = { model, character }
							return p
						end)()
					)
					local midY = if midRay then midRay.Position.Y else spawnPos.Y

					-- Bob up and down while walking
					local bobOffset = math.sin(tick() * 6) * 0.3

					model:PivotTo(
						CFrame.new(pos.X, midY + halfH + bobOffset, pos.Z)
						* (lookCF - lookCF.Position)
					)

					task.wait(0.03)
				end
			end

			-- Pause at destination
			local pauseTime = 1 + math.random() * 3
			local pauseStart = tick()
			while not stopped and model and model.Parent and (tick() - pauseStart) < pauseTime do
				-- Idle bob while paused
				if model.PrimaryPart then
					local currentPos = model.PrimaryPart.Position
					local bobOffset = math.sin(tick() * 2) * 0.3
					local _, modelSize = model:GetBoundingBox()
					local halfH = modelSize.Y / 2

					local midRay = workspace:Raycast(
						Vector3.new(currentPos.X, spawnPos.Y + 50, currentPos.Z),
						Vector3.new(0, -200, 0),
						(function()
							local p = RaycastParams.new()
							p.FilterType = Enum.RaycastFilterType.Exclude
							p.FilterDescendantsInstances = { model, character }
							return p
						end)()
					)
					local groundAtPos = if midRay then midRay.Position.Y else spawnPos.Y

					model:PivotTo(
						CFrame.new(currentPos.X, groundAtPos + halfH + bobOffset, currentPos.Z)
						* (model.PrimaryPart.CFrame - model.PrimaryPart.CFrame.Position)
					)
				end
				task.wait(0.03)
			end
		end
	end)
end

function placeBuilding(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	-- Place in front of player
	local forward = rootPart.CFrame.LookVector
	local targetPos = rootPart.Position + forward * OrigamiConfig.PLACEMENT_DISTANCE

	-- Raycast down to find the ground
	local rayOrigin = Vector3.new(targetPos.X, rootPart.Position.Y + 50, targetPos.Z)
	local rayDir = Vector3.new(0, -200, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, model }

	local result = workspace:Raycast(rayOrigin, rayDir, params)
	local groundY = if result then result.Position.Y else rootPart.Position.Y - 3

	-- Position building flush on the ground
	model.Parent = workspace
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	-- How far the pivot sits above the bounding box bottom
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
	model:PivotTo(CFrame.new(targetPos.X, groundY + pivotAboveBottom, targetPos.Z))

	-- Add name label
	local modelName = modelData.name or "Building"
	addNameLabel(model, modelName)

	table.insert(_spawnedModels, model)
end

function placeModel(model: Model, modelData: { [string]: any })
	local character = Player.Character
	if not character then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		model.Parent = workspace
		table.insert(_spawnedModels, model)
		return
	end

	-- Place model in front of player
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	placementPos = Vector3.new(placementPos.X, rootPart.Position.Y, placementPos.Z)

	-- Position the model in front of player, on the ground
	model.Parent = workspace
	if model.PrimaryPart then
		local _, size = model:GetBoundingBox()
		local halfHeight = size.Y / 2
		model:PivotTo(CFrame.new(placementPos.X, placementPos.Y + halfHeight, placementPos.Z))
	end

	-- Add BillboardGui with name
	local modelName = modelData.name or "Creation"
	addNameLabel(model, modelName)

	-- Track for clear
	table.insert(_spawnedModels, model)
end

function addNameLabel(model: Model, name: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameLabel"
	billboard.Size = UDim2.new(0, 200, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 50

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if target then
		billboard.Adornee = target
		billboard.Parent = target
	end
end

function CreatorController:KnitInit()
end

function CreatorController:KnitStart()
	createUI()

	local OrigamiService = Knit.GetService("OrigamiService")
	OrigamiService.ModelGenerated:Connect(function(modelData)
	end)
end

return CreatorController
