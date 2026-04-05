--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

-- Types

type AttackType = "single" | "splash" | "rapid" | "piercing"
type TargetPriority = "nearest" | "weakest" | "strongest" | "fastest"
type DefenseType = "none" | "armor" | "dodge" | "regen"

type UnitData = {
	model: Model,
	name: string,
	hp: number,
	maxHp: number,
	damage: number,
	speed: number,
	side: "player" | "enemy",
	hpBar: BillboardGui?,
	hpFill: Frame?,
	alive: boolean,
	attackType: AttackType,
	targetPriority: TargetPriority,
	defenseType: DefenseType,
}

-- Constants

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

local MAX_PLAYER_UNITS = 5
local ARENA_OFFSET = Vector3.new(0, 0, -60) -- relative to player spawn
local ARENA_HALF_WIDTH = 30
local ARENA_DEPTH = 20
local FLOOR_HEIGHT = 0.2
local COMBAT_TICK = 0.5
local ATTACK_RANGE = 6
local SPLASH_RADIUS = 8
local UNIT_SPACING = 8

local ARMOR_REDUCTION = 0.3 -- 30% damage reduction
local DODGE_CHANCE = 0.25 -- 25% chance to avoid damage
local REGEN_PER_TICK = 3 -- HP healed per combat tick

local VALID_ATTACK_TYPES: { [string]: boolean } = { single = true, splash = true, rapid = true, piercing = true }
local VALID_TARGET_PRIORITIES: { [string]: boolean } =
	{ nearest = true, weakest = true, strongest = true, fastest = true }
local VALID_DEFENSE_TYPES: { [string]: boolean } = { none = true, armor = true, dodge = true, regen = true }

local RANDOM_ATTACK_TYPES: { AttackType } = { "single", "splash", "rapid", "piercing" }
local RANDOM_TARGET_PRIORITIES: { TargetPriority } = { "nearest", "weakest", "strongest", "fastest" }
local RANDOM_DEFENSE_TYPES: { DefenseType } = { "none", "armor", "dodge", "regen" }

local ENEMY_COLORS = {
	Color3.fromRGB(200, 60, 60),
	Color3.fromRGB(220, 120, 40),
	Color3.fromRGB(140, 50, 180),
	Color3.fromRGB(180, 40, 80),
	Color3.fromRGB(160, 80, 40),
}

-- State

local _gui: ScreenGui = nil :: any
local _active = false
local _fighting = false
local _round = 1
local _wins = 0
local _losses = 0

local _playerUnits: { UnitData } = {}
local _enemyUnits: { UnitData } = {}
local _arenaFolder: Folder? = nil
local _arenaCenter = Vector3.zero

-- UI references
local _roundLabel: TextLabel = nil :: any
local _recordLabel: TextLabel = nil :: any
local _statusLabel: TextLabel = nil :: any
local _promptBox: TextBox = nil :: any
local _addButton: TextButton = nil :: any
local _fightButton: TextButton = nil :: any
local _unitListFrame: Frame = nil :: any

-- Helpers

local function setStatus(text: string, color: Color3?)
	_statusLabel.Text = text
	_statusLabel.TextColor3 = color or COLORS.textDim
	local captured = text
	task.delay(5, function()
		if _statusLabel and _statusLabel.Text == captured then
			_statusLabel.Text = ""
		end
	end)
end

local function updateRoundDisplay()
	_roundLabel.Text = "Round " .. tostring(_round)
	_recordLabel.Text = _wins .. "W / " .. _losses .. "L"
end

local function updateFightButton()
	local canFight = #_playerUnits > 0 and #_enemyUnits > 0 and not _fighting
	_fightButton.Visible = canFight
end

local function updateInputState()
	local canAdd = #_playerUnits < MAX_PLAYER_UNITS and not _fighting
	_addButton.AutoButtonColor = canAdd
	_addButton.BackgroundColor3 = if canAdd then COLORS.accent else COLORS.disabled
	_promptBox.PlaceholderText = if _fighting
		then "Combat in progress..."
		elseif #_playerUnits >= MAX_PLAYER_UNITS then "Max units reached"
		else "Describe a creature..."
end

-- HP Bar

local function createHpBar(unit: UnitData)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HpBar"
	billboard.Size = UDim2.fromOffset(60, 10)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = unit.model

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if unit.side == "player" then COLORS.success else COLORS.danger
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	unit.hpBar = billboard
	unit.hpFill = fill
end

local function updateHpBar(unit: UnitData)
	if unit.hpFill then
		local pct = math.clamp(unit.hp / unit.maxHp, 0, 1)
		unit.hpFill.Size = UDim2.fromScale(pct, 1)
		if pct < 0.3 then
			unit.hpFill.BackgroundColor3 = COLORS.danger
		elseif pct < 0.6 then
			unit.hpFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
		end
	end
end

-- Unit List UI

local function refreshUnitList()
	for _, child in _unitListFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for i, unit in _playerUnits do
		local entry = Instance.new("Frame")
		entry.Name = "Unit_" .. tostring(i)
		entry.Size = UDim2.new(1, 0, 0, 28)
		entry.BackgroundColor3 = COLORS.bgLight
		entry.BorderSizePixel = 0
		entry.LayoutOrder = i
		entry.Parent = _unitListFrame

		local entryCorner = Instance.new("UICorner")
		entryCorner.CornerRadius = UDim.new(0, 4)
		entryCorner.Parent = entry

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Size = UDim2.new(0.6, -4, 1, 0)
		nameLabel.Position = UDim2.fromOffset(6, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = unit.name
		nameLabel.TextColor3 = COLORS.text
		nameLabel.TextSize = 13
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = entry

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Name = "Stats"
		statsLabel.Size = UDim2.new(0.4, -6, 0.5, 0)
		statsLabel.Position = UDim2.new(0.6, 0, 0, 0)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Text = tostring(math.ceil(unit.hp)) .. "/" .. tostring(unit.maxHp) .. " HP"
		statsLabel.TextColor3 = COLORS.success
		statsLabel.TextSize = 11
		statsLabel.Font = Enum.Font.GothamMedium
		statsLabel.TextXAlignment = Enum.TextXAlignment.Right
		statsLabel.Parent = entry

		local stratLabel = Instance.new("TextLabel")
		stratLabel.Name = "Strategy"
		stratLabel.Size = UDim2.new(0.4, -6, 0.5, 0)
		stratLabel.Position = UDim2.new(0.6, 0, 0.5, 0)
		stratLabel.BackgroundTransparency = 1
		stratLabel.Text = unit.attackType:sub(1, 3)
			.. "/"
			.. unit.targetPriority:sub(1, 3)
			.. "/"
			.. unit.defenseType:sub(1, 3)
		stratLabel.TextColor3 = COLORS.textDim
		stratLabel.TextSize = 10
		stratLabel.Font = Enum.Font.Gotham
		stratLabel.TextXAlignment = Enum.TextXAlignment.Right
		stratLabel.Parent = entry
	end
end

-- Arena

local function getArenaCenter(): Vector3
	local player = Players.LocalPlayer
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			return root.Position + ARENA_OFFSET
		end
	end
	return Vector3.new(0, 3, 0)
end

local function createArena()
	if _arenaFolder then
		_arenaFolder:Destroy()
	end

	_arenaCenter = getArenaCenter()
	_arenaFolder = Instance.new("Folder")
	_arenaFolder.Name = "AutoBattlerArena"
	_arenaFolder.Parent = workspace

	-- Player side (left / -X)
	local playerFloor = Instance.new("Part")
	playerFloor.Name = "PlayerFloor"
	playerFloor.Anchored = true
	playerFloor.Size = Vector3.new(ARENA_HALF_WIDTH, FLOOR_HEIGHT, ARENA_DEPTH)
	playerFloor.Position = _arenaCenter + Vector3.new(-ARENA_HALF_WIDTH / 2 - 1, -3, 0)
	playerFloor.Color = Color3.fromRGB(40, 60, 100)
	playerFloor.Material = Enum.Material.SmoothPlastic
	playerFloor.Transparency = 0.3
	playerFloor.CanCollide = false
	playerFloor.Parent = _arenaFolder

	-- Enemy side (right / +X)
	local enemyFloor = Instance.new("Part")
	enemyFloor.Name = "EnemyFloor"
	enemyFloor.Anchored = true
	enemyFloor.Size = Vector3.new(ARENA_HALF_WIDTH, FLOOR_HEIGHT, ARENA_DEPTH)
	enemyFloor.Position = _arenaCenter + Vector3.new(ARENA_HALF_WIDTH / 2 + 1, -3, 0)
	enemyFloor.Color = Color3.fromRGB(100, 40, 40)
	enemyFloor.Material = Enum.Material.SmoothPlastic
	enemyFloor.Transparency = 0.3
	enemyFloor.CanCollide = false
	enemyFloor.Parent = _arenaFolder
end

-- Unit Placement

local function getPlayerSlotPosition(index: number): Vector3
	local zOffset = (index - 1 - (#_playerUnits - 1) / 2) * UNIT_SPACING
	return _arenaCenter + Vector3.new(-ARENA_HALF_WIDTH / 2, 0, zOffset)
end

local function getEnemySlotPosition(index: number, total: number): Vector3
	local zOffset = (index - 1 - (total - 1) / 2) * UNIT_SPACING
	return _arenaCenter + Vector3.new(ARENA_HALF_WIDTH / 2, 0, zOffset)
end

local function repositionPlayerUnits()
	for i, unit in _playerUnits do
		if unit.alive and unit.model and unit.model.PrimaryPart then
			local pos = getPlayerSlotPosition(i)
			unit.model:PivotTo(CFrame.new(pos))
		end
	end
end

-- Enemy Generation

local function createEnemyModel(round: number): Model
	local model = Instance.new("Model")
	model.Name = "Enemy_R" .. tostring(round)

	local partCount = math.random(3, 5)
	local baseColor = ENEMY_COLORS[math.random(1, #ENEMY_COLORS)]

	for i = 1, partCount do
		local part = Instance.new("Part")
		part.Name = "EnemyPart_" .. tostring(i)
		part.Anchored = true
		part.CanCollide = false
		part.Shape = Enum.PartType.Block
		part.Material = Enum.Material.SmoothPlastic

		local sx = math.random(10, 30) / 10
		local sy = math.random(10, 30) / 10
		local sz = math.random(10, 30) / 10
		part.Size = Vector3.new(sx, sy, sz)

		-- Stack/offset parts relative to first
		if i == 1 then
			part.Position = Vector3.zero
		else
			part.Position = Vector3.new(math.random(-15, 15) / 10, math.random(0, 30) / 10, math.random(-15, 15) / 10)
		end

		-- Slight color variation
		local r = math.clamp(baseColor.R * 255 + math.random(-20, 20), 0, 255)
		local g = math.clamp(baseColor.G * 255 + math.random(-20, 20), 0, 255)
		local b = math.clamp(baseColor.B * 255 + math.random(-20, 20), 0, 255)
		part.Color = Color3.fromRGB(r, g, b)

		if i == 1 then
			model.PrimaryPart = part
		else
			-- Weld to first part
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = model.PrimaryPart
			weld.Part1 = part
			weld.Parent = part
		end

		part.Parent = model
	end

	return model
end

local function deriveEnemyStats(round: number): (number, number)
	local hp = 30 + round * 15
	local damage = 5 + round * 3
	return hp, damage
end

local function spawnEnemyTeam()
	-- Clear old enemies
	for _, unit in _enemyUnits do
		if unit.model then
			unit.model:Destroy()
		end
	end
	table.clear(_enemyUnits)

	local count = math.max(1, #_playerUnits)
	for i = 1, count do
		local model = createEnemyModel(_round)
		local pos = getEnemySlotPosition(i, count)
		model:PivotTo(CFrame.new(pos))
		model.Parent = _arenaFolder

		local hp, damage = deriveEnemyStats(_round)
		local unit: UnitData = {
			model = model,
			name = "Enemy " .. tostring(i),
			hp = hp,
			maxHp = hp,
			damage = damage,
			speed = 8 + math.random(0, 4),
			side = "enemy",
			hpBar = nil,
			hpFill = nil,
			alive = true,
			attackType = RANDOM_ATTACK_TYPES[math.random(1, #RANDOM_ATTACK_TYPES)],
			targetPriority = RANDOM_TARGET_PRIORITIES[math.random(1, #RANDOM_TARGET_PRIORITIES)],
			defenseType = RANDOM_DEFENSE_TYPES[math.random(1, #RANDOM_DEFENSE_TYPES)],
		}
		createHpBar(unit)
		table.insert(_enemyUnits, unit)
	end
end

-- Player Unit Creation

local function deriveStatsFromModel(model: Model): (number, number, number)
	local partCount = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			partCount += 1
		end
	end

	local hp = partCount * 10

	local _, size = model:GetBoundingBox()
	local volume = size.X * size.Y * size.Z
	local damage = math.max(1, math.floor(volume / 5))

	local maxDim = math.max(size.X, size.Y, size.Z)
	local speed = math.max(2, 20 / math.max(1, maxDim))

	return hp, damage, speed
end

local function addPlayerUnit(prompt: string)
	if #_playerUnits >= MAX_PLAYER_UNITS then
		setStatus("Max " .. tostring(MAX_PLAYER_UNITS) .. " units", COLORS.error)
		return
	end
	if _fighting then
		setStatus("Can't add units during combat", COLORS.error)
		return
	end
	if prompt == "" then
		setStatus("Enter a creature description", COLORS.error)
		return
	end

	setStatus("Generating unit...", COLORS.accent)
	_promptBox.Text = ""
	updateInputState()

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "creature", "origami", nil, "battler"):await()

		if not _active then
			return
		end

		if not ok or not result or not result.success then
			local errMsg = if result and result.error then tostring(result.error) else "Request failed"
			setStatus(errMsg, COLORS.error)
			updateInputState()
			return
		end

		local modelData = result.model
		local model = OrigamiBuilder.BuildModel(modelData)
		if not model or not model.PrimaryPart then
			setStatus("Failed to build model", COLORS.error)
			updateInputState()
			return
		end

		model.Parent = _arenaFolder

		local hp, damage, speed = deriveStatsFromModel(model)
		local unitName = if modelData and modelData.name then modelData.name else prompt

		-- Read strategy from LLM response, validate, default to basic
		local atkType: AttackType = "single"
		local tgtPriority: TargetPriority = "nearest"
		local defType: DefenseType = "none"
		if modelData then
			if modelData.attackType and VALID_ATTACK_TYPES[modelData.attackType] then
				atkType = modelData.attackType :: AttackType
			end
			if modelData.targetPriority and VALID_TARGET_PRIORITIES[modelData.targetPriority] then
				tgtPriority = modelData.targetPriority :: TargetPriority
			end
			if modelData.defenseType and VALID_DEFENSE_TYPES[modelData.defenseType] then
				defType = modelData.defenseType :: DefenseType
			end
		end

		local unit: UnitData = {
			model = model,
			name = unitName,
			hp = hp,
			maxHp = hp,
			damage = damage,
			speed = speed,
			side = "player",
			hpBar = nil,
			hpFill = nil,
			alive = true,
			attackType = atkType,
			targetPriority = tgtPriority,
			defenseType = defType,
		}
		createHpBar(unit)
		table.insert(_playerUnits, unit)

		-- Position all player units
		repositionPlayerUnits()

		-- Spawn matching enemies
		spawnEnemyTeam()

		setStatus(unitName .. " [" .. atkType .. "/" .. tgtPriority .. "/" .. defType .. "]", COLORS.success)
		refreshUnitList()
		updateFightButton()
		updateInputState()
	end)
end

-- Combat

local function findTarget(unit: UnitData, targets: { UnitData }): UnitData?
	local unitPos = unit.model:GetPivot().Position
	local priority = unit.targetPriority

	local best: UnitData? = nil
	local bestScore = math.huge -- lower is better for nearest/weakest, negated for strongest/fastest

	for _, target in targets do
		if target.alive and target.model and target.model.PrimaryPart then
			local dist = (target.model:GetPivot().Position - unitPos).Magnitude

			if priority == "nearest" then
				if dist < bestScore then
					bestScore = dist
					best = target
				end
			elseif priority == "weakest" then
				if target.hp < bestScore then
					bestScore = target.hp
					best = target
				end
			elseif priority == "strongest" then
				local score = -target.maxHp
				if score < bestScore then
					bestScore = score
					best = target
				end
			elseif priority == "fastest" then
				local score = -target.speed
				if score < bestScore then
					bestScore = score
					best = target
				end
			end
		end
	end

	return best
end

local function moveUnitToward(unit: UnitData, targetPos: Vector3, dt: number)
	if not unit.model or not unit.model.PrimaryPart then
		return
	end

	local currentPos = unit.model:GetPivot().Position
	local direction = targetPos - currentPos
	local dist = direction.Magnitude

	if dist < 1 then
		return
	end

	local moveDir = direction.Unit
	local moveDist = math.min(unit.speed * dt, dist)
	local newPos = currentPos + moveDir * moveDist

	-- Face the target
	local lookCF = CFrame.lookAt(newPos, targetPos)
	unit.model:PivotTo(lookCF)
end

local function teamAlive(units: { UnitData }): boolean
	for _, unit in units do
		if unit.alive then
			return true
		end
	end
	return false
end

local function killUnit(unit: UnitData)
	unit.alive = false
	unit.hp = 0
	if unit.model then
		unit.model:Destroy()
	end
end

local function dealDamage(attacker: UnitData, target: UnitData)
	-- Defense check
	if target.defenseType == "dodge" then
		if math.random() < DODGE_CHANCE then
			return -- dodged
		end
	end

	local dmg = attacker.damage
	if target.defenseType == "armor" and attacker.attackType ~= "piercing" then
		dmg = dmg * (1 - ARMOR_REDUCTION)
	end

	target.hp -= dmg
	updateHpBar(target)
	if target.hp <= 0 then
		killUnit(target)
	end
end

local function applyAttack(attacker: UnitData, target: UnitData, allTargets: { UnitData })
	if attacker.attackType == "splash" then
		-- Damage target + all enemies within SPLASH_RADIUS of target
		local center = target.model:GetPivot().Position
		for _, other in allTargets do
			if other.alive and other.model and other.model.PrimaryPart then
				local dist = (other.model:GetPivot().Position - center).Magnitude
				if dist <= SPLASH_RADIUS then
					dealDamage(attacker, other)
				end
			end
		end
	elseif attacker.attackType == "rapid" then
		-- Two hits at reduced damage
		local origDmg = attacker.damage
		attacker.damage = math.floor(origDmg * 0.6)
		dealDamage(attacker, target)
		if target.alive then
			dealDamage(attacker, target)
		end
		attacker.damage = origDmg
	else
		-- single or piercing (piercing handled in dealDamage)
		dealDamage(attacker, target)
	end
end

local function applyRegen(units: { UnitData })
	for _, unit in units do
		if unit.alive and unit.defenseType == "regen" and unit.hp < unit.maxHp then
			unit.hp = math.min(unit.maxHp, unit.hp + REGEN_PER_TICK)
			updateHpBar(unit)
		end
	end
end

local function runCombat()
	_fighting = true
	updateInputState()
	updateFightButton()
	setStatus("Fight!", COLORS.accent)

	task.spawn(function()
		while _active and _fighting and teamAlive(_playerUnits) and teamAlive(_enemyUnits) do
			-- Regen phase
			applyRegen(_playerUnits)
			applyRegen(_enemyUnits)

			-- Move phase (always move toward strategy target)
			for _, unit in _playerUnits do
				if unit.alive then
					local target = findTarget(unit, _enemyUnits)
					if target and target.model then
						moveUnitToward(unit, target.model:GetPivot().Position, COMBAT_TICK)
					end
				end
			end
			for _, unit in _enemyUnits do
				if unit.alive then
					local target = findTarget(unit, _playerUnits)
					if target and target.model then
						moveUnitToward(unit, target.model:GetPivot().Position, COMBAT_TICK)
					end
				end
			end

			-- Attack phase (uses strategy)
			for _, unit in _playerUnits do
				if unit.alive then
					local target = findTarget(unit, _enemyUnits)
					if target and target.alive and target.model then
						local dist = (unit.model:GetPivot().Position - target.model:GetPivot().Position).Magnitude
						if dist <= ATTACK_RANGE then
							applyAttack(unit, target, _enemyUnits)
						end
					end
				end
			end
			for _, unit in _enemyUnits do
				if unit.alive then
					local target = findTarget(unit, _playerUnits)
					if target and target.alive and target.model then
						local dist = (unit.model:GetPivot().Position - target.model:GetPivot().Position).Magnitude
						if dist <= ATTACK_RANGE then
							applyAttack(unit, target, _playerUnits)
						end
					end
				end
			end

			-- Update unit list mid-combat
			refreshUnitList()

			task.wait(COMBAT_TICK)
		end

		if not _active then
			return
		end

		-- Determine winner
		_fighting = false
		local playerWon = teamAlive(_playerUnits)

		if playerWon then
			_wins += 1
			_round += 1
			setStatus("Victory! Preparing round " .. tostring(_round) .. "...", COLORS.success)

			-- Clean up dead player units
			local surviving: { UnitData } = {}
			for _, unit in _playerUnits do
				if unit.alive then
					table.insert(surviving, unit)
				end
			end
			_playerUnits = surviving

			-- Reposition and spawn new enemies
			repositionPlayerUnits()
			task.wait(1.5)
			if _active then
				spawnEnemyTeam()
			end
		else
			_losses += 1
			setStatus("Defeated at round " .. tostring(_round) .. "!", COLORS.danger)
		end

		updateRoundDisplay()
		refreshUnitList()
		updateFightButton()
		updateInputState()
	end)
end

-- UI

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "AutoBattlerGui"
	_gui.DisplayOrder = 15
	_gui.ResetOnSpawn = false
	_gui.Enabled = false
	_gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Top-left: Round + Record
	local topFrame = Instance.new("Frame")
	topFrame.Name = "TopInfo"
	topFrame.Size = UDim2.fromOffset(180, 60)
	topFrame.Position = UDim2.fromOffset(12, 12)
	topFrame.BackgroundColor3 = COLORS.bg
	topFrame.BackgroundTransparency = 0.2
	topFrame.BorderSizePixel = 0
	topFrame.Parent = _gui

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 8)
	topCorner.Parent = topFrame

	local topPadding = Instance.new("UIPadding")
	topPadding.PaddingLeft = UDim.new(0, 10)
	topPadding.PaddingTop = UDim.new(0, 6)
	topPadding.Parent = topFrame

	_roundLabel = Instance.new("TextLabel")
	_roundLabel.Name = "Round"
	_roundLabel.Size = UDim2.new(1, -10, 0, 24)
	_roundLabel.BackgroundTransparency = 1
	_roundLabel.Text = "Round 1"
	_roundLabel.TextColor3 = COLORS.text
	_roundLabel.TextSize = 18
	_roundLabel.Font = Enum.Font.GothamBold
	_roundLabel.TextXAlignment = Enum.TextXAlignment.Left
	_roundLabel.Parent = topFrame

	_recordLabel = Instance.new("TextLabel")
	_recordLabel.Name = "Record"
	_recordLabel.Size = UDim2.new(1, -10, 0, 20)
	_recordLabel.Position = UDim2.fromOffset(0, 26)
	_recordLabel.BackgroundTransparency = 1
	_recordLabel.Text = "0W / 0L"
	_recordLabel.TextColor3 = COLORS.textDim
	_recordLabel.TextSize = 14
	_recordLabel.Font = Enum.Font.GothamMedium
	_recordLabel.TextXAlignment = Enum.TextXAlignment.Left
	_recordLabel.Parent = topFrame

	-- Unit list panel (left side)
	local unitPanel = Instance.new("Frame")
	unitPanel.Name = "UnitPanel"
	unitPanel.Size = UDim2.fromOffset(200, 220)
	unitPanel.Position = UDim2.fromOffset(12, 84)
	unitPanel.BackgroundColor3 = COLORS.bg
	unitPanel.BackgroundTransparency = 0.2
	unitPanel.BorderSizePixel = 0
	unitPanel.Parent = _gui

	local unitPanelCorner = Instance.new("UICorner")
	unitPanelCorner.CornerRadius = UDim.new(0, 8)
	unitPanelCorner.Parent = unitPanel

	local unitTitle = Instance.new("TextLabel")
	unitTitle.Name = "Title"
	unitTitle.Size = UDim2.new(1, 0, 0, 28)
	unitTitle.BackgroundTransparency = 1
	unitTitle.Text = "Your Units"
	unitTitle.TextColor3 = COLORS.accent
	unitTitle.TextSize = 14
	unitTitle.Font = Enum.Font.GothamBold
	unitTitle.Parent = unitPanel

	_unitListFrame = Instance.new("Frame")
	_unitListFrame.Name = "UnitList"
	_unitListFrame.Size = UDim2.new(1, -12, 1, -34)
	_unitListFrame.Position = UDim2.fromOffset(6, 30)
	_unitListFrame.BackgroundTransparency = 1
	_unitListFrame.Parent = unitPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = _unitListFrame

	-- Bottom-center: prompt + add button
	local bottomFrame = Instance.new("Frame")
	bottomFrame.Name = "BottomInput"
	bottomFrame.Size = UDim2.fromOffset(400, 48)
	bottomFrame.AnchorPoint = Vector2.new(0.5, 1)
	bottomFrame.Position = UDim2.new(0.5, 0, 1, -16)
	bottomFrame.BackgroundColor3 = COLORS.bg
	bottomFrame.BackgroundTransparency = 0.1
	bottomFrame.BorderSizePixel = 0
	bottomFrame.Parent = _gui

	local bottomCorner = Instance.new("UICorner")
	bottomCorner.CornerRadius = UDim.new(0, 8)
	bottomCorner.Parent = bottomFrame

	_promptBox = Instance.new("TextBox")
	_promptBox.Name = "Prompt"
	_promptBox.Size = UDim2.new(1, -120, 1, -8)
	_promptBox.Position = UDim2.fromOffset(6, 4)
	_promptBox.BackgroundColor3 = COLORS.bgLight
	_promptBox.BorderSizePixel = 0
	_promptBox.Text = ""
	_promptBox.PlaceholderText = "Describe a creature..."
	_promptBox.PlaceholderColor3 = COLORS.textDim
	_promptBox.TextColor3 = COLORS.text
	_promptBox.TextSize = 14
	_promptBox.Font = Enum.Font.GothamMedium
	_promptBox.ClearTextOnFocus = false
	_promptBox.Parent = bottomFrame

	local promptCorner = Instance.new("UICorner")
	promptCorner.CornerRadius = UDim.new(0, 6)
	promptCorner.Parent = _promptBox

	local promptPadding = Instance.new("UIPadding")
	promptPadding.PaddingLeft = UDim.new(0, 8)
	promptPadding.PaddingRight = UDim.new(0, 8)
	promptPadding.Parent = _promptBox

	_addButton = Instance.new("TextButton")
	_addButton.Name = "AddUnit"
	_addButton.Size = UDim2.fromOffset(104, 36)
	_addButton.AnchorPoint = Vector2.new(1, 0.5)
	_addButton.Position = UDim2.new(1, -6, 0.5, 0)
	_addButton.BackgroundColor3 = COLORS.accent
	_addButton.BorderSizePixel = 0
	_addButton.Text = "Add Unit"
	_addButton.TextColor3 = COLORS.bg
	_addButton.TextSize = 14
	_addButton.Font = Enum.Font.GothamBold
	_addButton.Parent = bottomFrame

	local addCorner = Instance.new("UICorner")
	addCorner.CornerRadius = UDim.new(0, 6)
	addCorner.Parent = _addButton

	-- Fight button (center)
	_fightButton = Instance.new("TextButton")
	_fightButton.Name = "FightButton"
	_fightButton.Size = UDim2.fromOffset(160, 52)
	_fightButton.AnchorPoint = Vector2.new(0.5, 1)
	_fightButton.Position = UDim2.new(0.5, 0, 1, -76)
	_fightButton.BackgroundColor3 = COLORS.success
	_fightButton.BorderSizePixel = 0
	_fightButton.Text = "Fight!"
	_fightButton.TextColor3 = COLORS.bg
	_fightButton.TextSize = 22
	_fightButton.Font = Enum.Font.GothamBold
	_fightButton.Visible = false
	_fightButton.Parent = _gui

	local fightCorner = Instance.new("UICorner")
	fightCorner.CornerRadius = UDim.new(0, 10)
	fightCorner.Parent = _fightButton

	-- Status label
	_statusLabel = Instance.new("TextLabel")
	_statusLabel.Name = "Status"
	_statusLabel.Size = UDim2.fromOffset(400, 24)
	_statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	_statusLabel.Position = UDim2.new(0.5, 0, 1, -68)
	_statusLabel.BackgroundTransparency = 1
	_statusLabel.Text = ""
	_statusLabel.TextColor3 = COLORS.textDim
	_statusLabel.TextSize = 14
	_statusLabel.Font = Enum.Font.GothamMedium
	_statusLabel.Parent = _gui

	-- Wire up events
	_addButton.Activated:Connect(function()
		if not _fighting and #_playerUnits < MAX_PLAYER_UNITS then
			addPlayerUnit(_promptBox.Text)
		end
	end)

	_fightButton.Activated:Connect(function()
		if not _fighting and #_playerUnits > 0 and #_enemyUnits > 0 then
			runCombat()
		end
	end)
end

-- Activate / Cleanup

local AutoBattlerController = Knit.CreateController({
	Name = "AutoBattlerController",
})

function AutoBattlerController:Activate()
	if _active then
		return
	end
	_active = true
	_fighting = false
	_round = 1
	_wins = 0
	_losses = 0
	table.clear(_playerUnits)
	table.clear(_enemyUnits)

	createArena()
	_gui.Enabled = true
	updateRoundDisplay()
	refreshUnitList()
	updateFightButton()
	updateInputState()
	setStatus("Describe creatures to build your team!", COLORS.accent)
end

function AutoBattlerController:Cleanup()
	_active = false
	_fighting = false
	_gui.Enabled = false

	-- Destroy all units
	for _, unit in _playerUnits do
		if unit.model then
			unit.model:Destroy()
		end
	end
	for _, unit in _enemyUnits do
		if unit.model then
			unit.model:Destroy()
		end
	end
	table.clear(_playerUnits)
	table.clear(_enemyUnits)

	if _arenaFolder then
		_arenaFolder:Destroy()
		_arenaFolder = nil
	end

	refreshUnitList()
end

function AutoBattlerController:KnitInit() end

function AutoBattlerController:KnitStart()
	createUI()

	GameMode.Changed:Connect(function(newMode: string, oldMode: string)
		if newMode == "auto_battler" then
			self:Activate()
		elseif oldMode == "auto_battler" then
			self:Cleanup()
		end
	end)
end

return AutoBattlerController
