--[[
	CoopTowerDefenseController — client-side co-op tower defense.
	Activates on "tower_defense" game mode. Players join a lobby, ready up,
	and defend a shared base from waves of enemies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local VFXUtil = require(ReplicatedStorage.Shared.VFXUtil)

local Player = Players.LocalPlayer

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
local TEXT_SCALE = if IS_CONSOLE then 1.5 elseif IS_MOBILE then 1.2 else 1.0
local BUTTON_HEIGHT = if IS_MOBILE then 54 else 44
local BOTTOM_SAFE = if IS_MOBILE then 40 else 20

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
	gold = Color3.fromRGB(255, 210, 60),
	health = Color3.fromRGB(255, 80, 80),
}

-- State
local _gui = nil
local _active = false
local _inLobby = false
local _connections = {}
local _allInstances = {}
local _creepModels = {} -- creepId → visual part
local _towerModels = {} -- towerId → visual

-- World folders
local _pathFolder = nil
local _towerFolder = nil
local _creepFolder = nil
local _projectileFolder = nil
local _baseFolder = nil

-- UI refs
local _lobbyFrame = nil
local _gameFrame = nil
local _goldLabel = nil
local _baseHPLabel = nil
local _waveLabel = nil
local _statusLabel = nil
local _inputBox = nil
local _buildButton = nil
local _readyButton = nil
local _playerListFrame = nil
local _gameOverLabel = nil

-- Cached state
local _currentGold = 0
local _currentBaseHP = 0
local _currentWave = 0
local _basePart = nil

-- Helpers

local function makeCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
end

local function setStatus(text: string, color: Color3?)
	if _statusLabel then
		_statusLabel.Text = text
		_statusLabel.TextColor3 = color or COLORS.textDim
	end
end

local function updateHUD()
	if _goldLabel then
		_goldLabel.Text = "Gold: " .. tostring(math.floor(_currentGold))
	end
	if _baseHPLabel then
		_baseHPLabel.Text = "Base HP: " .. tostring(math.floor(_currentBaseHP))
		_baseHPLabel.TextColor3 = if _currentBaseHP <= 50 then COLORS.danger else COLORS.health
	end
	if _waveLabel then
		_waveLabel.Text = "Wave " .. tostring(_currentWave)
	end
	if _buildButton then
		local canBuild = _currentGold >= 50
		_buildButton.AutoButtonColor = canBuild
		_buildButton.BackgroundColor3 = if canBuild then COLORS.accent else COLORS.disabled
	end
end

-- World Visualization

local function createBase(center: Vector3)
	local base = Instance.new("Part")
	base.Name = "CoopBase"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(1, 10, 10)
	base.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.CanCollide = false
	base.Material = Enum.Material.Neon
	base.Color = COLORS.accent
	base.Transparency = 0.3
	base.Parent = _baseFolder
	table.insert(_allInstances, base)
	_basePart = base
end

local function createPathVisuals(paths: { { { x: number, y: number, z: number } } })
	for _, path in ipairs(paths) do
		for i = 1, #path - 1 do
			local a = Vector3.new(path[i].x, path[i].y, path[i].z)
			local b = Vector3.new(path[i + 1].x, path[i + 1].y, path[i + 1].z)
			local mid = (a + b) / 2
			local dist = (b - a).Magnitude

			local line = Instance.new("Part")
			line.Size = Vector3.new(dist, 0.1, 1)
			line.CFrame = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
			line.Anchored = true
			line.CanCollide = false
			line.Material = Enum.Material.Neon
			line.Color = COLORS.accentDim
			line.Transparency = 0.7
			line.Parent = _pathFolder
			table.insert(_allInstances, line)
		end

		-- Waypoint markers
		for _, wp in ipairs(path) do
			local marker = Instance.new("Part")
			marker.Shape = Enum.PartType.Cylinder
			marker.Size = Vector3.new(0.2, 3, 3)
			marker.CFrame = CFrame.new(wp.x, wp.y, wp.z) * CFrame.Angles(0, 0, math.rad(90))
			marker.Anchored = true
			marker.CanCollide = false
			marker.Material = Enum.Material.Neon
			marker.Color = COLORS.accentDim
			marker.Transparency = 0.6
			marker.Parent = _pathFolder
			table.insert(_allInstances, marker)
		end
	end
end

-- UI

local function createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CoopTD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Player.PlayerGui
	_gui = gui

	-- === LOBBY FRAME ===
	local lobbyFrame = Instance.new("Frame")
	lobbyFrame.Name = "LobbyFrame"
	lobbyFrame.Size = if IS_MOBILE then UDim2.new(0.85, 0, 0, 300) else UDim2.fromOffset(300, 280)
	lobbyFrame.Position = if IS_MOBILE then UDim2.new(0.075, 0, 0.5, -150) else UDim2.new(0.5, -150, 0.5, -140)
	lobbyFrame.AnchorPoint = Vector2.new(0, 0)
	lobbyFrame.BackgroundColor3 = COLORS.bg
	lobbyFrame.BackgroundTransparency = 0.1
	lobbyFrame.BorderSizePixel = 0
	lobbyFrame.Parent = gui
	makeCorner(lobbyFrame)
	_lobbyFrame = lobbyFrame

	local lobbyPad = Instance.new("UIPadding")
	lobbyPad.PaddingLeft = UDim.new(0, 12)
	lobbyPad.PaddingRight = UDim.new(0, 12)
	lobbyPad.PaddingTop = UDim.new(0, 12)
	lobbyPad.Parent = lobbyFrame

	local lobbyTitle = Instance.new("TextLabel")
	lobbyTitle.Size = UDim2.new(1, 0, 0, 30)
	lobbyTitle.BackgroundTransparency = 1
	lobbyTitle.Text = "Tower Defense — Co-op"
	lobbyTitle.TextColor3 = COLORS.accent
	lobbyTitle.TextSize = math.floor(20 * TEXT_SCALE)
	lobbyTitle.Font = Enum.Font.GothamBold
	lobbyTitle.Parent = lobbyFrame

	local playerListFrame = Instance.new("Frame")
	playerListFrame.Name = "PlayerList"
	playerListFrame.Size = UDim2.new(1, 0, 0, 140)
	playerListFrame.Position = UDim2.fromOffset(0, 40)
	playerListFrame.BackgroundTransparency = 1
	playerListFrame.Parent = lobbyFrame
	_playerListFrame = playerListFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = playerListFrame

	local readyBtn = Instance.new("TextButton")
	readyBtn.Name = "ReadyButton"
	readyBtn.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	readyBtn.Position = UDim2.fromOffset(0, 190)
	readyBtn.Text = "Ready!"
	readyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	readyBtn.BackgroundColor3 = COLORS.success
	readyBtn.BorderSizePixel = 0
	readyBtn.TextSize = math.floor(18 * TEXT_SCALE)
	readyBtn.Font = Enum.Font.GothamBold
	readyBtn.AutoButtonColor = true
	readyBtn.Parent = lobbyFrame
	makeCorner(readyBtn, 6)
	_readyButton = readyBtn

	local lobbyStatus = Instance.new("TextLabel")
	lobbyStatus.Name = "LobbyStatus"
	lobbyStatus.Size = UDim2.new(1, 0, 0, 20)
	lobbyStatus.Position = UDim2.fromOffset(0, 235)
	lobbyStatus.BackgroundTransparency = 1
	lobbyStatus.Text = "Waiting for players..."
	lobbyStatus.TextColor3 = COLORS.textDim
	lobbyStatus.TextSize = 13
	lobbyStatus.Font = Enum.Font.Gotham
	lobbyStatus.Parent = lobbyFrame

	-- === GAME FRAME ===
	local gameFrame = Instance.new("Frame")
	gameFrame.Name = "GameFrame"
	gameFrame.Size = UDim2.fromScale(1, 1)
	gameFrame.BackgroundTransparency = 1
	gameFrame.Visible = false
	gameFrame.Parent = gui
	_gameFrame = gameFrame

	-- Base HP (center top)
	local baseHPLabel = Instance.new("TextLabel")
	baseHPLabel.Name = "BaseHP"
	baseHPLabel.Size = UDim2.fromOffset(200, 36)
	baseHPLabel.Position = UDim2.new(0.5, -100, 0, 16)
	baseHPLabel.BackgroundColor3 = COLORS.bg
	baseHPLabel.BackgroundTransparency = 0.3
	baseHPLabel.Text = "Base HP: 200"
	baseHPLabel.TextColor3 = COLORS.health
	baseHPLabel.TextSize = math.floor(22 * TEXT_SCALE)
	baseHPLabel.Font = Enum.Font.GothamBold
	baseHPLabel.Parent = gameFrame
	makeCorner(baseHPLabel)
	_baseHPLabel = baseHPLabel

	-- Gold (top left)
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "Gold"
	goldLabel.Size = UDim2.fromOffset(160, 30)
	goldLabel.Position = UDim2.fromOffset(16, 16)
	goldLabel.BackgroundColor3 = COLORS.bg
	goldLabel.BackgroundTransparency = 0.3
	goldLabel.Text = "Gold: 100"
	goldLabel.TextColor3 = COLORS.gold
	goldLabel.TextSize = math.floor(20 * TEXT_SCALE)
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.Parent = gameFrame
	makeCorner(goldLabel)
	_goldLabel = goldLabel

	-- Wave (top right)
	local waveLabel = Instance.new("TextLabel")
	waveLabel.Name = "Wave"
	waveLabel.Size = UDim2.fromOffset(120, 30)
	waveLabel.Position = UDim2.new(1, -136, 0, 16)
	waveLabel.BackgroundColor3 = COLORS.bg
	waveLabel.BackgroundTransparency = 0.3
	waveLabel.Text = "Wave 0"
	waveLabel.TextColor3 = COLORS.accent
	waveLabel.TextSize = math.floor(20 * TEXT_SCALE)
	waveLabel.Font = Enum.Font.GothamBold
	waveLabel.Parent = gameFrame
	makeCorner(waveLabel)
	_waveLabel = waveLabel

	-- Bottom bar: input + build
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = if IS_MOBILE then UDim2.new(0.92, 0, 0, BUTTON_HEIGHT + 14) else UDim2.new(0, 500, 0, 50)
	bottomBar.Position = if IS_MOBILE
		then UDim2.new(0.04, 0, 1, -(BUTTON_HEIGHT + 14 + BOTTOM_SAFE))
		else UDim2.new(0.5, -250, 1, -70)
	bottomBar.BackgroundColor3 = COLORS.bg
	bottomBar.BackgroundTransparency = 0.2
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = gameFrame
	makeCorner(bottomBar)

	local barPad = Instance.new("UIPadding")
	barPad.PaddingLeft = UDim.new(0, 8)
	barPad.PaddingRight = UDim.new(0, 8)
	barPad.PaddingTop = UDim.new(0, 7)
	barPad.Parent = bottomBar

	local inputBox = Instance.new("TextBox")
	inputBox.Size = UDim2.new(1, -130, 1, -6)
	inputBox.PlaceholderText = "Describe your tower... (50g)"
	inputBox.Text = ""
	inputBox.TextColor3 = COLORS.text
	inputBox.PlaceholderColor3 = COLORS.textDim
	inputBox.BackgroundColor3 = COLORS.bgLight
	inputBox.BorderSizePixel = 0
	inputBox.TextSize = math.floor(15 * TEXT_SCALE)
	inputBox.Font = Enum.Font.Gotham
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = bottomBar
	makeCorner(inputBox, 6)
	_inputBox = inputBox

	local buildBtn = Instance.new("TextButton")
	buildBtn.Name = "BuildButton"
	buildBtn.Size = UDim2.new(0, 118, 1, -6)
	buildBtn.Position = UDim2.new(1, -118, 0, 0)
	buildBtn.Text = "Build (50g)"
	buildBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buildBtn.BackgroundColor3 = COLORS.accent
	buildBtn.BorderSizePixel = 0
	buildBtn.TextSize = math.floor(15 * TEXT_SCALE)
	buildBtn.Font = Enum.Font.GothamBold
	buildBtn.AutoButtonColor = true
	buildBtn.Parent = bottomBar
	makeCorner(buildBtn, 6)
	_buildButton = buildBtn

	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.fromOffset(400, 24)
	statusLabel.Position = UDim2.new(0.5, -200, 1, -90)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.TextSize = 14
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = gameFrame
	_statusLabel = statusLabel

	-- Game over overlay
	local gameOverLabel = Instance.new("TextLabel")
	gameOverLabel.Name = "GameOver"
	gameOverLabel.Size = UDim2.fromScale(1, 1)
	gameOverLabel.BackgroundColor3 = COLORS.bg
	gameOverLabel.BackgroundTransparency = 0.4
	gameOverLabel.Text = "GAME OVER"
	gameOverLabel.TextColor3 = COLORS.danger
	gameOverLabel.TextSize = if IS_MOBILE then 48 else 64
	gameOverLabel.Font = Enum.Font.GothamBlack
	gameOverLabel.Visible = false
	gameOverLabel.ZIndex = 10
	gameOverLabel.Parent = gameFrame
	_gameOverLabel = gameOverLabel

	-- Wire build button
	buildBtn.Activated:Connect(function()
		submitBuildPrompt()
	end)
	inputBox.FocusLost:Connect(function(enter)
		if enter then
			submitBuildPrompt()
		end
	end)
end

-- Tower Building

function submitBuildPrompt()
	if not _inputBox then
		return
	end
	local prompt = _inputBox.Text
	if prompt == "" then
		setStatus("Type a tower description!", COLORS.error)
		return
	end
	if _currentGold < 50 then
		setStatus("Not enough gold!", COLORS.error)
		return
	end

	_inputBox.Text = ""
	setStatus("Building tower...", COLORS.accent)

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "building", "origami", nil, "tower"):await()

		if ok and result and result.success and result.model then
			-- Place tower near the player
			local character = Player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				setStatus("Can't place tower — no character", COLORS.error)
				return
			end

			local placePos = rootPart.Position + rootPart.CFrame.LookVector * 10
			placePos = Vector3.new(placePos.X, 0.5, placePos.Z)

			local CoopTDService = Knit.GetService("CoopTDService")
			local placeOk, placeResult =
				CoopTDService:PlaceTower(result.model, { x = placePos.X, y = placePos.Y, z = placePos.Z }):await()

			if placeOk and placeResult and placeResult.success then
				setStatus("Tower placed!", COLORS.success)
			else
				setStatus(placeResult and placeResult.error or "Failed to place", COLORS.error)
			end
		else
			setStatus("Failed to generate tower", COLORS.error)
		end
	end)
end

-- Lobby UI Updates

local function updatePlayerList(players: { any })
	if not _playerListFrame then
		return
	end

	-- Clear existing
	for _, child in ipairs(_playerListFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	for i, p in ipairs(players) do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 28)
		label.BackgroundColor3 = COLORS.bgLight
		label.BackgroundTransparency = 0.5
		label.Text = p.name .. (if p.ready then " ✓" else "")
		label.TextColor3 = if p.ready then COLORS.success else COLORS.text
		label.TextSize = math.floor(15 * TEXT_SCALE)
		label.Font = Enum.Font.GothamBold
		label.LayoutOrder = i
		label.Parent = _playerListFrame
		makeCorner(label, 4)
	end
end

-- Lifecycle

local CoopTowerDefenseController = Knit.CreateController({ Name = "CoopTowerDefenseController" })

function CoopTowerDefenseController:Activate()
	if _active then
		return
	end
	_active = true

	-- Create world folders
	_pathFolder = Instance.new("Folder")
	_pathFolder.Name = "CoopTD_Path"
	_pathFolder.Parent = workspace
	table.insert(_allInstances, _pathFolder)
	_towerFolder = Instance.new("Folder")
	_towerFolder.Name = "CoopTD_Towers"
	_towerFolder.Parent = workspace
	table.insert(_allInstances, _towerFolder)
	_creepFolder = Instance.new("Folder")
	_creepFolder.Name = "CoopTD_Creep"
	_creepFolder.Parent = workspace
	table.insert(_allInstances, _creepFolder)
	_projectileFolder = Instance.new("Folder")
	_projectileFolder.Name = "CoopTD_Projectiles"
	_projectileFolder.Parent = workspace
	table.insert(_allInstances, _projectileFolder)
	_baseFolder = Instance.new("Folder")
	_baseFolder.Name = "CoopTD_Bases"
	_baseFolder.Parent = workspace
	table.insert(_allInstances, _baseFolder)

	if _gui then
		_gui.Enabled = true
	end
	if _lobbyFrame then
		_lobbyFrame.Visible = true
	end
	if _gameFrame then
		_gameFrame.Visible = false
	end

	-- Auto-join lobby
	task.spawn(function()
		local CoopTDService = Knit.GetService("CoopTDService")
		local ok, result = CoopTDService:JoinLobby():await()
		if ok and result and result.success then
			_inLobby = true
			_currentGold = result.gold or 250
			_currentBaseHP = result.baseHP or 200
			updateHUD()
		end
	end)
end

function CoopTowerDefenseController:Cleanup()
	_active = false

	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	_connections = {}

	for _, inst in ipairs(_allInstances) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	_allInstances = {}
	_creepModels = {}
	_towerModels = {}

	_pathFolder = nil
	_towerFolder = nil
	_creepFolder = nil
	_projectileFolder = nil
	_baseFolder = nil
	_basePart = nil

	if _gui then
		_gui.Enabled = false
	end

	if _inLobby then
		task.spawn(function()
			local CoopTDService = Knit.GetService("CoopTDService")
			CoopTDService:LeaveLobby()
		end)
		_inLobby = false
	end
end

function CoopTowerDefenseController:KnitInit() end

function CoopTowerDefenseController:KnitStart()
	createUI()

	local CoopTDService = Knit.GetService("CoopTDService")

	-- Ready button
	if _readyButton then
		_readyButton.Activated:Connect(function()
			task.spawn(function()
				CoopTDService:ReadyUp()
				if _readyButton then
					_readyButton.Text = "Waiting..."
					_readyButton.BackgroundColor3 = COLORS.disabled
					_readyButton.AutoButtonColor = false
				end
			end)
		end)
	end

	-- Lobby updates
	CoopTDService.LobbyUpdated:Connect(function(state)
		if state.players then
			updatePlayerList(state.players)
		end
		if state.phase == "starting" then
			-- Transition to game view
			if _lobbyFrame then
				_lobbyFrame.Visible = false
			end
			if _gameFrame then
				_gameFrame.Visible = true
			end

			if state.center then
				createBase(Vector3.new(state.center.x, state.center.y, state.center.z))
			end
			if state.paths then
				createPathVisuals(state.paths)
			end
			if state.baseHP then
				_currentBaseHP = state.baseHP
			end
		end
		updateHUD()
	end)

	-- Prep phase
	CoopTDService.PrepPhaseStarted:Connect(function(data)
		local duration = data.duration or 15
		setStatus("Prep phase — Wave " .. (data.nextWave or "?") .. " in " .. duration .. "s", COLORS.accent)

		task.spawn(function()
			local remaining = duration
			while remaining > 0 and _active do
				task.wait(1)
				remaining -= 1
				setStatus(
					"Wave " .. (data.nextWave or "?") .. " in " .. remaining .. "s — Build towers!",
					COLORS.accent
				)
			end
		end)
	end)

	-- Wave started
	CoopTDService.WaveStarted:Connect(function(data)
		_currentWave = data.wave or 0
		setStatus("Wave " .. _currentWave .. " — Defend!", COLORS.error)
		updateHUD()
	end)

	-- Creep spawned
	CoopTDService.CreepSpawned:Connect(function(data)
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		local size = 2 + (_currentWave * 0.1)
		part.Size = Vector3.new(size, size, size)
		part.Position = Vector3.new(data.position.x, data.position.y + size / 2, data.position.z)
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(200, 60, 60)
		part.Parent = _creepFolder
		table.insert(_allInstances, part)
		_creepModels[data.id] = part
	end)

	-- Creep died
	CoopTDService.CreepDied:Connect(function(data)
		local part = _creepModels[data.id]
		if part and part.Parent then
			VFXUtil.pop(part, COLORS.error)
		end
		_creepModels[data.id] = nil
	end)

	-- Creep reached base
	CoopTDService.CreepReachedBase:Connect(function(data)
		local part = _creepModels[data.id]
		if part and part.Parent then
			part:Destroy()
		end
		_creepModels[data.id] = nil

		-- Flash base
		if _basePart then
			_basePart.Color = COLORS.danger
			task.delay(0.3, function()
				if _basePart then
					_basePart.Color = COLORS.accent
				end
			end)
		end
	end)

	-- Base HP
	CoopTDService.BaseHPChanged:Connect(function(hp)
		_currentBaseHP = hp
		updateHUD()
	end)

	-- Gold changed
	CoopTDService.GoldChanged:Connect(function(gold)
		_currentGold = gold
		updateHUD()
	end)

	-- Tower placed (from any player)
	CoopTDService.TowerPlaced:Connect(function(data)
		local pos = Vector3.new(data.position.x, data.position.y, data.position.z)

		if data.modelData then
			local model = OrigamiBuilder.BuildModel(data.modelData)
			if model then
				model:PivotTo(CFrame.new(pos + Vector3.new(0, 2, 0)))
				model.Parent = _towerFolder
				table.insert(_allInstances, model)
				_towerModels[data.id] = model
				OrigamiBuilder.ApplyAnimation(model, "idle_bob")

				-- Add owner label
				local billboard = Instance.new("BillboardGui")
				billboard.Size = UDim2.new(0, 120, 0, 20)
				billboard.StudsOffset = Vector3.new(0, 4, 0)
				billboard.AlwaysOnTop = true
				billboard.MaxDistance = 40
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Text = data.ownerName or "Tower"
				label.TextColor3 = COLORS.text
				label.TextStrokeTransparency = 0.5
				label.TextSize = 11
				label.Font = Enum.Font.Gotham
				label.Parent = billboard
				local target = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
				if target then
					billboard.Adornee = target
					billboard.Parent = target
				end
				return
			end
		end

		-- Fallback: simple block tower
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(3, 5, 3)
		part.Position = pos + Vector3.new(0, 2.5, 0)
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = COLORS.accent
		part.Parent = _towerFolder
		table.insert(_allInstances, part)
		_towerModels[data.id] = part
	end)

	-- Tower attacked (projectile visual)
	CoopTDService.TowerAttacked:Connect(function(data)
		local from = Vector3.new(data.position.x, data.position.y + 3, data.position.z)
		local to = Vector3.new(data.targetPos.x, data.targetPos.y, data.targetPos.z)

		local proj = Instance.new("Part")
		proj.Shape = Enum.PartType.Ball
		proj.Size = if data.attackType == "splash" then Vector3.new(1.5, 1.5, 1.5) else Vector3.new(0.8, 0.8, 0.8)
		proj.Position = from
		proj.Anchored = true
		proj.CanCollide = false
		proj.Material = Enum.Material.Neon
		proj.Color = COLORS.accent
		proj.Parent = _projectileFolder

		task.spawn(function()
			local elapsed = 0
			while elapsed < 0.3 and proj.Parent do
				elapsed += task.wait()
				proj.Position = from:Lerp(to, math.min(elapsed / 0.3, 1))
			end
			if proj.Parent then
				proj:Destroy()
			end
		end)
	end)

	-- Wave cleared
	CoopTDService.WaveCleared:Connect(function(data)
		setStatus("Wave " .. (data.wave or "?") .. " cleared! +" .. (data.goldBonus or 0) .. "g", COLORS.success)

		-- VFX: sparkle at base + rising gold text
		if _basePart then
			VFXUtil.sparkle(_basePart.Position, COLORS.success, 30, 2)
			VFXUtil.risingText(
				_basePart.Position + Vector3.new(0, 3, 0),
				"+" .. (data.goldBonus or 0) .. "g",
				COLORS.gold
			)
		end

		-- Trigger celebration emote
		task.spawn(function()
			local EmoteController = Knit.GetController("EmoteController")
			if EmoteController and EmoteController.PlayPreset then
				EmoteController:PlayPreset("celebration")
			end
		end)
	end)

	-- Game over
	CoopTDService.GameOver:Connect(function(data)
		if _gameOverLabel then
			_gameOverLabel.Text = "GAME OVER — Wave " .. (data.wave or "?")
			_gameOverLabel.Visible = true
		end
		setStatus("Base destroyed! Made it to wave " .. (data.wave or "?"), COLORS.danger)
	end)

	-- Mode switching
	GameMode.Changed:Connect(function(newMode: string, oldMode: string)
		if newMode == "tower_defense" then
			self:Activate()
		elseif oldMode == "tower_defense" then
			self:Cleanup()
		end
	end)
end

return CoopTowerDefenseController
