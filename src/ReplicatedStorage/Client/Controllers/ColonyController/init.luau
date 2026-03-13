local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local Player = Players.LocalPlayer

-- Sounds
local _successSound = Instance.new("Sound")
_successSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
_successSound.Volume = 0.5
_successSound.Parent = SoundService

local _failSound = Instance.new("Sound")
_failSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
_failSound.Volume = 0.4
_failSound.Parent = SoundService

local ColonyController = Knit.CreateController({
	Name = "ColonyController",
})

-----------------------------------------------------------
-- Constants
-----------------------------------------------------------

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

local COLONY_RADIUS = 40
local BOUNDARY_SEGMENTS = 24

local DAY_DURATION = 30
local NIGHT_DURATION = 15

local ENERGY_TICK_INTERVAL = 2
local TURRET_FIRE_INTERVAL = 1.5
local ENEMY_ATTACK_INTERVAL = 1
local ENEMY_ATTACK_RANGE = 2
local ENEMY_SPAWN_INTERVAL = 2
local ENEMY_SPEED = 6
local PROJECTILE_SPEED = 0.3

local TURRET_KEYWORDS = { "turret", "tower", "cannon", "gun", "defense" }

-----------------------------------------------------------
-- State
-----------------------------------------------------------

local _active = false
local _gui = nil

-- Colony area
local _colonyCenter = Vector3.zero
local _boundaryParts = {}
local _colonyFolder = nil

-- Game state
local _energy = 0
local _nightCount = 0
local _phase = "day"
local _phaseTimer = 0
local _gameOver = false

-- Structures: { { model, name, hp, maxHp, energyRate, hpBar, billboardGui } }
local _buildings = {}
-- Turrets: { { model, name, hp, maxHp, damage, range, lastFired, hpBar, billboardGui } }
local _turrets = {}
-- Enemies: { { model, hp, maxHp, damage, lastAttack, hpBar, billboardGui } }
local _enemies = {}

-- UI elements
local _energyLabel = nil
local _phaseLabel = nil
local _timerBar = nil
local _timerFill = nil
local _nightLabel = nil
local _statusLabel = nil
local _promptInput = nil
local _buildButton = nil
local _buildingListFrame = nil
local _gameOverFrame = nil

-- Connections
local _heartbeatConn = nil
local _energyTickTimer = 0

-----------------------------------------------------------
-- Utility
-----------------------------------------------------------

local function setStatus(text: string, color: Color3?)
	if not _statusLabel then
		return
	end
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim
	task.delay(5, function()
		if _statusLabel and _statusLabel.Text == text then
			_statusLabel.Text = ""
		end
	end)
end

local function getModelBounds(model: Model): (Vector3, number)
	local parts = model:GetDescendants()
	local totalVolume = 0
	local maxDim = 0
	local partCount = 0
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			partCount += 1
			local s = part.Size
			totalVolume += s.X * s.Y * s.Z
			maxDim = math.max(maxDim, s.X, s.Y, s.Z)
		end
	end
	return Vector3.new(partCount, totalVolume, maxDim), partCount
end

local function isTurretPrompt(prompt: string): boolean
	local lower = prompt:lower()
	for _, keyword in ipairs(TURRET_KEYWORDS) do
		if lower:find(keyword) then
			return true
		end
	end
	return false
end

local function getNextPlacementPos(): Vector3
	-- Spread buildings in a spiral-ish pattern from center
	local count = #_buildings + #_turrets
	local angle = count * 2.39996 -- golden angle in radians
	local radius = math.min(8 + count * 4, COLONY_RADIUS - 5)
	return _colonyCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-----------------------------------------------------------
-- HP Bar
-----------------------------------------------------------

local function createHPBar(model: Model, _maxHp: number): (BillboardGui, Frame)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HPBar"
	billboard.Size = UDim2.fromOffset(60, 8)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	billboard.Parent = model

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLORS.success
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 2)
	fillCorner.Parent = fill

	return billboard, fill
end

local function updateHPBar(entry: { hp: number, maxHp: number, hpBar: Frame? })
	if not entry.hpBar then
		return
	end
	local pct = math.clamp(entry.hp / entry.maxHp, 0, 1)
	entry.hpBar.Size = UDim2.fromScale(pct, 1)
	if pct > 0.5 then
		entry.hpBar.BackgroundColor3 = COLORS.success
	elseif pct > 0.25 then
		entry.hpBar.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
	else
		entry.hpBar.BackgroundColor3 = COLORS.danger
	end
end

-----------------------------------------------------------
-- Colony Boundary
-----------------------------------------------------------

local function createBoundary()
	for i = 1, BOUNDARY_SEGMENTS do
		local angle = (i / BOUNDARY_SEGMENTS) * math.pi * 2
		local pos = _colonyCenter + Vector3.new(math.cos(angle) * COLONY_RADIUS, 0, math.sin(angle) * COLONY_RADIUS)

		local part = Instance.new("Part")
		part.Name = "Boundary_" .. i
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(3, 0.2, 1)
		part.Position = pos
		part.Orientation = Vector3.new(0, math.deg(-angle) + 90, 0)
		part.Material = Enum.Material.Neon
		part.Color = COLORS.accent
		part.Transparency = 0.5
		part.Parent = _colonyFolder

		table.insert(_boundaryParts, part)
	end
end

local function destroyBoundary()
	for _, part in ipairs(_boundaryParts) do
		part:Destroy()
	end
	table.clear(_boundaryParts)
end

-----------------------------------------------------------
-- Building list UI
-----------------------------------------------------------

local function refreshBuildingList()
	if not _buildingListFrame then
		return
	end

	-- Clear existing children except layout
	for _, child in ipairs(_buildingListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local function addEntry(name: string, hp: number, maxHp: number, entryType: string, layoutOrder: number)
		local entry = Instance.new("Frame")
		entry.Name = name
		entry.Size = UDim2.new(1, -4, 0, 28)
		entry.BackgroundColor3 = COLORS.bgLight
		entry.BackgroundTransparency = 0.3
		entry.BorderSizePixel = 0
		entry.LayoutOrder = layoutOrder
		entry.Parent = _buildingListFrame

		local ec = Instance.new("UICorner")
		ec.CornerRadius = UDim.new(0, 4)
		ec.Parent = entry

		local typeIcon = Instance.new("TextLabel")
		typeIcon.Size = UDim2.new(0, 20, 1, 0)
		typeIcon.Position = UDim2.new(0, 4, 0, 0)
		typeIcon.BackgroundTransparency = 1
		typeIcon.Text = if entryType == "turret" then "T" else "B"
		typeIcon.TextColor3 = if entryType == "turret" then COLORS.danger else COLORS.accent
		typeIcon.Font = Enum.Font.GothamBold
		typeIcon.TextSize = 12
		typeIcon.Parent = entry

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -70, 1, 0)
		nameLabel.Position = UDim2.new(0, 26, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = name
		nameLabel.TextColor3 = COLORS.text
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextSize = 11
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = entry

		local hpLabel = Instance.new("TextLabel")
		hpLabel.Size = UDim2.new(0, 40, 1, 0)
		hpLabel.Position = UDim2.new(1, -44, 0, 0)
		hpLabel.BackgroundTransparency = 1
		hpLabel.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
		hpLabel.TextColor3 = COLORS.textDim
		hpLabel.Font = Enum.Font.Gotham
		hpLabel.TextSize = 10
		hpLabel.TextXAlignment = Enum.TextXAlignment.Right
		hpLabel.Parent = entry
	end

	for i, b in ipairs(_buildings) do
		addEntry(b.name, b.hp, b.maxHp, "building", i)
	end
	for i, t in ipairs(_turrets) do
		addEntry(t.name, t.hp, t.maxHp, "turret", #_buildings + i)
	end
end

-----------------------------------------------------------
-- Enemies
-----------------------------------------------------------

local function createEnemy(hp: number)
	if not _active or not _colonyFolder then
		return
	end

	-- Spawn from random point on boundary
	local angle = math.random() * math.pi * 2
	local spawnPos = _colonyCenter + Vector3.new(math.cos(angle) * COLONY_RADIUS, 0.5, math.sin(angle) * COLONY_RADIUS)

	local model = Instance.new("Model")
	model.Name = "Enemy"

	-- Simple 3-4 part red block creature
	local partCount = math.random(3, 4)
	for i = 1, partCount do
		local part = Instance.new("Part")
		part.Name = "EnemyPart_" .. i
		part.Anchored = true
		part.CanCollide = false
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(1 + math.random() * 1.5, 1 + math.random() * 1.5, 1 + math.random() * 1.5)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(180 + math.random(0, 40), 20 + math.random(0, 30), 20 + math.random(0, 30))
		part.Position = spawnPos + Vector3.new((i - 2) * 0.8, (i - 1) * 0.7, 0)
		part.Parent = model

		if i == 1 then
			model.PrimaryPart = part
		end
	end

	model.Parent = _colonyFolder

	local billboard, fill = createHPBar(model, hp)

	local enemy = {
		model = model,
		hp = hp,
		maxHp = hp,
		damage = 5 + _nightCount * 2,
		lastAttack = 0,
		hpBar = fill,
		billboardGui = billboard,
	}

	table.insert(_enemies, enemy)
end

local function destroyEnemy(index: number)
	local enemy = _enemies[index]
	if enemy and enemy.model then
		enemy.model:Destroy()
	end
	table.remove(_enemies, index)
end

-----------------------------------------------------------
-- Turret shooting
-----------------------------------------------------------

local function fireProjectile(from: Vector3, target: Model)
	if not _colonyFolder then
		return
	end

	local targetPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	if not targetPart then
		return
	end

	local projectile = Instance.new("Part")
	projectile.Name = "Projectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(0.6, 0.6, 0.6)
	projectile.Material = Enum.Material.Neon
	projectile.Color = COLORS.accent
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Position = from + Vector3.new(0, 2, 0)
	projectile.Parent = _colonyFolder

	local startPos = projectile.Position
	local endPos = targetPart.Position
	local startTick = tick()

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not projectile.Parent then
			conn:Disconnect()
			return
		end

		local elapsed = tick() - startTick
		local alpha = math.clamp(elapsed / PROJECTILE_SPEED, 0, 1)
		projectile.Position = startPos:Lerp(endPos, alpha)

		if alpha >= 1 then
			conn:Disconnect()
			projectile:Destroy()
		end
	end)
end

-----------------------------------------------------------
-- Game loop
-----------------------------------------------------------

local function findNearestBuilding(pos: Vector3)
	local best = nil
	local bestDist = math.huge

	-- Check buildings first, then turrets
	for _, b in ipairs(_buildings) do
		if b.model.Parent and b.hp > 0 then
			local bp = b.model.PrimaryPart
			if bp then
				local d = (bp.Position - pos).Magnitude
				if d < bestDist then
					bestDist = d
					best = b
				end
			end
		end
	end
	for _, t in ipairs(_turrets) do
		if t.model.Parent and t.hp > 0 then
			local tp = t.model.PrimaryPart
			if tp then
				local d = (tp.Position - pos).Magnitude
				if d < bestDist then
					bestDist = d
					best = t
				end
			end
		end
	end

	if best then
		return best, bestDist
	end
	return nil, 0
end

local function findNearestEnemy(pos: Vector3, range: number): (number, number)
	local bestIdx = 0
	local bestDist = math.huge
	for i, e in ipairs(_enemies) do
		if e.model.Parent and e.hp > 0 then
			local ep = e.model.PrimaryPart
			if ep then
				local d = (ep.Position - pos).Magnitude
				if d < bestDist and d <= range then
					bestDist = d
					bestIdx = i
				end
			end
		end
	end
	return bestIdx, bestDist
end

local function checkGameOver()
	if _gameOver then
		return
	end

	local hasStructures = false
	for _, b in ipairs(_buildings) do
		if b.hp > 0 then
			hasStructures = true
			break
		end
	end
	if not hasStructures then
		for _, t in ipairs(_turrets) do
			if t.hp > 0 then
				hasStructures = true
				break
			end
		end
	end

	if not hasStructures and (#_buildings > 0 or #_turrets > 0) then
		_gameOver = true
		if _gameOverFrame then
			_gameOverFrame.Visible = true
		end
		setStatus("Colony destroyed! All structures lost.", COLORS.error)
	end
end

local function gameLoopTick(dt: number)
	if not _active or _gameOver then
		return
	end

	local now = tick()

	-- Phase timer
	_phaseTimer -= dt
	if _phaseTimer <= 0 then
		if _phase == "day" then
			-- Transition to night
			_phase = "night"
			_nightCount += 1
			_phaseTimer = NIGHT_DURATION
			setStatus("Night " .. _nightCount .. " begins! Enemies approaching!", COLORS.danger)
			_failSound:Play()
		else
			-- Transition to day
			_phase = "day"
			_phaseTimer = DAY_DURATION
			setStatus("Day breaks. Build and prepare!", COLORS.success)
			_successSound:Play()
		end
	end

	-- Update UI
	if _phaseLabel then
		_phaseLabel.Text = if _phase == "day" then "DAY" else "NIGHT"
		_phaseLabel.TextColor3 = if _phase == "day" then COLORS.success else COLORS.danger
	end
	if _nightLabel then
		_nightLabel.Text = "Night: " .. _nightCount
	end
	if _energyLabel then
		_energyLabel.Text = "Energy: " .. math.floor(_energy)
	end
	if _timerFill then
		local maxTime = if _phase == "day" then DAY_DURATION else NIGHT_DURATION
		local pct = math.clamp(_phaseTimer / maxTime, 0, 1)
		_timerFill.Size = UDim2.fromScale(pct, 1)
		_timerFill.BackgroundColor3 = if _phase == "day" then COLORS.success else COLORS.danger
	end

	-- Energy ticking (buildings generate energy)
	_energyTickTimer -= dt
	if _energyTickTimer <= 0 then
		_energyTickTimer = ENERGY_TICK_INTERVAL
		for _, b in ipairs(_buildings) do
			if b.hp > 0 and b.model.Parent then
				_energy += b.energyRate
			end
		end
	end

	-- Enemy spawning during night
	if _phase == "night" then
		local totalEnemies = 3 + _nightCount * 2
		local currentEnemyCount = #_enemies
		local enemyHp = 30 + _nightCount * 15

		-- Spawn enemies gradually
		if currentEnemyCount < totalEnemies then
			-- Use attribute on folder to track last spawn time
			local lastSpawn = if _colonyFolder then _colonyFolder:GetAttribute("LastEnemySpawn") or 0 else 0
			if now - lastSpawn >= ENEMY_SPAWN_INTERVAL then
				if _colonyFolder then
					_colonyFolder:SetAttribute("LastEnemySpawn", now)
				end
				createEnemy(enemyHp)
			end
		end
	end

	-- Enemy movement and attacking
	for i = #_enemies, 1, -1 do
		local enemy = _enemies[i]
		if not enemy.model.Parent or enemy.hp <= 0 then
			destroyEnemy(i)
			continue
		end

		local enemyPart = enemy.model.PrimaryPart
		if not enemyPart then
			continue
		end

		local target, dist = findNearestBuilding(enemyPart.Position)
		if not target then
			continue
		end

		if dist <= ENEMY_ATTACK_RANGE then
			-- Attack
			if now - enemy.lastAttack >= ENEMY_ATTACK_INTERVAL then
				enemy.lastAttack = now
				target.hp -= enemy.damage
				updateHPBar(target)

				if target.hp <= 0 then
					target.model:Destroy()
					refreshBuildingList()
					checkGameOver()
				end
			end
		else
			-- Move toward target
			local targetPart = target.model.PrimaryPart
			if targetPart then
				local dir = (targetPart.Position - enemyPart.Position)
				dir = Vector3.new(dir.X, 0, dir.Z) -- Keep on ground plane
				if dir.Magnitude > 0.1 then
					local move = dir.Unit * math.min(ENEMY_SPEED * dt, dir.Magnitude)
					enemy.model:PivotTo(enemy.model:GetPivot() + move)
				end
			end
		end
	end

	-- Turret firing
	for _, turret in ipairs(_turrets) do
		if turret.hp <= 0 or not turret.model.Parent then
			continue
		end

		if now - turret.lastFired >= TURRET_FIRE_INTERVAL then
			local turretPart = turret.model.PrimaryPart
			if turretPart then
				local enemyIdx, _ = findNearestEnemy(turretPart.Position, turret.range)
				if enemyIdx > 0 then
					turret.lastFired = now
					local enemy = _enemies[enemyIdx]

					fireProjectile(turretPart.Position, enemy.model)

					-- Apply damage after projectile travel time
					task.delay(PROJECTILE_SPEED, function()
						if not _active then
							return
						end
						if enemy.hp > 0 then
							enemy.hp -= turret.damage
							updateHPBar(enemy)
							if enemy.hp <= 0 then
								-- Find and remove enemy
								for j, e in ipairs(_enemies) do
									if e == enemy then
										destroyEnemy(j)
										break
									end
								end
							end
						end
					end)
				end
			end
		end
	end
end

-----------------------------------------------------------
-- Build action
-----------------------------------------------------------

local function submitBuild()
	if not _active or not _promptInput or _gameOver then
		return
	end

	local prompt = _promptInput.Text
	if prompt == "" then
		setStatus("Enter a building description!", COLORS.error)
		return
	end

	_promptInput.Text = ""
	if _buildButton then
		_buildButton.BackgroundColor3 = COLORS.disabled
	end
	setStatus("Building: " .. prompt .. "...", COLORS.accent)

	local isTurret = isTurretPrompt(prompt)
	local category = "building"

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, category, "origami"):await()

		if not _active then
			return
		end

		if _buildButton then
			_buildButton.BackgroundColor3 = COLORS.accent
		end

		if not ok or not result or not result.success then
			local errMsg = if result and result.error then result.error else "Build failed"
			setStatus("Error: " .. tostring(errMsg), COLORS.error)
			_failSound:Play()
			return
		end

		local modelData = result.model
		local model = OrigamiBuilder.BuildModel(modelData)
		model.Parent = _colonyFolder

		-- Place in colony
		local placePos = getNextPlacementPos()

		-- Raycast down for ground placement
		local rayOrigin = placePos + Vector3.new(0, 50, 0)
		local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0))
		if rayResult then
			placePos = Vector3.new(placePos.X, rayResult.Position.Y, placePos.Z)
		end

		model:PivotTo(CFrame.new(placePos))

		-- Calculate stats
		local bounds, partCount = getModelBounds(model)
		local totalVolume = bounds.Y
		local maxDim = bounds.Z

		if isTurret then
			local billboard, fill = createHPBar(model, partCount * 10)
			local turret = {
				model = model,
				name = modelData.name or prompt,
				hp = partCount * 10,
				maxHp = partCount * 10,
				damage = totalVolume,
				range = maxDim * 3,
				lastFired = 0,
				hpBar = fill,
				billboardGui = billboard,
			}
			table.insert(_turrets, turret)
			setStatus(
				"Turret deployed: "
					.. turret.name
					.. " (DMG: "
					.. math.floor(turret.damage)
					.. ", RNG: "
					.. math.floor(turret.range)
					.. ")",
				COLORS.success
			)
		else
			local billboard, fill = createHPBar(model, partCount * 10)
			local building = {
				model = model,
				name = modelData.name or prompt,
				hp = partCount * 10,
				maxHp = partCount * 10,
				energyRate = totalVolume / 10,
				hpBar = fill,
				billboardGui = billboard,
			}
			table.insert(_buildings, building)
			setStatus(
				"Built: " .. building.name .. " (+" .. string.format("%.1f", building.energyRate) .. " energy/tick)",
				COLORS.success
			)
		end

		_successSound:Play()
		refreshBuildingList()
	end)
end

-----------------------------------------------------------
-- UI Creation
-----------------------------------------------------------

local function createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ColonyUI"
	gui.DisplayOrder = 15
	gui.ResetOnSpawn = false

	-- Top-left info panel
	local infoPanel = Instance.new("Frame")
	infoPanel.Name = "InfoPanel"
	infoPanel.Size = UDim2.new(0, 200, 0, 120)
	infoPanel.Position = UDim2.new(0, 12, 0, 12)
	infoPanel.BackgroundColor3 = COLORS.bg
	infoPanel.BackgroundTransparency = 0.15
	infoPanel.BorderSizePixel = 0
	infoPanel.Parent = gui

	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(0, 8)
	infoCorner.Parent = infoPanel

	local infoPadding = Instance.new("UIPadding")
	infoPadding.PaddingLeft = UDim.new(0, 10)
	infoPadding.PaddingTop = UDim.new(0, 8)
	infoPadding.PaddingRight = UDim.new(0, 10)
	infoPadding.Parent = infoPanel

	local infoLayout = Instance.new("UIListLayout")
	infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
	infoLayout.Padding = UDim.new(0, 4)
	infoLayout.Parent = infoPanel

	-- Energy
	_energyLabel = Instance.new("TextLabel")
	_energyLabel.Name = "Energy"
	_energyLabel.Size = UDim2.new(1, 0, 0, 22)
	_energyLabel.BackgroundTransparency = 1
	_energyLabel.Text = "Energy: 0"
	_energyLabel.TextColor3 = COLORS.accent
	_energyLabel.Font = Enum.Font.GothamBold
	_energyLabel.TextSize = 16
	_energyLabel.TextXAlignment = Enum.TextXAlignment.Left
	_energyLabel.LayoutOrder = 1
	_energyLabel.Parent = infoPanel

	-- Night counter
	_nightLabel = Instance.new("TextLabel")
	_nightLabel.Name = "NightCount"
	_nightLabel.Size = UDim2.new(1, 0, 0, 18)
	_nightLabel.BackgroundTransparency = 1
	_nightLabel.Text = "Night: 0"
	_nightLabel.TextColor3 = COLORS.textDim
	_nightLabel.Font = Enum.Font.Gotham
	_nightLabel.TextSize = 13
	_nightLabel.TextXAlignment = Enum.TextXAlignment.Left
	_nightLabel.LayoutOrder = 2
	_nightLabel.Parent = infoPanel

	-- Phase label
	_phaseLabel = Instance.new("TextLabel")
	_phaseLabel.Name = "Phase"
	_phaseLabel.Size = UDim2.new(1, 0, 0, 22)
	_phaseLabel.BackgroundTransparency = 1
	_phaseLabel.Text = "DAY"
	_phaseLabel.TextColor3 = COLORS.success
	_phaseLabel.Font = Enum.Font.GothamBold
	_phaseLabel.TextSize = 18
	_phaseLabel.TextXAlignment = Enum.TextXAlignment.Left
	_phaseLabel.LayoutOrder = 3
	_phaseLabel.Parent = infoPanel

	-- Timer bar
	_timerBar = Instance.new("Frame")
	_timerBar.Name = "TimerBar"
	_timerBar.Size = UDim2.new(1, 0, 0, 8)
	_timerBar.BackgroundColor3 = COLORS.bgLight
	_timerBar.BorderSizePixel = 0
	_timerBar.LayoutOrder = 4
	_timerBar.Parent = infoPanel

	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 4)
	timerCorner.Parent = _timerBar

	_timerFill = Instance.new("Frame")
	_timerFill.Name = "Fill"
	_timerFill.Size = UDim2.fromScale(1, 1)
	_timerFill.BackgroundColor3 = COLORS.success
	_timerFill.BorderSizePixel = 0
	_timerFill.Parent = _timerBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = _timerFill

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "Status"
	_statusLabel.Size = UDim2.new(1, 0, 0, 16)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.Font = Enum.Font.Gotham
	_statusLabel.TextSize = 11
	_statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	_statusLabel.TextWrapped = true
	_statusLabel.LayoutOrder = 5
	_statusLabel.Parent = infoPanel

	-- Bottom-center build panel
	local buildPanel = Instance.new("Frame")
	buildPanel.Name = "BuildPanel"
	buildPanel.Size = UDim2.new(0, 360, 0, 48)
	buildPanel.Position = UDim2.new(0.5, -180, 1, -60)
	buildPanel.BackgroundColor3 = COLORS.bg
	buildPanel.BackgroundTransparency = 0.15
	buildPanel.BorderSizePixel = 0
	buildPanel.Parent = gui

	local buildCorner = Instance.new("UICorner")
	buildCorner.CornerRadius = UDim.new(0, 8)
	buildCorner.Parent = buildPanel

	-- Prompt input
	_promptInput = Instance.new("TextBox")
	_promptInput.Name = "PromptInput"
	_promptInput.Size = UDim2.new(1, -80, 0, 32)
	_promptInput.Position = UDim2.new(0, 8, 0.5, -16)
	_promptInput.BackgroundColor3 = COLORS.bgLight
	_promptInput.BorderSizePixel = 0
	_promptInput.PlaceholderText = "Describe a building or turret..."
	_promptInput.PlaceholderColor3 = COLORS.textDim
	_promptInput.Text = ""
	_promptInput.TextColor3 = COLORS.text
	_promptInput.Font = Enum.Font.Gotham
	_promptInput.TextSize = 13
	_promptInput.ClearTextOnFocus = false
	_promptInput.Parent = buildPanel

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 6)
	inputCorner.Parent = _promptInput

	local inputPadding = Instance.new("UIPadding")
	inputPadding.PaddingLeft = UDim.new(0, 8)
	inputPadding.PaddingRight = UDim.new(0, 8)
	inputPadding.Parent = _promptInput

	-- Build button
	_buildButton = Instance.new("TextButton")
	_buildButton.Name = "BuildButton"
	_buildButton.Size = UDim2.new(0, 60, 0, 32)
	_buildButton.Position = UDim2.new(1, -68, 0.5, -16)
	_buildButton.BackgroundColor3 = COLORS.accent
	_buildButton.BorderSizePixel = 0
	_buildButton.Text = "Build"
	_buildButton.TextColor3 = COLORS.bg
	_buildButton.Font = Enum.Font.GothamBold
	_buildButton.TextSize = 14
	_buildButton.Parent = buildPanel

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = _buildButton

	_buildButton.Activated:Connect(submitBuild)
	_promptInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitBuild()
		end
	end)

	-- Right side building list panel
	local listPanel = Instance.new("Frame")
	listPanel.Name = "BuildingList"
	listPanel.Size = UDim2.new(0, 180, 0, 300)
	listPanel.Position = UDim2.new(1, -192, 0, 12)
	listPanel.BackgroundColor3 = COLORS.bg
	listPanel.BackgroundTransparency = 0.15
	listPanel.BorderSizePixel = 0
	listPanel.Parent = gui

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = listPanel

	local listTitle = Instance.new("TextLabel")
	listTitle.Name = "Title"
	listTitle.Size = UDim2.new(1, 0, 0, 28)
	listTitle.BackgroundTransparency = 1
	listTitle.Text = "  Structures"
	listTitle.TextColor3 = COLORS.text
	listTitle.Font = Enum.Font.GothamBold
	listTitle.TextSize = 13
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.Parent = listPanel

	_buildingListFrame = Instance.new("ScrollingFrame")
	_buildingListFrame.Name = "List"
	_buildingListFrame.Size = UDim2.new(1, -8, 1, -36)
	_buildingListFrame.Position = UDim2.new(0, 4, 0, 32)
	_buildingListFrame.BackgroundTransparency = 1
	_buildingListFrame.BorderSizePixel = 0
	_buildingListFrame.ScrollBarThickness = 4
	_buildingListFrame.ScrollBarImageColor3 = COLORS.textDim
	_buildingListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	_buildingListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	_buildingListFrame.Parent = listPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 3)
	listLayout.Parent = _buildingListFrame

	-- Game over overlay
	_gameOverFrame = Instance.new("Frame")
	_gameOverFrame.Name = "GameOver"
	_gameOverFrame.Size = UDim2.fromScale(1, 1)
	_gameOverFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	_gameOverFrame.BackgroundTransparency = 0.4
	_gameOverFrame.BorderSizePixel = 0
	_gameOverFrame.Visible = false
	_gameOverFrame.ZIndex = 10
	_gameOverFrame.Parent = gui

	local gameOverLabel = Instance.new("TextLabel")
	gameOverLabel.Size = UDim2.new(0, 400, 0, 80)
	gameOverLabel.Position = UDim2.new(0.5, -200, 0.4, -40)
	gameOverLabel.BackgroundTransparency = 1
	gameOverLabel.Text = "COLONY DESTROYED"
	gameOverLabel.TextColor3 = COLORS.danger
	gameOverLabel.Font = Enum.Font.GothamBold
	gameOverLabel.TextSize = 36
	gameOverLabel.ZIndex = 11
	gameOverLabel.Parent = _gameOverFrame

	local survivalLabel = Instance.new("TextLabel")
	survivalLabel.Name = "Survival"
	survivalLabel.Size = UDim2.new(0, 400, 0, 30)
	survivalLabel.Position = UDim2.new(0.5, -200, 0.4, 40)
	survivalLabel.BackgroundTransparency = 1
	survivalLabel.TextColor3 = COLORS.text
	survivalLabel.Font = Enum.Font.Gotham
	survivalLabel.TextSize = 16
	survivalLabel.ZIndex = 11
	survivalLabel.Parent = _gameOverFrame

	-- We'll update survival text dynamically
	task.spawn(function()
		while _gameOverFrame and not _gameOverFrame.Visible do
			task.wait(0.5)
			if not _active then
				return
			end
		end
		if survivalLabel then
			survivalLabel.Text = "Survived "
				.. _nightCount
				.. " night"
				.. (if _nightCount == 1 then "" else "s")
				.. " | Energy collected: "
				.. math.floor(_energy)
		end
	end)

	gui.Parent = Player.PlayerGui
	return gui
end

-----------------------------------------------------------
-- Activate / Cleanup
-----------------------------------------------------------

function ColonyController:Activate()
	if _active then
		return
	end
	_active = true

	-- Reset state
	_energy = 0
	_nightCount = 0
	_phase = "day"
	_phaseTimer = DAY_DURATION
	_gameOver = false
	_energyTickTimer = ENERGY_TICK_INTERVAL
	table.clear(_buildings)
	table.clear(_turrets)
	table.clear(_enemies)

	-- Colony center in front of player
	local character = Player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local forward = rootPart.CFrame.LookVector
			_colonyCenter = rootPart.Position + forward * 30
			_colonyCenter = Vector3.new(_colonyCenter.X, rootPart.Position.Y, _colonyCenter.Z)
		else
			_colonyCenter = Vector3.new(0, 5, 0)
		end
	else
		_colonyCenter = Vector3.new(0, 5, 0)
	end

	-- Create folder for all colony objects
	_colonyFolder = Instance.new("Folder")
	_colonyFolder.Name = "ColonyObjects"
	_colonyFolder.Parent = workspace

	createBoundary()
	_gui = createUI()

	-- Start game loop
	_heartbeatConn = RunService.Heartbeat:Connect(gameLoopTick)

	setStatus("Colony established! Build structures to generate energy.", COLORS.success)
end

function ColonyController:Cleanup()
	_active = false

	-- Disconnect heartbeat
	if _heartbeatConn then
		_heartbeatConn:Disconnect()
		_heartbeatConn = nil
	end

	-- Destroy all colony objects
	if _colonyFolder then
		_colonyFolder:Destroy()
		_colonyFolder = nil
	end

	destroyBoundary()

	-- Clear tables
	table.clear(_buildings)
	table.clear(_turrets)
	table.clear(_enemies)

	-- Destroy UI
	if _gui then
		_gui:Destroy()
		_gui = nil
	end

	-- Nil out UI refs
	_energyLabel = nil
	_phaseLabel = nil
	_timerBar = nil
	_timerFill = nil
	_nightLabel = nil
	_statusLabel = nil
	_promptInput = nil
	_buildButton = nil
	_buildingListFrame = nil
	_gameOverFrame = nil
end

-----------------------------------------------------------
-- Knit lifecycle
-----------------------------------------------------------

function ColonyController:KnitInit() end

function ColonyController:KnitStart()
	GameMode.Changed:Connect(function(newMode, oldMode)
		if newMode == "colony" then
			self:Activate()
		elseif oldMode == "colony" then
			self:Cleanup()
		end
	end)
end

return ColonyController
