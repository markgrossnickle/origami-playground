local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local Player = Players.LocalPlayer

-- Sound effects (built-in engine sounds — no asset ownership needed)
local _successSound = Instance.new("Sound")
_successSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
_successSound.Volume = 0.5
_successSound.Parent = SoundService

local _failSound = Instance.new("Sound")
_failSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
_failSound.Volume = 0.4
_failSound.Parent = SoundService

local CreatorController = Knit.CreateController({
	Name = "CreatorController",
})

local _trove = Trove.new()
local _selectedCategory = "creature"
local _selectedStyle = "origami"
local _gui: ScreenGui
local _inputBox: TextBox
local _statusLabel: TextLabel
local _createButton: TextButton
local _clearButton: TextButton
local _categoryButtons: { [string]: TextButton } = {}
local _styleButtons: { [string]: TextButton } = {}
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
	container.Size = UDim2.new(0.6, 0, 0, 156)
	container.Position = UDim2.new(0.2, 0, 1, -220)
	container.BackgroundColor3 = COLORS.bg
	container.BackgroundTransparency = 0.1
	container.BorderSizePixel = 0
	container.Parent = _gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	-- Style buttons row (scrollable)
	local styleClip = Instance.new("Frame")
	styleClip.Name = "StyleClip"
	styleClip.Size = UDim2.new(1, -20, 0, 28)
	styleClip.Position = UDim2.new(0, 10, 0, 8)
	styleClip.BackgroundTransparency = 1
	styleClip.ClipsDescendants = true
	styleClip.Parent = container

	local styleRow = Instance.new("ScrollingFrame")
	styleRow.Name = "StyleRow"
	styleRow.Size = UDim2.new(1, 0, 1, 0)
	styleRow.BackgroundTransparency = 1
	styleRow.BorderSizePixel = 0
	styleRow.ScrollBarThickness = 2
	styleRow.ScrollBarImageColor3 = COLORS.accentDim
	styleRow.ScrollingDirection = Enum.ScrollingDirection.X
	styleRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	styleRow.CanvasSize = UDim2.new(0, 0, 0, 28)
	styleRow.Parent = styleClip

	local styleLayout = Instance.new("UIListLayout")
	styleLayout.FillDirection = Enum.FillDirection.Horizontal
	styleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	styleLayout.Padding = UDim.new(0, 4)
	styleLayout.Parent = styleRow

	for _, sty in ipairs(OrigamiConfig.STYLES) do
		local btn = Instance.new("TextButton")
		btn.Name = "Style_" .. sty.key
		btn.Size = UDim2.new(0, 68, 1, 0)
		btn.BackgroundColor3 = COLORS.bgLight
		btn.BorderSizePixel = 0
		btn.Text = sty.display
		btn.TextColor3 = COLORS.textDim
		btn.TextSize = 11
		btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		btn.Parent = styleRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		_styleButtons[sty.key] = btn

		btn.MouseButton1Click:Connect(function()
			_selectedStyle = sty.key
			updateStyleHighlights()
		end)
	end

	-- Category buttons row
	local categoryRow = Instance.new("Frame")
	categoryRow.Name = "CategoryRow"
	categoryRow.Size = UDim2.new(1, -20, 0, 32)
	categoryRow.Position = UDim2.new(0, 10, 0, 40)
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
	inputRow.Position = UDim2.new(0, 10, 0, 82)
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
	_statusLabel.Position = UDim2.new(0, 10, 0, 128)
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

	updateStyleHighlights()
	updateCategoryHighlights()
end

function updateStyleHighlights()
	for key, btn in pairs(_styleButtons) do
		if key == _selectedStyle then
			btn.BackgroundColor3 = COLORS.accentDim
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.bgLight
			btn.TextColor3 = COLORS.textDim
		end
	end
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
	local style = _selectedStyle
	_inputBox.Text = ""

	local queueId = addQueueEntry(prompt, category)

	-- Run async so multiple requests can fly in parallel
	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, category, style):await()

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


-- Snappy paper-fold curve: sharp snap at zero-crossing, holds at extremes
local function foldCurve(raw: number): number
	return math.sign(raw) * math.abs(raw) ^ 0.6
end

-- Apply per-part creature animation based on name prefix
local function applyCreatureAnimation(model: Model, animParts: { [BasePart]: CFrame }, t: number)
	local pivot = model:GetPivot()

	for part, baseOffset in pairs(animParts) do
		if not part.Parent then
			continue
		end

		local name = part.Name
		local animOffset = CFrame.new()

		if name:match("^seg_") then
			-- Body segments: accordion fold
			local idx = tonumber(name:match("%d+")) or 1
			local dir = if idx % 2 == 0 then 1 else -1
			local foldY = foldCurve(math.sin(t * 2.0 + idx * 0.5)) * 0.2 * dir
			local foldAngle = foldCurve(math.cos(t * 1.5 + idx * 0.4)) * math.rad(15) * dir
			animOffset = CFrame.new(0, foldY, 0) * CFrame.Angles(0, foldAngle, 0)

		elseif name:match("^wing_L") then
			-- Left wing: flap up/down via Z rotation
			local idx = tonumber(name:match("%d+")) or 1
			local flapAngle = foldCurve(math.sin(t * 4.0 + idx * 0.3)) * math.rad(35)
			animOffset = CFrame.Angles(0, 0, flapAngle)

		elseif name:match("^wing_R") then
			-- Right wing: flap opposite
			local idx = tonumber(name:match("%d+")) or 1
			local flapAngle = foldCurve(math.sin(t * 4.0 + idx * 0.3)) * math.rad(35)
			animOffset = CFrame.Angles(0, 0, -flapAngle)

		elseif name:match("^tail_") then
			-- Tail: side-to-side sway
			local idx = tonumber(name:match("%d+")) or 1
			local swayAngle = math.sin(t * 3.0 + idx * 0.6) * math.rad(20)
			animOffset = CFrame.Angles(0, swayAngle, 0)

		elseif name:match("^jaw_") then
			-- Jaw: open/close
			local openAngle = (math.sin(t * 2.0) * 0.5 + 0.5) * math.rad(15) -- 0 to 15 degrees
			animOffset = CFrame.Angles(openAngle, 0, 0)

		elseif name:match("^leg_") then
			-- Legs: walking cycle. FL/BL move opposite to FR/BR
			local isLeft = name:match("_[FB]L_")
			local isFront = name:match("_F[LR]_")
			local phase = (if isLeft then 0 else math.pi) + (if isFront then 0 else math.pi / 2)
			local walkAngle = math.sin(t * 5.0 + phase) * math.rad(25)
			animOffset = CFrame.Angles(walkAngle, 0, 0)
		end
		-- else: detail parts (eyes, horns) — no animation, animOffset stays identity

		part.CFrame = pivot * baseOffset * animOffset
	end
end

-- Locomotion configs: speed, wanderRadius, hover height, behavior
local LOCOMOTION_CONFIG = {
	walk = { speed = 4, radius = 20, hoverHeight = 0, pauseMin = 1, pauseMax = 3 },
	slither = { speed = 2, radius = 12, hoverHeight = 0, pauseMin = 2, pauseMax = 5 },
	fly = { speed = 6, radius = 30, hoverHeight = 12, pauseMin = 0.5, pauseMax = 2 },
	float = { speed = 1.5, radius = 15, hoverHeight = 6, pauseMin = 3, pauseMax = 6 },
	hop = { speed = 5, radius = 18, hoverHeight = 0, pauseMin = 0.8, pauseMax = 2 },
	stationary = { speed = 0, radius = 0, hoverHeight = 0, pauseMin = 2, pauseMax = 4 },
}

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

	-- Place in front of player, on ground
	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * OrigamiConfig.PLACEMENT_DISTANCE
	model.Parent = workspace

	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
	model:PivotTo(CFrame.new(placementPos.X, rootPart.Position.Y + pivotAboveBottom, placementPos.Z))

	-- Add name label
	local modelName = modelData.name or "Creature"
	addNameLabel(model, modelName)
	table.insert(_spawnedModels, model)

	-- Collect ALL parts and their offsets from the model pivot for animation
	local animParts: { [BasePart]: CFrame } = {}
	local currentPivot = model:GetPivot()
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			animParts[child] = currentPivot:ToObjectSpace(child.CFrame)
		end
	end

	-- Locomotion type
	local locomotion = modelData.locomotion or "walk"
	local locoConfig = LOCOMOTION_CONFIG[locomotion] or LOCOMOTION_CONFIG.walk

	-- Wandering state
	local spawnPos = model:GetPivot().Position
	local stopped = false
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model, character }

	model.Destroying:Connect(function()
		stopped = true
	end)

	local function raycastGround(x: number, z: number): number
		local result = workspace:Raycast(Vector3.new(x, spawnPos.Y + 50, z), Vector3.new(0, -200, 0), rayParams)
		return if result then result.Position.Y else spawnPos.Y
	end

	local function isAlive(): boolean
		return not stopped and model ~= nil and model.Parent ~= nil and model.PrimaryPart ~= nil
	end

	-- Stationary: just animate in place
	if locomotion == "stationary" then
		task.spawn(function()
			while isAlive() do
				applyCreatureAnimation(model, animParts, tick())
				task.wait(0.03)
			end
		end)
		return
	end

	task.spawn(function()
		while isAlive() do
			-- Pick a random target within wander radius
			local angle = math.random() * math.pi * 2
			local dist = math.random() * locoConfig.radius
			local targetX = spawnPos.X + math.cos(angle) * dist
			local targetZ = spawnPos.Z + math.sin(angle) * dist
			local groundY = raycastGround(targetX, targetZ)

			local startPos = model.PrimaryPart.Position
			local distance = (Vector3.new(targetX, 0, targetZ) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude

			if distance > 1 then
				local lookCF = CFrame.lookAt(startPos, Vector3.new(targetX, startPos.Y, targetZ))
				local lookRot = lookCF - lookCF.Position
				local steps = math.max(1, math.floor(distance / (locoConfig.speed * 0.03)))

				-- Slither: curved sinuous path
				local slitherPhase = math.random() * math.pi * 2

				-- Hop: pre-compute hop count
				local hopCount = 0
				local hopStepsPerHop = 0
				if locomotion == "hop" then
					hopCount = math.max(1, math.floor(distance / 3))
					hopStepsPerHop = math.max(1, math.floor(steps / hopCount))
				end

				for step = 1, steps do
					if not isAlive() then
						break
					end

					local t = step / steps
					local baseX = startPos.X + (targetX - startPos.X) * t
					local baseZ = startPos.Z + (targetZ - startPos.Z) * t
					local baseGroundY = raycastGround(baseX, baseZ)
					local finalY = baseGroundY + pivotAboveBottom
					local finalRot = lookRot

					if locomotion == "slither" then
						-- Sinuous S-curve perpendicular to travel direction
						local perpX = -(targetZ - startPos.Z)
						local perpZ = targetX - startPos.X
						local perpLen = math.sqrt(perpX * perpX + perpZ * perpZ)
						if perpLen > 0.01 then
							perpX, perpZ = perpX / perpLen, perpZ / perpLen
						end
						local sway = math.sin(t * math.pi * 4 + slitherPhase) * 1.2
						baseX = baseX + perpX * sway
						baseZ = baseZ + perpZ * sway
						-- Rotate to face movement direction (tangent of the curve)
						local tangentSway = math.cos(t * math.pi * 4 + slitherPhase) * 1.2 * (math.pi * 4 / distance)
						local yawOffset = math.atan2(tangentSway * perpX, tangentSway * perpZ)
						finalRot = lookRot * CFrame.Angles(0, yawOffset * 0.3, 0)
						finalY = baseGroundY + pivotAboveBottom

					elseif locomotion == "fly" then
						-- Swooping flight: sine wave altitude + bank into turns
						local swoopY = math.sin(t * math.pi * 2) * 4
						finalY = baseGroundY + pivotAboveBottom + locoConfig.hoverHeight + swoopY
						-- Bank slightly into the swoop
						local bankAngle = math.cos(t * math.pi * 2) * math.rad(15)
						finalRot = lookRot * CFrame.Angles(0, 0, bankAngle)

					elseif locomotion == "float" then
						-- Gentle hover with vertical bob
						local bobY = math.sin(tick() * 1.5) * 1.0
						finalY = baseGroundY + pivotAboveBottom + locoConfig.hoverHeight + bobY
						-- Slow gentle yaw drift
						local driftYaw = math.sin(tick() * 0.5) * math.rad(10)
						finalRot = lookRot * CFrame.Angles(0, driftYaw, 0)

					elseif locomotion == "hop" then
						-- Parabolic arc per hop
						local hopIndex = math.floor((step - 1) / hopStepsPerHop)
						local hopT = ((step - 1) % hopStepsPerHop) / hopStepsPerHop
						local arcHeight = math.sin(hopT * math.pi) * 2.5
						finalY = baseGroundY + pivotAboveBottom + arcHeight
						-- Slight forward tilt during hop
						local tiltAngle = math.sin(hopT * math.pi) * math.rad(-20)
						finalRot = lookRot * CFrame.Angles(tiltAngle, 0, 0)

					else -- walk (default)
						finalY = baseGroundY + pivotAboveBottom
					end

					model:PivotTo(CFrame.new(baseX, finalY, baseZ) * finalRot)
					applyCreatureAnimation(model, animParts, tick())
					task.wait(0.03)
				end
			end

			-- Pause at destination with fold animation
			local pauseTime = locoConfig.pauseMin + math.random() * (locoConfig.pauseMax - locoConfig.pauseMin)

			-- Float/fly: keep bobbing during pause
			if locomotion == "float" or locomotion == "fly" then
				local pauseStart = tick()
				while isAlive() and (tick() - pauseStart) < pauseTime do
					local currentPos = model:GetPivot().Position
					local groundY = raycastGround(currentPos.X, currentPos.Z)
					local bobY = math.sin(tick() * 1.5) * 1.0
					local targetY = groundY + pivotAboveBottom + locoConfig.hoverHeight + bobY
					local currentRot = model:GetPivot() - model:GetPivot().Position
					model:PivotTo(CFrame.new(currentPos.X, targetY, currentPos.Z) * currentRot)
					applyCreatureAnimation(model, animParts, tick())
					task.wait(0.03)
				end
			else
				local pauseStart = tick()
				while isAlive() and (tick() - pauseStart) < pauseTime do
					applyCreatureAnimation(model, animParts, tick())
					task.wait(0.03)
				end
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
