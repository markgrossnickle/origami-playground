--!strict
--[[
	TowerDefenseController
	Tower defense game mode: build origami towers via LLM prompts, defend against waves of enemies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local Player = Players.LocalPlayer

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

-- Game constants
local MAX_LIVES = 20
local WAYPOINT_COUNT = 6
local PATH_LENGTH = 100
local PATH_Y = 0.5
local TOWER_OFFSET = 10
local ENEMY_SPAWN_INTERVAL = 3
local ATTACK_INTERVAL = 1
local PROJECTILE_SPEED = 0.3
local BASE_ENEMY_HP = 50
local HP_PER_WAVE = 20
local ENEMIES_BASE = 2

-- State
local _gui: ScreenGui? = nil
local _active = false
local _lives = MAX_LIVES
local _wave = 0
local _waveRunning = false
local _gameOver = false

local _towers: { { model: Model, damage: number, range: number, position: Vector3 } } = {}
local _enemies: { { part: BasePart, hp: number, maxHp: number, waypointIndex: number, speed: number, alive: boolean } } =
	{}
local _projectiles: { BasePart } = {}
local _waypoints: { Vector3 } = {}
local _waypointParts: { BasePart } = {}
local _allInstances: { Instance } = {}
local _connections: { RBXScriptConnection } = {}

-- UI references
local _waveLabel: TextLabel? = nil
local _livesLabel: TextLabel? = nil
local _statusLabel: TextLabel? = nil
local _inputBox: TextBox? = nil
local _buildButton: TextButton? = nil
local _startWaveButton: TextButton? = nil
local _gameOverLabel: TextLabel? = nil

local _pathFolder: Folder? = nil
local _towerFolder: Folder? = nil
local _enemyFolder: Folder? = nil
local _projectileFolder: Folder? = nil

-- Helpers

local function getPathOrigin(): Vector3
	local char = Player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local root = char.HumanoidRootPart :: BasePart
		local pos = root.Position
		return Vector3.new(pos.X - PATH_LENGTH / 2, PATH_Y, pos.Z + 20)
	end
	return Vector3.new(-PATH_LENGTH / 2, PATH_Y, 20)
end

local function generateWaypoints()
	local origin = getPathOrigin()
	_waypoints = {}
	for i = 1, WAYPOINT_COUNT do
		local t = (i - 1) / (WAYPOINT_COUNT - 1)
		local x = origin.X + t * PATH_LENGTH
		local z = origin.Z + math.sin(t * math.pi) * 15
		table.insert(_waypoints, Vector3.new(x, origin.Y, z))
	end
end

local function createWaypointMarkers()
	for _, wp in ipairs(_waypoints) do
		local marker = Instance.new("Part")
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.2, 4, 4)
		marker.CFrame = CFrame.new(wp) * CFrame.Angles(0, 0, math.rad(90))
		marker.Anchored = true
		marker.CanCollide = false
		marker.Material = Enum.Material.Neon
		marker.Color = COLORS.accentDim
		marker.Transparency = 0.6
		marker.Parent = _pathFolder
		table.insert(_waypointParts, marker)
		table.insert(_allInstances, marker)
	end

	-- Draw path lines between waypoints
	for i = 1, #_waypoints - 1 do
		local a = _waypoints[i]
		local b = _waypoints[i + 1]
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
end

local function setStatus(text: string, color: Color3?)
	if _statusLabel then
		_statusLabel.Text = text
		_statusLabel.TextColor3 = color or COLORS.text
	end
end

local function updateHUD()
	if _waveLabel then
		_waveLabel.Text = "Wave: " .. tostring(_wave)
	end
	if _livesLabel then
		_livesLabel.Text = "Lives: " .. tostring(_lives)
		_livesLabel.TextColor3 = if _lives <= 5 then COLORS.danger else COLORS.text
	end
end

local function findNearestEnemy(
	pos: Vector3,
	range: number
): {
	part: BasePart,
	hp: number,
	maxHp: number,
	waypointIndex: number,
	speed: number,
	alive: boolean,
}?
	local best = nil
	local bestDist = range + 1
	for _, enemy in ipairs(_enemies) do
		if enemy.alive and enemy.part and enemy.part.Parent then
			local dist = (enemy.part.Position - pos).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = enemy
			end
		end
	end
	return best
end

local function fireProjectile(from: Vector3, target: BasePart, damage: number)
	local proj = Instance.new("Part")
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(1, 1, 1)
	proj.Position = from + Vector3.new(0, 3, 0)
	proj.Anchored = true
	proj.CanCollide = false
	proj.Material = Enum.Material.Neon
	proj.Color = COLORS.accent
	proj.Parent = _projectileFolder
	table.insert(_projectiles, proj)
	table.insert(_allInstances, proj)

	task.spawn(function()
		local startPos = proj.Position
		local elapsed = 0
		while elapsed < PROJECTILE_SPEED and proj.Parent and target and target.Parent do
			elapsed += task.wait()
			local t = math.min(elapsed / PROJECTILE_SPEED, 1)
			proj.Position = startPos:Lerp(target.Position, t)
		end

		-- Deal damage to the enemy
		for _, enemy in ipairs(_enemies) do
			if enemy.part == target and enemy.alive then
				enemy.hp -= damage
				if enemy.hp <= 0 then
					enemy.alive = false
					if enemy.part and enemy.part.Parent then
						enemy.part:Destroy()
					end
				end
				break
			end
		end

		if proj.Parent then
			proj:Destroy()
		end
	end)
end

local function enemyReachedEnd()
	_lives -= 1
	updateHUD()
	if _lives <= 0 then
		_gameOver = true
		_waveRunning = false
		if _gameOverLabel then
			_gameOverLabel.Visible = true
		end
		if _buildButton then
			_buildButton.AutoButtonColor = false
			_buildButton.BackgroundColor3 = COLORS.disabled
		end
		if _startWaveButton then
			_startWaveButton.AutoButtonColor = false
			_startWaveButton.BackgroundColor3 = COLORS.disabled
		end
		setStatus("Game Over!", COLORS.danger)
	end
end

local function spawnEnemy(hp: number, speed: number)
	if #_waypoints < 2 then
		return
	end

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(3, 3, 3)
	part.Position = _waypoints[1] + Vector3.new(0, 1.5, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic

	-- Color: red hue, darker with higher HP
	local brightness = math.clamp(1 - (hp - BASE_ENEMY_HP) / 300, 0.3, 1)
	part.Color = Color3.fromRGB(math.floor(220 * brightness), math.floor(40 * brightness), math.floor(40 * brightness))

	part.Parent = _enemyFolder
	table.insert(_allInstances, part)

	local enemy = {
		part = part,
		hp = hp,
		maxHp = hp,
		waypointIndex = 1,
		speed = speed,
		alive = true,
	}
	table.insert(_enemies, enemy)

	-- Move enemy along waypoints
	task.spawn(function()
		while enemy.alive and not _gameOver and enemy.waypointIndex < #_waypoints do
			local targetIdx = enemy.waypointIndex + 1
			local target = _waypoints[targetIdx] + Vector3.new(0, 1.5, 0)
			local start = enemy.part.Position

			local dist = (target - start).Magnitude
			local duration = dist / enemy.speed
			local elapsed = 0

			while elapsed < duration and enemy.alive and enemy.part and enemy.part.Parent do
				local dt = task.wait()
				elapsed += dt
				local t = math.min(elapsed / duration, 1)
				enemy.part.Position = start:Lerp(target, t)
			end

			if enemy.alive then
				enemy.waypointIndex = targetIdx
			end
		end

		-- Reached end
		if enemy.alive and enemy.waypointIndex >= #_waypoints then
			enemy.alive = false
			if enemy.part and enemy.part.Parent then
				enemy.part:Destroy()
			end
			enemyReachedEnd()
		end
	end)
end

local function startWave()
	if _gameOver or _waveRunning then
		return
	end

	_waveRunning = true
	_wave += 1
	updateHUD()
	setStatus("Wave " .. tostring(_wave) .. " incoming!", COLORS.accent)

	if _startWaveButton then
		_startWaveButton.AutoButtonColor = false
		_startWaveButton.BackgroundColor3 = COLORS.disabled
	end

	local enemyCount = _wave + ENEMIES_BASE
	local hp = BASE_ENEMY_HP + (_wave * HP_PER_WAVE)
	local speed = 6 + math.min(_wave * 0.5, 6)

	task.spawn(function()
		for i = 1, enemyCount do
			if _gameOver or not _active then
				break
			end
			spawnEnemy(hp, speed)
			if i < enemyCount then
				task.wait(ENEMY_SPAWN_INTERVAL)
			end
		end

		-- Wait for all enemies to die or reach end
		while _active and not _gameOver do
			local anyAlive = false
			for _, enemy in ipairs(_enemies) do
				if enemy.alive then
					anyAlive = true
					break
				end
			end
			if not anyAlive then
				break
			end
			task.wait(0.5)
		end

		_waveRunning = false
		if not _gameOver and _active then
			setStatus("Wave " .. tostring(_wave) .. " cleared! Build towers or start next wave.", COLORS.success)
			if _startWaveButton then
				_startWaveButton.AutoButtonColor = true
				_startWaveButton.BackgroundColor3 = COLORS.accent
			end
		end
	end)
end

local function placeTower(modelData: { [string]: any })
	local model = OrigamiBuilder.BuildModel(modelData)
	if not model then
		setStatus("Failed to build tower model", COLORS.error)
		return
	end

	-- Find placement position: near a waypoint, offset from path
	local wpIndex = math.random(1, math.max(1, #_waypoints - 1))
	local wp = _waypoints[wpIndex]
	local nextWp = _waypoints[math.min(wpIndex + 1, #_waypoints)]
	local dir = (nextWp - wp).Unit
	local perpendicular = Vector3.new(-dir.Z, 0, dir.X)
	local side = if math.random() > 0.5 then 1 else -1
	local offset = perpendicular * (TOWER_OFFSET * side)
	local placePos = wp + offset + Vector3.new(0, 2, 0)

	model:PivotTo(CFrame.new(placePos))
	model.Parent = _towerFolder
	table.insert(_allInstances, model)

	-- Derive stats from bounding box
	local _, size = model:GetBoundingBox()
	local volume = size.X * size.Y * size.Z
	local maxDim = math.max(size.X, size.Y, size.Z)

	local tower = {
		model = model,
		damage = math.max(5, math.floor(volume / 2)),
		range = math.max(15, maxDim * 2),
		position = placePos,
	}
	table.insert(_towers, tower)

	OrigamiBuilder.ApplyAnimation(model, "idle_bob")

	setStatus(string.format("Tower placed! DMG: %d, Range: %d", tower.damage, math.floor(tower.range)), COLORS.success)
end

local function submitPrompt()
	if _gameOver then
		return
	end
	if not _inputBox then
		return
	end
	local prompt = _inputBox.Text
	if prompt == "" then
		setStatus("Enter a prompt to build a tower!", COLORS.error)
		return
	end

	_inputBox.Text = ""
	setStatus("Building tower...", COLORS.accent)

	if _buildButton then
		_buildButton.AutoButtonColor = false
		_buildButton.BackgroundColor3 = COLORS.disabled
	end

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "building", "origami"):await()

		if _buildButton then
			_buildButton.AutoButtonColor = true
			_buildButton.BackgroundColor3 = COLORS.accent
		end

		if ok and result and result.success and result.model then
			placeTower(result.model)
		else
			local errMsg = "Failed to generate tower"
			if result and type(result) == "table" and result.error then
				errMsg = "Error: " .. tostring(result.error)
			elseif type(result) == "string" then
				errMsg = "Error: " .. result
			end
			setStatus(errMsg, COLORS.error)
		end
	end)
end

-- Tower attack loop
local function startAttackLoop()
	local conn = RunService.Heartbeat:Connect(function()
		if not _active or _gameOver then
			return
		end

		-- Throttle to ~1 attack per second per tower using os.clock
		-- We store last attack time on the tower table entry
		local now = os.clock()
		for _, tower in ipairs(_towers) do
			local lastAttack = (tower :: any)._lastAttack or 0
			if now - lastAttack >= ATTACK_INTERVAL then
				local enemy = findNearestEnemy(tower.position, tower.range)
				if enemy then
					(tower :: any)._lastAttack = now
					fireProjectile(tower.position, enemy.part, tower.damage)
				end
			end
		end
	end)
	table.insert(_connections, conn)
end

-- UI Creation

local function makeCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
end

local function createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TowerDefense"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Player.PlayerGui
	_gui = gui

	-- Top-left panel: Wave + Lives
	local infoPanel = Instance.new("Frame")
	infoPanel.Name = "InfoPanel"
	infoPanel.Size = UDim2.fromOffset(200, 100)
	infoPanel.Position = UDim2.fromOffset(16, 16)
	infoPanel.BackgroundColor3 = COLORS.bg
	infoPanel.BackgroundTransparency = 0.2
	infoPanel.BorderSizePixel = 0
	infoPanel.Parent = gui
	makeCorner(infoPanel)

	local infoPadding = Instance.new("UIPadding")
	infoPadding.PaddingLeft = UDim.new(0, 12)
	infoPadding.PaddingTop = UDim.new(0, 12)
	infoPadding.Parent = infoPanel

	local waveLabel = Instance.new("TextLabel")
	waveLabel.Name = "WaveLabel"
	waveLabel.Size = UDim2.new(1, 0, 0, 30)
	waveLabel.BackgroundTransparency = 1
	waveLabel.Text = "Wave: 0"
	waveLabel.TextColor3 = COLORS.text
	waveLabel.TextSize = 22
	waveLabel.Font = Enum.Font.GothamBold
	waveLabel.TextXAlignment = Enum.TextXAlignment.Left
	waveLabel.Parent = infoPanel
	_waveLabel = waveLabel

	local livesLabel = Instance.new("TextLabel")
	livesLabel.Name = "LivesLabel"
	livesLabel.Size = UDim2.new(1, 0, 0, 30)
	livesLabel.Position = UDim2.fromOffset(0, 34)
	livesLabel.BackgroundTransparency = 1
	livesLabel.Text = "Lives: " .. tostring(MAX_LIVES)
	livesLabel.TextColor3 = COLORS.text
	livesLabel.TextSize = 22
	livesLabel.Font = Enum.Font.GothamBold
	livesLabel.TextXAlignment = Enum.TextXAlignment.Left
	livesLabel.Parent = infoPanel
	_livesLabel = livesLabel

	-- Bottom-center: Input bar
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(0, 500, 0, 100)
	bottomBar.Position = UDim2.new(0.5, -250, 1, -120)
	bottomBar.BackgroundColor3 = COLORS.bg
	bottomBar.BackgroundTransparency = 0.2
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = gui
	makeCorner(bottomBar)

	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0, 10)
	barPadding.PaddingRight = UDim.new(0, 10)
	barPadding.PaddingTop = UDim.new(0, 8)
	barPadding.PaddingBottom = UDim.new(0, 8)
	barPadding.Parent = bottomBar

	-- Input row
	local inputRow = Instance.new("Frame")
	inputRow.Name = "InputRow"
	inputRow.Size = UDim2.new(1, 0, 0, 36)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = bottomBar

	local inputBox = Instance.new("TextBox")
	inputBox.Name = "PromptInput"
	inputBox.Size = UDim2.new(1, -120, 1, 0)
	inputBox.PlaceholderText = "Describe your tower..."
	inputBox.Text = ""
	inputBox.TextColor3 = COLORS.text
	inputBox.PlaceholderColor3 = COLORS.textDim
	inputBox.BackgroundColor3 = COLORS.bgLight
	inputBox.BorderSizePixel = 0
	inputBox.TextSize = 16
	inputBox.Font = Enum.Font.Gotham
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = inputRow
	makeCorner(inputBox, 6)
	_inputBox = inputBox

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 8)
	inputPadding.Parent = inputBox

	local buildButton = Instance.new("TextButton")
	buildButton.Name = "BuildButton"
	buildButton.Size = UDim2.new(0, 108, 1, 0)
	buildButton.Position = UDim2.new(1, -108, 0, 0)
	buildButton.Text = "Build Tower"
	buildButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buildButton.BackgroundColor3 = COLORS.accent
	buildButton.BorderSizePixel = 0
	buildButton.TextSize = 16
	buildButton.Font = Enum.Font.GothamBold
	buildButton.AutoButtonColor = true
	buildButton.Parent = inputRow
	makeCorner(buildButton, 6)
	_buildButton = buildButton

	-- Button row: Start Wave + Status
	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "ButtonRow"
	buttonRow.Size = UDim2.new(1, 0, 0, 36)
	buttonRow.Position = UDim2.fromOffset(0, 44)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = bottomBar

	local startWaveBtn = Instance.new("TextButton")
	startWaveBtn.Name = "StartWaveButton"
	startWaveBtn.Size = UDim2.new(0, 120, 1, 0)
	startWaveBtn.Text = "Start Wave"
	startWaveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	startWaveBtn.BackgroundColor3 = COLORS.accent
	startWaveBtn.BorderSizePixel = 0
	startWaveBtn.TextSize = 16
	startWaveBtn.Font = Enum.Font.GothamBold
	startWaveBtn.AutoButtonColor = true
	startWaveBtn.Parent = buttonRow
	makeCorner(startWaveBtn, 6)
	_startWaveButton = startWaveBtn

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -130, 1, 0)
	statusLabel.Position = UDim2.fromOffset(130, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Build towers and start waves!"
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.TextSize = 14
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.Parent = buttonRow
	_statusLabel = statusLabel

	-- Game Over overlay
	local gameOverLabel = Instance.new("TextLabel")
	gameOverLabel.Name = "GameOverLabel"
	gameOverLabel.Size = UDim2.fromScale(1, 1)
	gameOverLabel.BackgroundColor3 = COLORS.bg
	gameOverLabel.BackgroundTransparency = 0.4
	gameOverLabel.Text = "GAME OVER"
	gameOverLabel.TextColor3 = COLORS.danger
	gameOverLabel.TextSize = 64
	gameOverLabel.Font = Enum.Font.GothamBlack
	gameOverLabel.Visible = false
	gameOverLabel.ZIndex = 10
	gameOverLabel.Parent = gui
	_gameOverLabel = gameOverLabel

	-- Wire events
	buildButton.MouseButton1Click:Connect(submitPrompt)
	inputBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitPrompt()
		end
	end)
	startWaveBtn.MouseButton1Click:Connect(startWave)
end

-- Activation / Cleanup

local function resetState()
	_lives = MAX_LIVES
	_wave = 0
	_waveRunning = false
	_gameOver = false
	_towers = {}
	_enemies = {}
	_projectiles = {}
	_waypoints = {}
	_waypointParts = {}
end

local TowerDefenseController = Knit.CreateController({ Name = "TowerDefenseController" })

function TowerDefenseController:Activate()
	if _active then
		return
	end
	_active = true

	resetState()

	-- Create workspace folders
	_pathFolder = Instance.new("Folder")
	_pathFolder.Name = "TD_Path"
	_pathFolder.Parent = workspace
	table.insert(_allInstances, _pathFolder)

	_towerFolder = Instance.new("Folder")
	_towerFolder.Name = "TD_Towers"
	_towerFolder.Parent = workspace
	table.insert(_allInstances, _towerFolder)

	_enemyFolder = Instance.new("Folder")
	_enemyFolder.Name = "TD_Enemies"
	_enemyFolder.Parent = workspace
	table.insert(_allInstances, _enemyFolder)

	_projectileFolder = Instance.new("Folder")
	_projectileFolder.Name = "TD_Projectiles"
	_projectileFolder.Parent = workspace
	table.insert(_allInstances, _projectileFolder)

	-- Set up path
	generateWaypoints()
	createWaypointMarkers()

	-- Show UI
	if _gui then
		_gui.Enabled = true
		if _gameOverLabel then
			_gameOverLabel.Visible = false
		end
	end
	updateHUD()
	setStatus("Build towers and start waves!", COLORS.textDim)

	-- Re-enable buttons
	if _buildButton then
		_buildButton.AutoButtonColor = true
		_buildButton.BackgroundColor3 = COLORS.accent
	end
	if _startWaveButton then
		_startWaveButton.AutoButtonColor = true
		_startWaveButton.BackgroundColor3 = COLORS.accent
	end

	-- Start tower attack loop
	startAttackLoop()
end

function TowerDefenseController:Cleanup()
	_active = false
	_waveRunning = false
	_gameOver = true -- stops any running enemy/wave coroutines

	-- Disconnect all connections
	for _, conn in ipairs(_connections) do
		conn:Disconnect()
	end
	_connections = {}

	-- Destroy all world instances
	for _, inst in ipairs(_allInstances) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	_allInstances = {}

	-- Clear folders
	_pathFolder = nil
	_towerFolder = nil
	_enemyFolder = nil
	_projectileFolder = nil

	-- Reset state
	_towers = {}
	_enemies = {}
	_projectiles = {}
	_waypoints = {}
	_waypointParts = {}

	-- Hide UI
	if _gui then
		_gui.Enabled = false
	end
end

function TowerDefenseController:KnitInit() end

function TowerDefenseController:KnitStart()
	createUI()

	GameMode.Changed:Connect(function(newMode: string, oldMode: string)
		if newMode == "tower_defense" then
			self:Activate()
		elseif oldMode == "tower_defense" then
			self:Cleanup()
		end
	end)
end

return TowerDefenseController
