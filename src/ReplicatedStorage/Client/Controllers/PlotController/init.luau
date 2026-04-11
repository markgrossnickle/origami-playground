--[[
	PlotController — client-side surface plot building and visiting.
	Plot HUD, material palette, build mode (B key toggle), block rendering,
	creature display, visit menu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiUnfold = require(ReplicatedStorage.Shared.OrigamiUnfold)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local VFXUtil = require(ReplicatedStorage.Shared.VFXUtil)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local COLORS = {
	bg = Color3.fromRGB(25, 25, 35),
	panel = Color3.fromRGB(35, 35, 50),
	card = Color3.fromRGB(45, 45, 65),
	text = Color3.fromRGB(230, 230, 240),
	textDim = Color3.fromRGB(140, 140, 160),
	success = Color3.fromRGB(100, 220, 140),
	error = Color3.fromRGB(220, 100, 100),
	accent = Color3.fromRGB(100, 180, 255),
	buildMode = Color3.fromRGB(255, 200, 80),
}

-- State
local _screenGui: ScreenGui? = nil
local _visible = false
local _buildMode = false
local _plotData = nil -- { plotIndex, placedBlocks, assignedCreatures, origin }
local _plotOrigin: Vector3? = nil
local _renderedBlocks: { [string]: BasePart } = {} -- "x,y,z" → Part
local _creatureModels: { [string]: { model: Model, cleanup: (() -> ())? } } = {}
local _selectedMaterial: string? = nil
local _ghostBlock: BasePart? = nil
local _plotFolder: Folder? = nil
local _hudFrame: Frame? = nil
local _paletteFrame: Frame? = nil
local _visitFrame: Frame? = nil

local function createCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

-- Block Rendering

local function getOrCreatePlotFolder(): Folder
	if _plotFolder and _plotFolder.Parent then
		return _plotFolder
	end
	_plotFolder = Instance.new("Folder")
	_plotFolder.Name = "PlotBlocks"
	_plotFolder.Parent = workspace
	return _plotFolder
end

local function renderBlock(key: string, materialId: string)
	if _renderedBlocks[key] then
		return -- already rendered
	end

	local blockConfig = PlotConfig.PLACEABLE_BLOCKS[materialId]
	if not blockConfig or not _plotOrigin then
		return
	end

	-- Parse key "x,y,z"
	local lx, ly, lz = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
	lx, ly, lz = tonumber(lx), tonumber(ly), tonumber(lz)
	if not lx then
		return
	end

	local worldPos = PlotConfig.localToWorld(_plotOrigin, lx, ly, lz)

	local part = Instance.new("Part")
	part.Name = "PlotBlock_" .. key
	part.Size = Vector3.new(PlotConfig.BLOCK_SIZE, PlotConfig.BLOCK_SIZE, PlotConfig.BLOCK_SIZE)
	part.Position = worldPos
	part.Anchored = true
	part.Color = Color3.fromRGB(blockConfig.color[1], blockConfig.color[2], blockConfig.color[3])
	part.Material = Enum.Material[blockConfig.material] or Enum.Material.SmoothPlastic
	part.Parent = getOrCreatePlotFolder()

	_renderedBlocks[key] = part
end

local function unrenderBlock(key: string)
	local part = _renderedBlocks[key]
	if part then
		part:Destroy()
		_renderedBlocks[key] = nil
	end
end

local function clearRenderedBlocks()
	for key, part in pairs(_renderedBlocks) do
		part:Destroy()
	end
	_renderedBlocks = {}
end

local function renderAllBlocks(placedBlocks: { [string]: string })
	clearRenderedBlocks()
	for key, materialId in pairs(placedBlocks) do
		renderBlock(key, materialId)
	end
end

-- Creature Display

local function clearCreatures()
	for _, entry in pairs(_creatureModels) do
		if entry.cleanup then
			entry.cleanup()
		end
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
	end
	_creatureModels = {}
end

local function spawnPlotCreature(creatureId: string, localX: number, localZ: number)
	if not _plotOrigin then
		return
	end
	-- Fetch creature data from server
	task.spawn(function()
		local CreatureService = Knit.GetService("CreatureService")
		local success, creatures = CreatureService:GetCreatures():await()
		if not success or type(creatures) ~= "table" then
			return
		end

		local creature = nil
		for _, c in ipairs(creatures) do
			if c.id == creatureId then
				creature = c
				break
			end
		end
		if not creature or not creature.modelData then
			return
		end

		local model = OrigamiBuilder.BuildModel(creature.modelData)
		if not model then
			return
		end

		local worldPos = PlotConfig.localToWorld(_plotOrigin, localX, 0, localZ)
		model.Name = creature.name or "Creature"
		model:SetAttribute("CreatureId", creatureId)
		model.Parent = workspace
		model:PivotTo(CFrame.new(worldPos))

		local character = Player.Character
		local entry = { model = model, cleanup = nil :: (() -> ())? }
		_creatureModels[creatureId] = entry
		OrigamiUnfold.Animate(model, worldPos, function()
			if not model.Parent or _creatureModels[creatureId] ~= entry then
				return
			end
			entry.cleanup = CreatureAI.Start(model, creature.modelData, worldPos, { model, character })
		end)
	end)
end

-- Ghost Block (Build Mode Preview)

local function createGhostBlock()
	if _ghostBlock then
		_ghostBlock:Destroy()
	end
	_ghostBlock = Instance.new("Part")
	_ghostBlock.Name = "GhostBlock"
	_ghostBlock.Size = Vector3.new(PlotConfig.BLOCK_SIZE, PlotConfig.BLOCK_SIZE, PlotConfig.BLOCK_SIZE)
	_ghostBlock.Anchored = true
	_ghostBlock.CanCollide = false
	_ghostBlock.Transparency = 0.5
	_ghostBlock.Color = Color3.fromRGB(100, 200, 255)
	_ghostBlock.Material = Enum.Material.Neon
	_ghostBlock.Parent = workspace
	return _ghostBlock
end

local function updateGhostBlock()
	if not _buildMode or not _plotOrigin or not _selectedMaterial or not _ghostBlock then
		if _ghostBlock then
			_ghostBlock.Transparency = 1
		end
		return
	end

	local mouse = Player:GetMouse()
	local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { _ghostBlock, Player.Character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
	if not result then
		_ghostBlock.Transparency = 1
		return
	end

	-- Snap to grid: compute which block face was hit, place adjacent
	local hitPos = result.Position + result.Normal * 0.1
	local lx, ly, lz = PlotConfig.worldToLocal(_plotOrigin, hitPos)

	if not PlotConfig.isInBounds(lx, ly, lz) then
		_ghostBlock.Transparency = 1
		return
	end

	local worldPos = PlotConfig.localToWorld(_plotOrigin, lx, ly, lz)
	_ghostBlock.Position = worldPos
	_ghostBlock.Transparency = 0.5

	local blockConfig = PlotConfig.PLACEABLE_BLOCKS[_selectedMaterial]
	if blockConfig then
		_ghostBlock.Color = Color3.fromRGB(blockConfig.color[1], blockConfig.color[2], blockConfig.color[3])
	end
end

local function destroyGhostBlock()
	if _ghostBlock then
		_ghostBlock:Destroy()
		_ghostBlock = nil
	end
end

-- Plot Floor (visual boundary)

local function renderPlotFloor()
	if not _plotOrigin then
		return
	end
	local folder = getOrCreatePlotFolder()

	-- Base plate
	local base = Instance.new("Part")
	base.Name = "PlotBase"
	base.Size = Vector3.new(PlotConfig.PLOT_SIZE_STUDS, 1, PlotConfig.PLOT_SIZE_STUDS)
	base.Position = _plotOrigin + Vector3.new(PlotConfig.PLOT_SIZE_STUDS / 2, -0.5, PlotConfig.PLOT_SIZE_STUDS / 2)
	base.Anchored = true
	base.Color = Color3.fromRGB(80, 120, 80)
	base.Material = Enum.Material.Grass
	base.Parent = folder

	-- Border posts (corners)
	for _, corner in ipairs({
		Vector3.new(0, 0, 0),
		Vector3.new(PlotConfig.PLOT_SIZE_STUDS, 0, 0),
		Vector3.new(0, 0, PlotConfig.PLOT_SIZE_STUDS),
		Vector3.new(PlotConfig.PLOT_SIZE_STUDS, 0, PlotConfig.PLOT_SIZE_STUDS),
	}) do
		local post = Instance.new("Part")
		post.Name = "PlotPost"
		post.Size = Vector3.new(1, 8, 1)
		post.Position = _plotOrigin + corner + Vector3.new(0, 4, 0)
		post.Anchored = true
		post.Color = Color3.fromRGB(200, 180, 140)
		post.Material = Enum.Material.Wood
		post.Parent = folder
	end
end

-- UI

local function buildUI()
	if _screenGui then
		_screenGui:Destroy()
	end

	_screenGui = Instance.new("ScreenGui")
	_screenGui.Name = "PlotUI"
	_screenGui.ResetOnSpawn = false
	_screenGui.DisplayOrder = 10
	_screenGui.Parent = PlayerGui

	-- Toggle button
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "PlotToggle"
	toggleBtn.Size = UDim2.fromOffset(44, 44)
	toggleBtn.Position = UDim2.new(0, 10, 0.5, 30)
	toggleBtn.BackgroundColor3 = COLORS.panel
	toggleBtn.Text = "🏠"
	toggleBtn.TextSize = 22
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextColor3 = COLORS.text
	toggleBtn.Parent = _screenGui
	createCorner(toggleBtn, 10)

	-- Plot HUD (shown when on plot)
	_hudFrame = Instance.new("Frame")
	_hudFrame.Name = "PlotHUD"
	_hudFrame.Size = UDim2.fromOffset(200, 60)
	_hudFrame.Position = UDim2.new(0.5, -100, 0, 10)
	_hudFrame.BackgroundColor3 = COLORS.bg
	_hudFrame.BackgroundTransparency = 0.3
	_hudFrame.Visible = false
	_hudFrame.Parent = _screenGui
	createCorner(_hudFrame, 8)

	local hudLabel = Instance.new("TextLabel")
	hudLabel.Name = "HUDLabel"
	hudLabel.Size = UDim2.fromScale(1, 1)
	hudLabel.BackgroundTransparency = 1
	hudLabel.Text = "Your Plot"
	hudLabel.TextColor3 = COLORS.text
	hudLabel.TextSize = 12
	hudLabel.Font = Enum.Font.GothamBold
	hudLabel.Parent = _hudFrame

	-- Build/remove buttons hidden — use B key on desktop to toggle build mode

	-- Material palette (horizontal bar, bottom of screen)
	_paletteFrame = Instance.new("Frame")
	_paletteFrame.Name = "MaterialPalette"
	_paletteFrame.Size = UDim2.new(0, 0, 0, 50)
	_paletteFrame.Position = UDim2.new(0.5, 0, 1, -60)
	_paletteFrame.AnchorPoint = Vector2.new(0.5, 0)
	_paletteFrame.BackgroundColor3 = COLORS.bg
	_paletteFrame.BackgroundTransparency = 0.3
	_paletteFrame.Visible = false
	_paletteFrame.Parent = _screenGui
	createCorner(_paletteFrame, 8)

	local paletteLayout = Instance.new("UIListLayout")
	paletteLayout.FillDirection = Enum.FillDirection.Horizontal
	paletteLayout.Padding = UDim.new(0, 4)
	paletteLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	paletteLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	paletteLayout.Parent = _paletteFrame

	local palettePadding = Instance.new("UIPadding")
	palettePadding.PaddingLeft = UDim.new(0, 6)
	palettePadding.PaddingRight = UDim.new(0, 6)
	palettePadding.Parent = _paletteFrame

	-- Visit menu (simple panel)
	_visitFrame = Instance.new("Frame")
	_visitFrame.Name = "VisitMenu"
	_visitFrame.Size = UDim2.new(0.75, 0, 0.55, 0)
	_visitFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	_visitFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	_visitFrame.BackgroundColor3 = COLORS.bg
	_visitFrame.BorderSizePixel = 0
	_visitFrame.Visible = false
	_visitFrame.Parent = _screenGui
	createCorner(_visitFrame, 12)

	local visitSizeConstraint = Instance.new("UISizeConstraint")
	visitSizeConstraint.MaxSize = Vector2.new(300, 360)
	visitSizeConstraint.MinSize = Vector2.new(200, 250)
	visitSizeConstraint.Parent = _visitFrame

	local visitTitle = Instance.new("TextLabel")
	visitTitle.Size = UDim2.new(1, 0, 0, 32)
	visitTitle.BackgroundColor3 = COLORS.panel
	visitTitle.Text = "Visit Plots"
	visitTitle.TextColor3 = COLORS.text
	visitTitle.TextSize = 14
	visitTitle.Font = Enum.Font.GothamBold
	visitTitle.Parent = _visitFrame
	createCorner(visitTitle, 12)

	local visitScroll = Instance.new("ScrollingFrame")
	visitScroll.Name = "OwnerList"
	visitScroll.Size = UDim2.new(1, -12, 1, -80)
	visitScroll.Position = UDim2.fromOffset(6, 36)
	visitScroll.BackgroundTransparency = 1
	visitScroll.ScrollBarThickness = 4
	visitScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	visitScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	visitScroll.Parent = _visitFrame

	local visitLayout = Instance.new("UIListLayout")
	visitLayout.Padding = UDim.new(0, 4)
	visitLayout.Parent = visitScroll

	-- Claim / Go to Plot / Visit buttons
	local actionFrame = Instance.new("Frame")
	actionFrame.Size = UDim2.new(1, -12, 0, 36)
	actionFrame.Position = UDim2.new(0, 6, 1, -42)
	actionFrame.BackgroundTransparency = 1
	actionFrame.Parent = _visitFrame

	local claimBtn = Instance.new("TextButton")
	claimBtn.Name = "ClaimBtn"
	claimBtn.Size = UDim2.new(0.5, -2, 1, 0)
	claimBtn.BackgroundColor3 = COLORS.success
	claimBtn.Text = "Claim Plot"
	claimBtn.TextColor3 = COLORS.bg
	claimBtn.TextSize = 12
	claimBtn.Font = Enum.Font.GothamBold
	claimBtn.Parent = actionFrame
	createCorner(claimBtn, 6)

	local goToBtn = Instance.new("TextButton")
	goToBtn.Name = "GoToBtn"
	goToBtn.Size = UDim2.new(0.5, -2, 1, 0)
	goToBtn.Position = UDim2.new(0.5, 2, 0, 0)
	goToBtn.BackgroundColor3 = COLORS.accent
	goToBtn.Text = "Go to My Plot"
	goToBtn.TextColor3 = COLORS.bg
	goToBtn.TextSize = 12
	goToBtn.Font = Enum.Font.GothamBold
	goToBtn.Parent = actionFrame
	createCorner(goToBtn, 6)

	local visitCloseBtn = Instance.new("TextButton")
	visitCloseBtn.Size = UDim2.fromOffset(24, 24)
	visitCloseBtn.Position = UDim2.new(1, -28, 0, 4)
	visitCloseBtn.BackgroundTransparency = 1
	visitCloseBtn.Text = "X"
	visitCloseBtn.TextColor3 = COLORS.textDim
	visitCloseBtn.TextSize = 12
	visitCloseBtn.Font = Enum.Font.GothamBold
	visitCloseBtn.Parent = _visitFrame

	-- Event handlers
	toggleBtn.MouseButton1Click:Connect(function()
		_visible = not _visible
		_visitFrame.Visible = _visible
		if _visible then
			refreshVisitMenu()
		end
	end)

	visitCloseBtn.MouseButton1Click:Connect(function()
		_visible = false
		_visitFrame.Visible = false
	end)

	claimBtn.MouseButton1Click:Connect(function()
		task.spawn(function()
			local PlotService = Knit.GetService("PlotService")
			local result = PlotService:ClaimPlot():await()
			if result and result.success then
				loadMyPlot()
				teleportToPlot(Vector3.new(result.origin[1], result.origin[2], result.origin[3]))
				_visitFrame.Visible = false
			end
		end)
	end)

	goToBtn.MouseButton1Click:Connect(function()
		task.spawn(function()
			local PlotService = Knit.GetService("PlotService")
			local result = PlotService:GetPlotData():await()
			if result and result.origin then
				loadMyPlot()
				teleportToPlot(Vector3.new(result.origin[1], result.origin[2], result.origin[3]))
				_visitFrame.Visible = false
			end
		end)
	end)
end

function refreshVisitMenu()
	if not _visitFrame then
		return
	end

	task.spawn(function()
		local PlotService = Knit.GetService("PlotService")
		local success, owners = PlotService:GetPlotOwners():await()

		local scroll = _visitFrame:FindFirstChild("OwnerList")
		if not scroll then
			return
		end

		-- Clear
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		if not success or type(owners) ~= "table" or #owners == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, 0, 0, 30)
			empty.BackgroundTransparency = 1
			empty.Text = "No other players with plots online"
			empty.TextColor3 = COLORS.textDim
			empty.TextSize = 11
			empty.Font = Enum.Font.Gotham
			empty.Parent = scroll
			return
		end

		for _, owner in ipairs(owners) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 0, 30)
			btn.BackgroundColor3 = COLORS.card
			btn.Text = "Visit " .. owner.displayName
			btn.TextColor3 = COLORS.text
			btn.TextSize = 12
			btn.Font = Enum.Font.GothamBold
			btn.Parent = scroll
			createCorner(btn, 6)

			btn.MouseButton1Click:Connect(function()
				visitPlot(owner.userId)
				_visitFrame.Visible = false
			end)
		end
	end)
end

function teleportToPlot(origin: Vector3)
	local character = Player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		-- Teleport to center of plot
		local center = origin + Vector3.new(PlotConfig.PLOT_SIZE_STUDS / 2, 5, PlotConfig.PLOT_SIZE_STUDS / 2)
		rootPart.CFrame = CFrame.new(center)
	end
end

function loadMyPlot()
	task.spawn(function()
		local PlotService = Knit.GetService("PlotService")
		local success, data = PlotService:GetPlotData():await()

		if not success or type(data) ~= "table" or not data.origin then
			return
		end

		_plotData = data
		_plotOrigin = Vector3.new(data.origin[1], data.origin[2], data.origin[3])

		clearRenderedBlocks()
		clearCreatures()
		renderPlotFloor()
		renderAllBlocks(data.placedBlocks or {})

		-- Spawn assigned creatures
		for _, entry in ipairs(data.assignedCreatures or {}) do
			spawnPlotCreature(entry.creatureId, entry.localX, entry.localZ)
		end

		updateHUD()
	end)
end

function visitPlot(ownerUserId: number)
	task.spawn(function()
		local PlotService = Knit.GetService("PlotService")
		local result = PlotService:GetPlotDataForVisit(ownerUserId):await()

		if not result or not result.success then
			return
		end

		_plotData = result
		_plotOrigin = Vector3.new(result.origin[1], result.origin[2], result.origin[3])

		clearRenderedBlocks()
		clearCreatures()
		renderPlotFloor()
		renderAllBlocks(result.placedBlocks or {})

		teleportToPlot(_plotOrigin)

		-- Subscribe for live updates
		PlotService:SubscribePlot(ownerUserId)
	end)
end

function updateHUD()
	if not _hudFrame or not _plotData then
		_hudFrame.Visible = false
		return
	end

	_hudFrame.Visible = true
	local label = _hudFrame:FindFirstChild("HUDLabel")
	if label then
		local blockCount = _plotData.blockCount or 0
		local creatureCount = #(_plotData.assignedCreatures or {})
		label.Text = string.format(
			"Your Plot  |  Blocks: %d/%d  |  Creatures: %d/%d%s",
			blockCount,
			PlotConfig.MAX_BLOCKS,
			creatureCount,
			PlotConfig.MAX_CREATURES,
			if _buildMode then "  |  BUILD MODE" else ""
		)
	end
end

function refreshPalette()
	if not _paletteFrame then
		return
	end

	-- Clear existing
	for _, child in ipairs(_paletteFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Get mining inventory
	task.spawn(function()
		local PlotService = Knit.GetService("PlotService")
		-- We just need the player's MiningInventory — read from a simple call
		-- For now, get the available materials from what's in their inventory
		local EggCraftingService = Knit.GetService("EggCraftingService")
		-- Actually, let's just iterate PLACEABLE_BLOCKS and show ones with count > 0
		-- We'll get counts from the recipe check which returns mining inventory

		local materials = {} :: { { id: string, name: string, color: { number } } }
		for itemId, config in pairs(PlotConfig.PLACEABLE_BLOCKS) do
			table.insert(materials, { id = itemId, name = config.name, color = config.color })
		end
		table.sort(materials, function(a, b)
			return a.name < b.name
		end)

		local count = 0
		for _, mat in ipairs(materials) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.fromOffset(40, 40)
			btn.BackgroundColor3 = Color3.fromRGB(mat.color[1], mat.color[2], mat.color[3])
			btn.Text = ""
			btn.AutoButtonColor = true
			btn.Parent = _paletteFrame
			createCorner(btn, 4)

			-- Selection indicator
			if mat.id == _selectedMaterial then
				local sel = Instance.new("UIStroke")
				sel.Color = COLORS.buildMode
				sel.Thickness = 2
				sel.Parent = btn
			end

			-- Tooltip
			btn.MouseEnter:Connect(function()
				btn:SetAttribute("Tooltip", mat.name)
			end)

			btn.MouseButton1Click:Connect(function()
				_selectedMaterial = mat.id
				refreshPalette()
			end)

			count += 1
		end

		-- Resize palette to fit
		_paletteFrame.Size = UDim2.fromOffset(math.min(count, 15) * 44 + 12, 50)
	end)
end

function toggleBuildMode()
	_buildMode = not _buildMode

	if _buildMode then
		createGhostBlock()
		_paletteFrame.Visible = true
		refreshPalette()
		-- Select first material if none selected
		if not _selectedMaterial then
			for itemId in pairs(PlotConfig.PLACEABLE_BLOCKS) do
				_selectedMaterial = itemId
				break
			end
			refreshPalette()
		end
	else
		destroyGhostBlock()
		_paletteFrame.Visible = false
	end

	updateHUD()
end

-- Input

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end

	-- B key: toggle build mode
	if input.KeyCode == Enum.KeyCode.B then
		if _plotOrigin then
			toggleBuildMode()
		end
		return
	end

	if not _buildMode or not _plotOrigin or not _selectedMaterial then
		return
	end

	-- Left click / tap: place or remove block (remove mode on mobile)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local mouse = Player:GetMouse()
		local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { _ghostBlock, Player.Character }

		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
		if not result then
			return
		end

		-- Check if we're in remove mode (mobile) or hit a plot block
		local removeBtn = _screenGui and _screenGui:FindFirstChild("RemoveToggle")
		local isRemoveMode = removeBtn and removeBtn:GetAttribute("RemoveMode")

		if isRemoveMode and result.Instance and result.Instance.Name:match("^PlotBlock_") then
			-- Remove the hit block
			local key = result.Instance.Name:sub(11)
			local rlx, rly, rlz = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
			if rlx then
				task.spawn(function()
					local PlotService = Knit.GetService("PlotService")
					local res = PlotService:RemoveBlock(tonumber(rlx), tonumber(rly), tonumber(rlz)):await()
					if res and res.success then
						unrenderBlock(key)
						if _plotData then
							_plotData.blockCount = math.max(0, (_plotData.blockCount or 1) - 1)
						end
						updateHUD()
					end
				end)
			end
		else
			-- Place block
			local hitPos = result.Position + result.Normal * 0.1
			local lx, ly, lz = PlotConfig.worldToLocal(_plotOrigin, hitPos)

			if PlotConfig.isInBounds(lx, ly, lz) then
				task.spawn(function()
					local PlotService = Knit.GetService("PlotService")
					local res = PlotService:PlaceBlock(lx, ly, lz, _selectedMaterial):await()
					if res and res.success then
						renderBlock(res.key, res.materialId)
						if _plotData then
							_plotData.blockCount = (_plotData.blockCount or 0) + 1
						end
						updateHUD()
					end
				end)
			end
		end
		return
	end

	-- Right click: remove block (desktop)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		local mouse = Player:GetMouse()
		local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { _ghostBlock, Player.Character }

		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
		if not result or not result.Instance then
			return
		end

		-- Check if hit a plot block
		local hitPart = result.Instance
		if hitPart.Name:match("^PlotBlock_") then
			local key = hitPart.Name:sub(11) -- remove "PlotBlock_" prefix
			local lx, ly, lz = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
			if lx then
				task.spawn(function()
					local PlotService = Knit.GetService("PlotService")
					local res = PlotService:RemoveBlock(tonumber(lx), tonumber(ly), tonumber(lz)):await()
					if res and res.success then
						unrenderBlock(key)
						if _plotData then
							_plotData.blockCount = math.max(0, (_plotData.blockCount or 1) - 1)
						end
						updateHUD()
					end
				end)
			end
		end
		return
	end
end

-- Lifecycle

local PlotController = Knit.CreateController({ Name = "PlotController" })

function PlotController:KnitInit() end

function PlotController:KnitStart()
	-- Plot UI disabled
end

return PlotController
