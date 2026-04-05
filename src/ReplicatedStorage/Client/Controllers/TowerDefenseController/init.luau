--!strict
--[[
	TowerDefenseController
	PvP tower defense: Player vs Bot. Both sides earn gold passively, build towers (defend),
	and send creep (attack). First to destroy the enemy base wins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local TDCombat = require(ReplicatedStorage.Shared.TDCombat)
local TDPathGenerator = require(ReplicatedStorage.Shared.TDPathGenerator)

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
	gold = Color3.fromRGB(255, 210, 60),
	botColor = Color3.fromRGB(200, 80, 80),
	playerColor = Color3.fromRGB(80, 160, 255),
}

-- Layout constants
local WAYPOINT_COUNT = 6
local PATH_LENGTH = 100
local PATH_Y = 0.5
local TOWER_OFFSET = 10

-- Combat constants
local ATTACK_INTERVAL = 1
local PROJECTILE_SPEED = 0.3
local BASE_HP = 100

-- Economy constants
local STARTING_GOLD = 100
local GOLD_PER_SECOND = 5
local KILL_BONUS = 10
local TOWER_COST = 50

-- Creep tiers
local CREEP_TIERS = {
	Scout = { cost = 20, hp = 40, speed = 14, size = 2, label = "Scout (20g)" },
	Soldier = { cost = 35, hp = 80, speed = 10, size = 3, label = "Soldier (35g)" },
	Brute = { cost = 50, hp = 150, speed = 6, size = 4, label = "Brute (50g)" },
}

-- Bot AI constants
local BOT_THINK_INTERVAL = 4
local BOT_MAX_TOWERS = 5

-- Strategy constants (shared via TDCombat, kept as local aliases for this controller)
local ARMOR_REDUCTION = TDCombat.ARMOR_REDUCTION
local DODGE_CHANCE = TDCombat.DODGE_CHANCE
local REGEN_PER_TICK = TDCombat.REGEN_PER_TICK
local SPLASH_RADIUS = TDCombat.SPLASH_RADIUS

type AttackType = "single" | "splash" | "rapid" | "piercing"
type TargetPriority = "nearest" | "weakest" | "strongest" | "fastest"
type DefenseType = "none" | "armor" | "dodge" | "regen"

local VALID_ATTACK_TYPES: { [string]: boolean } = { single = true, splash = true, rapid = true, piercing = true }
local VALID_TARGET_PRIORITIES: { [string]: boolean } =
	{ nearest = true, weakest = true, strongest = true, fastest = true }
local RANDOM_ATTACK_TYPES: { AttackType } = { "single", "splash", "rapid", "piercing" }
local RANDOM_TARGET_PRIORITIES: { TargetPriority } = { "nearest", "weakest", "strongest", "fastest" }
local RANDOM_DEFENSE_TYPES: { DefenseType } = { "none", "armor", "dodge", "regen" }

-- Types
type Tower = {
	model: Model | BasePart,
	damage: number,
	range: number,
	position: Vector3,
	side: string,
	_lastAttack: number,
	attackType: AttackType,
	targetPriority: TargetPriority,
}
type Creep = {
	part: BasePart,
	hp: number,
	maxHp: number,
	waypointIndex: number,
	speed: number,
	alive: boolean,
	side: string,
	tier: string,
	defenseType: DefenseType,
}

-- State
local _gui: ScreenGui? = nil
local _active = false
local _gameOver = false

local _playerGold = STARTING_GOLD
local _botGold = STARTING_GOLD
local _playerBaseHP = BASE_HP
local _botBaseHP = BASE_HP

local _playerTowers: { Tower } = {}
local _botTowers: { Tower } = {}
local _playerCreep: { Creep } = {} -- player's creep walk toward bot base
local _botCreep: { Creep } = {} -- bot's creep walk toward player base

local _waypoints: { Vector3 } = {}
local _waypointParts: { BasePart } = {}
local _allInstances: { Instance } = {}
local _connections: { RBXScriptConnection } = {}

-- UI refs
local _goldLabel: TextLabel? = nil
local _playerHPLabel: TextLabel? = nil
local _botHPLabel: TextLabel? = nil
local _statusLabel: TextLabel? = nil
local _inputBox: TextBox? = nil
local _buildButton: TextButton? = nil
local _scoutButton: TextButton? = nil
local _soldierButton: TextButton? = nil
local _bruteButton: TextButton? = nil
local _gameOverLabel: TextLabel? = nil

-- World folders
local _pathFolder: Folder? = nil
local _towerFolder: Folder? = nil
local _creepFolder: Folder? = nil
local _projectileFolder: Folder? = nil
local _baseFolder: Folder? = nil

-- Base parts (visual)
local _playerBasePart: BasePart? = nil
local _botBasePart: BasePart? = nil

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
	_waypoints = TDPathGenerator.generateLinearPath(origin, PATH_LENGTH, WAYPOINT_COUNT, 15)
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

local function createBases()
	if #_waypoints < 2 then
		return
	end

	-- Player base (left end)
	local playerBase = Instance.new("Part")
	playerBase.Shape = Enum.PartType.Block
	playerBase.Size = Vector3.new(6, 8, 6)
	playerBase.Position = _waypoints[1] + Vector3.new(-4, 4, 0)
	playerBase.Anchored = true
	playerBase.CanCollide = false
	playerBase.Material = Enum.Material.SmoothPlastic
	playerBase.Color = COLORS.playerColor
	playerBase.Transparency = 0.3
	playerBase.Parent = _baseFolder
	table.insert(_allInstances, playerBase)
	_playerBasePart = playerBase

	-- Bot base (right end)
	local botBase = Instance.new("Part")
	botBase.Shape = Enum.PartType.Block
	botBase.Size = Vector3.new(6, 8, 6)
	botBase.Position = _waypoints[#_waypoints] + Vector3.new(4, 4, 0)
	botBase.Anchored = true
	botBase.CanCollide = false
	botBase.Material = Enum.Material.SmoothPlastic
	botBase.Color = COLORS.botColor
	botBase.Transparency = 0.3
	botBase.Parent = _baseFolder
	table.insert(_allInstances, botBase)
	_botBasePart = botBase
end

local function setStatus(text: string, color: Color3?)
	if _statusLabel then
		_statusLabel.Text = text
		_statusLabel.TextColor3 = color or COLORS.text
	end
end

local function updateHUD()
	if _goldLabel then
		_goldLabel.Text = "Gold: " .. tostring(math.floor(_playerGold))
	end
	if _playerHPLabel then
		_playerHPLabel.Text = "Your Base: " .. tostring(math.floor(_playerBaseHP))
		_playerHPLabel.TextColor3 = if _playerBaseHP <= 30 then COLORS.danger else COLORS.playerColor
	end
	if _botHPLabel then
		_botHPLabel.Text = "Enemy Base: " .. tostring(math.floor(_botBaseHP))
		_botHPLabel.TextColor3 = if _botBaseHP <= 30 then COLORS.success else COLORS.botColor
	end

	-- Update creep button states
	local buttons = {
		{ btn = _scoutButton, cost = CREEP_TIERS.Scout.cost },
		{ btn = _soldierButton, cost = CREEP_TIERS.Soldier.cost },
		{ btn = _bruteButton, cost = CREEP_TIERS.Brute.cost },
	}
	for _, entry in ipairs(buttons) do
		if entry.btn then
			local canAfford = _playerGold >= entry.cost and not _gameOver
			entry.btn.AutoButtonColor = canAfford
			entry.btn.BackgroundColor3 = if canAfford then COLORS.accent else COLORS.disabled
		end
	end

	-- Build button: need gold + not game over
	if _buildButton then
		local canBuild = _playerGold >= TOWER_COST and not _gameOver
		_buildButton.AutoButtonColor = canBuild
		_buildButton.BackgroundColor3 = if canBuild then COLORS.accent else COLORS.disabled
	end

	-- Update base visuals (flash when low HP)
	if _playerBasePart then
		_playerBasePart.Transparency = if _playerBaseHP <= 30 then 0.1 else 0.3
	end
	if _botBasePart then
		_botBasePart.Transparency = if _botBaseHP <= 30 then 0.1 else 0.3
	end
end

-- Combat

local function findCreepTarget(pos: Vector3, range: number, creepList: { Creep }, priority: TargetPriority): Creep?
	local best: Creep? = nil
	local bestScore = math.huge

	for _, creep in ipairs(creepList) do
		if creep.alive and creep.part and creep.part.Parent then
			local dist = (creep.part.Position - pos).Magnitude
			if dist <= range then
				if priority == "nearest" then
					if dist < bestScore then
						bestScore = dist
						best = creep
					end
				elseif priority == "weakest" then
					if creep.hp < bestScore then
						bestScore = creep.hp
						best = creep
					end
				elseif priority == "strongest" then
					local score = -creep.maxHp
					if score < bestScore then
						bestScore = score
						best = creep
					end
				elseif priority == "fastest" then
					-- In TD, "fastest" means closest to reaching your base (most dangerous)
					local progress: number
					if creep.side == "player" then
						-- Player creep walk left→right, higher index = closer to bot base
						progress = -creep.waypointIndex
					else
						-- Bot creep walk right→left, lower index = closer to player base
						progress = creep.waypointIndex
					end
					if progress < bestScore then
						bestScore = progress
						best = creep
					end
				end
			end
		end
	end
	return best
end

local function damageCreep(creep: Creep, damage: number, attackType: AttackType, killerSide: string)
	if not creep.alive then
		return
	end

	-- Defense checks
	if creep.defenseType == "dodge" then
		if math.random() < DODGE_CHANCE then
			return
		end
	end

	local dmg = damage
	if creep.defenseType == "armor" and attackType ~= "piercing" then
		dmg = dmg * (1 - ARMOR_REDUCTION)
	end

	creep.hp -= dmg
	if creep.hp <= 0 then
		creep.alive = false
		if creep.part and creep.part.Parent then
			creep.part:Destroy()
		end
		if killerSide == "player" then
			_playerGold += KILL_BONUS
		else
			_botGold += KILL_BONUS
		end
	end
end

local function fireProjectile(
	from: Vector3,
	target: BasePart,
	tower: Tower,
	targetCreepList: { Creep },
	killerSide: string
)
	local proj = Instance.new("Part")
	proj.Shape = Enum.PartType.Ball
	proj.Size = if tower.attackType == "splash" then Vector3.new(1.5, 1.5, 1.5) else Vector3.new(1, 1, 1)
	proj.Position = from + Vector3.new(0, 3, 0)
	proj.Anchored = true
	proj.CanCollide = false
	proj.Material = Enum.Material.Neon
	proj.Color = if killerSide == "player" then COLORS.playerColor else COLORS.botColor
	proj.Parent = _projectileFolder
	table.insert(_allInstances, proj)

	task.spawn(function()
		local startPos = proj.Position
		local elapsed = 0
		while elapsed < PROJECTILE_SPEED and proj.Parent and target and target.Parent do
			elapsed += task.wait()
			local t = math.min(elapsed / PROJECTILE_SPEED, 1)
			proj.Position = startPos:Lerp(target.Position, t)
		end

		if tower.attackType == "splash" then
			-- Damage all creep near impact point
			local impactPos = if target and target.Parent then target.Position else proj.Position
			for _, creep in ipairs(targetCreepList) do
				if creep.alive and creep.part and creep.part.Parent then
					local dist = (creep.part.Position - impactPos).Magnitude
					if dist <= SPLASH_RADIUS then
						damageCreep(creep, tower.damage, tower.attackType, killerSide)
					end
				end
			end
		else
			-- Single target (single, rapid, piercing)
			for _, creep in ipairs(targetCreepList) do
				if creep.part == target and creep.alive then
					damageCreep(creep, tower.damage, tower.attackType, killerSide)
					break
				end
			end
		end

		if proj.Parent then
			proj:Destroy()
		end
	end)
end

local function checkGameOver()
	if _gameOver then
		return
	end

	local winner: string? = nil
	if _playerBaseHP <= 0 then
		_playerBaseHP = 0
		winner = "bot"
	elseif _botBaseHP <= 0 then
		_botBaseHP = 0
		winner = "player"
	end

	if winner then
		_gameOver = true
		updateHUD()
		if _gameOverLabel then
			_gameOverLabel.Text = if winner == "player" then "VICTORY!" else "DEFEAT!"
			_gameOverLabel.TextColor3 = if winner == "player" then COLORS.success else COLORS.danger
			_gameOverLabel.Visible = true
		end
		setStatus(
			if winner == "player" then "You destroyed the enemy base!" else "Your base was destroyed!",
			if winner == "player" then COLORS.success else COLORS.danger
		)
	end
end

-- Creep System

local function spawnCreep(side: string, tierName: string)
	if #_waypoints < 2 or _gameOver then
		return
	end

	local tier = CREEP_TIERS[tierName]
	if not tier then
		return
	end

	-- Deduct gold
	if side == "player" then
		if _playerGold < tier.cost then
			return
		end
		_playerGold -= tier.cost
	else
		if _botGold < tier.cost then
			return
		end
		_botGold -= tier.cost
	end

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(tier.size, tier.size, tier.size)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic

	-- Player creep start at player base (waypoint 1), walk toward bot base (last waypoint)
	-- Bot creep start at bot base (last waypoint), walk toward player base (waypoint 1)
	if side == "player" then
		part.Position = _waypoints[1] + Vector3.new(0, tier.size / 2, 0)
		part.Color = COLORS.playerColor
	else
		part.Position = _waypoints[#_waypoints] + Vector3.new(0, tier.size / 2, 0)
		part.Color = COLORS.botColor
	end

	part.Parent = _creepFolder
	table.insert(_allInstances, part)

	-- Assign defense type: brutes get armor, scouts get dodge, soldiers random
	local defType: DefenseType = "none"
	if tierName == "Brute" then
		defType = "armor"
	elseif tierName == "Scout" then
		defType = "dodge"
	elseif tierName == "Soldier" then
		defType = RANDOM_DEFENSE_TYPES[math.random(1, #RANDOM_DEFENSE_TYPES)]
	end

	local creep: Creep = {
		part = part,
		hp = tier.hp,
		maxHp = tier.hp,
		waypointIndex = if side == "player" then 1 else #_waypoints,
		speed = tier.speed,
		alive = true,
		side = side,
		tier = tierName,
		defenseType = defType,
	}

	if side == "player" then
		table.insert(_playerCreep, creep)
	else
		table.insert(_botCreep, creep)
	end

	updateHUD()

	-- Move creep along waypoints
	task.spawn(function()
		if side == "player" then
			-- Walk left to right (waypoint 1 → last)
			while creep.alive and not _gameOver and creep.waypointIndex < #_waypoints do
				local targetIdx = creep.waypointIndex + 1
				local target = _waypoints[targetIdx] + Vector3.new(0, tier.size / 2, 0)
				local start = creep.part.Position

				local dist = (target - start).Magnitude
				local duration = dist / creep.speed
				local elapsed = 0

				while elapsed < duration and creep.alive and creep.part and creep.part.Parent do
					local dt = task.wait()
					elapsed += dt
					local t = math.min(elapsed / duration, 1)
					creep.part.Position = start:Lerp(target, t)
				end

				if creep.alive then
					creep.waypointIndex = targetIdx
				end
			end

			-- Reached bot base
			if creep.alive and creep.waypointIndex >= #_waypoints then
				creep.alive = false
				_botBaseHP -= 10
				if creep.part and creep.part.Parent then
					creep.part:Destroy()
				end
				checkGameOver()
				updateHUD()
			end
		else
			-- Walk right to left (last waypoint → 1)
			while creep.alive and not _gameOver and creep.waypointIndex > 1 do
				local targetIdx = creep.waypointIndex - 1
				local target = _waypoints[targetIdx] + Vector3.new(0, tier.size / 2, 0)
				local start = creep.part.Position

				local dist = (target - start).Magnitude
				local duration = dist / creep.speed
				local elapsed = 0

				while elapsed < duration and creep.alive and creep.part and creep.part.Parent do
					local dt = task.wait()
					elapsed += dt
					local t = math.min(elapsed / duration, 1)
					creep.part.Position = start:Lerp(target, t)
				end

				if creep.alive then
					creep.waypointIndex = targetIdx
				end
			end

			-- Reached player base
			if creep.alive and creep.waypointIndex <= 1 then
				creep.alive = false
				_playerBaseHP -= 10
				if creep.part and creep.part.Parent then
					creep.part:Destroy()
				end
				checkGameOver()
				updateHUD()
			end
		end
	end)
end

-- Tower Placement

local function placeTowerAtPosition(model: Model | BasePart, side: string, placePos: Vector3): Tower
	if typeof(model) == "Instance" and model:IsA("Model") then
		(model :: Model):PivotTo(CFrame.new(placePos))
	else
		(model :: BasePart).Position = placePos
	end

	if typeof(model) == "Instance" and model:IsA("Model") then
		model.Parent = _towerFolder
	else
		(model :: BasePart).Parent = _towerFolder
	end
	table.insert(_allInstances, model)

	local stats = TDCombat.deriveTowerStats(model)
	local damage = stats.damage
	local range = stats.range

	if model:IsA("Model") then
		OrigamiBuilder.ApplyAnimation(model, "idle_bob")
	end

	local tower: Tower = {
		model = model,
		damage = damage,
		range = range,
		position = placePos,
		side = side,
		_lastAttack = 0,
		attackType = "single",
		targetPriority = "nearest",
	}

	if side == "player" then
		table.insert(_playerTowers, tower)
	else
		table.insert(_botTowers, tower)
	end

	return tower
end

local function getRandomTowerPosition(side: string): Vector3
	if #_waypoints < 2 then
		return Vector3.new(0, 2, 0)
	end

	-- Player towers on left half, bot towers on right half
	local startIdx, endIdx
	if side == "player" then
		startIdx = 1
		endIdx = math.max(1, math.floor(#_waypoints / 2))
	else
		startIdx = math.ceil(#_waypoints / 2) + 1
		endIdx = #_waypoints
	end

	local wpIndex = math.random(startIdx, math.max(startIdx, endIdx - 1))
	local wp = _waypoints[wpIndex]
	local nextWp = _waypoints[math.min(wpIndex + 1, #_waypoints)]
	local dir = (nextWp - wp).Unit
	local perpendicular = Vector3.new(-dir.Z, 0, dir.X)
	local sideOffset = if math.random() > 0.5 then 1 else -1
	local offset = perpendicular * (TOWER_OFFSET * sideOffset)
	return wp + offset + Vector3.new(0, 2, 0)
end

local function placeTower(modelData: { [string]: any })
	local model = OrigamiBuilder.BuildModel(modelData)
	if not model then
		setStatus("Failed to build tower model", COLORS.error)
		return
	end

	local placePos = getRandomTowerPosition("player")
	local tower = placeTowerAtPosition(model, "player", placePos)

	-- Read strategy from LLM response
	if modelData then
		if modelData.attackType and VALID_ATTACK_TYPES[modelData.attackType] then
			tower.attackType = modelData.attackType :: AttackType
		end
		if modelData.targetPriority and VALID_TARGET_PRIORITIES[modelData.targetPriority] then
			tower.targetPriority = modelData.targetPriority :: TargetPriority
		end
	end

	setStatus(
		string.format("Tower [%s/%s] DMG:%d", tower.attackType, tower.targetPriority, tower.damage),
		COLORS.success
	)
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
	if _playerGold < TOWER_COST then
		setStatus("Not enough gold! Need " .. tostring(TOWER_COST), COLORS.error)
		return
	end

	_playerGold -= TOWER_COST
	updateHUD()
	_inputBox.Text = ""
	setStatus("Building tower...", COLORS.accent)

	if _buildButton then
		_buildButton.AutoButtonColor = false
		_buildButton.BackgroundColor3 = COLORS.disabled
	end

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "building", "origami", nil, "tower"):await()

		if _buildButton then
			_buildButton.AutoButtonColor = true
			_buildButton.BackgroundColor3 = COLORS.accent
		end

		if ok and result and result.success and result.model then
			placeTower(result.model)
			updateHUD()
		else
			-- Refund gold on failure
			_playerGold += TOWER_COST
			updateHUD()

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

-- Bot AI

local function spawnBotTower()
	if #_waypoints < 2 then
		return
	end

	local placePos = getRandomTowerPosition("bot")

	-- Simple colored block tower for bot
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	local s = math.random(3, 5)
	part.Size = Vector3.new(s, s * 1.5, s)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(math.random(150, 220), math.random(50, 100), math.random(50, 100))

	local tower = placeTowerAtPosition(part, "bot", placePos)
	tower.attackType = RANDOM_ATTACK_TYPES[math.random(1, #RANDOM_ATTACK_TYPES)]
	tower.targetPriority = RANDOM_TARGET_PRIORITIES[math.random(1, #RANDOM_TARGET_PRIORITIES)]
end

local function botThink()
	if _gameOver or not _active then
		return
	end

	-- Priority 1: Build tower if fewer than max
	if _botGold >= TOWER_COST and #_botTowers < BOT_MAX_TOWERS then
		if math.random() < 0.4 then
			spawnBotTower()
			_botGold -= TOWER_COST
		end
	end

	-- Priority 2: Send creep
	if _botGold >= CREEP_TIERS.Scout.cost then
		local roll = math.random()
		if roll < 0.4 and _botGold >= CREEP_TIERS.Brute.cost then
			spawnCreep("bot", "Brute")
		elseif roll < 0.7 and _botGold >= CREEP_TIERS.Soldier.cost then
			spawnCreep("bot", "Soldier")
		else
			spawnCreep("bot", "Scout")
		end
	end
end

-- Attack Loop

local function towerAttack(tower: Tower, targetCreepList: { Creep }, killerSide: string)
	local interval = if tower.attackType == "rapid" then ATTACK_INTERVAL * 0.5 else ATTACK_INTERVAL
	local now = os.clock()
	if now - tower._lastAttack < interval then
		return
	end

	local target = findCreepTarget(tower.position, tower.range, targetCreepList, tower.targetPriority)
	if not target then
		return
	end

	tower._lastAttack = now
	local dmg = if tower.attackType == "rapid" then math.floor(tower.damage * 0.6) else tower.damage
	local effectiveTower: Tower = {
		model = tower.model,
		damage = dmg,
		range = tower.range,
		position = tower.position,
		side = tower.side,
		_lastAttack = tower._lastAttack,
		attackType = tower.attackType,
		targetPriority = tower.targetPriority,
	}
	fireProjectile(tower.position, target.part, effectiveTower, targetCreepList, killerSide)
end

local function startAttackLoop()
	local conn = RunService.Heartbeat:Connect(function()
		if not _active or _gameOver then
			return
		end

		-- Player towers attack bot creep
		for _, tower in ipairs(_playerTowers) do
			towerAttack(tower, _botCreep, "player")
		end

		-- Bot towers attack player creep
		for _, tower in ipairs(_botTowers) do
			towerAttack(tower, _playerCreep, "bot")
		end
	end)
	table.insert(_connections, conn)
end

-- Economy Loop

local function applyCreepRegen(creepList: { Creep }, dt: number)
	for _, creep in ipairs(creepList) do
		if creep.alive and creep.defenseType == "regen" and creep.hp < creep.maxHp then
			creep.hp = math.min(creep.maxHp, creep.hp + REGEN_PER_TICK * dt)
		end
	end
end

local function startEconomyLoop()
	local conn = RunService.Heartbeat:Connect(function(dt: number)
		if not _active or _gameOver then
			return
		end

		_playerGold += GOLD_PER_SECOND * dt
		_botGold += GOLD_PER_SECOND * dt

		-- Regen for creep with regen defense
		applyCreepRegen(_playerCreep, dt)
		applyCreepRegen(_botCreep, dt)
	end)
	table.insert(_connections, conn)

	-- HUD update at ~4fps (not every frame)
	task.spawn(function()
		while _active and not _gameOver do
			updateHUD()
			task.wait(0.25)
		end
	end)
end

-- Bot AI Loop

local function startBotAILoop()
	task.spawn(function()
		while _active and not _gameOver do
			task.wait(BOT_THINK_INTERVAL)
			botThink()
		end
	end)
end

-- UI

local function makeCorner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
end

local function createCreepButton(parent: GuiObject, tierName: string, posX: number): TextButton
	local tier = CREEP_TIERS[tierName]
	local btn = Instance.new("TextButton")
	btn.Name = tierName .. "Button"
	btn.Size = UDim2.new(0, 90, 1, 0)
	btn.Position = UDim2.fromOffset(posX, 0)
	btn.Text = tier.label
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.BackgroundColor3 = COLORS.accent
	btn.BorderSizePixel = 0
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	btn.Parent = parent
	makeCorner(btn, 6)

	btn.Activated:Connect(function()
		if not _gameOver and _playerGold >= tier.cost then
			spawnCreep("player", tierName)
			updateHUD()
		end
	end)

	return btn
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

	-- Top-left panel: Gold + Base HPs
	local infoPanel = Instance.new("Frame")
	infoPanel.Name = "InfoPanel"
	infoPanel.Size = UDim2.fromOffset(220, 120)
	infoPanel.Position = UDim2.fromOffset(16, 16)
	infoPanel.BackgroundColor3 = COLORS.bg
	infoPanel.BackgroundTransparency = 0.2
	infoPanel.BorderSizePixel = 0
	infoPanel.Parent = gui
	makeCorner(infoPanel)

	local infoPadding = Instance.new("UIPadding")
	infoPadding.PaddingLeft = UDim.new(0, 12)
	infoPadding.PaddingTop = UDim.new(0, 10)
	infoPadding.Parent = infoPanel

	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldLabel"
	goldLabel.Size = UDim2.new(1, 0, 0, 28)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Text = "Gold: " .. tostring(STARTING_GOLD)
	goldLabel.TextColor3 = COLORS.gold
	goldLabel.TextSize = 22
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Parent = infoPanel
	_goldLabel = goldLabel

	local playerHPLabel = Instance.new("TextLabel")
	playerHPLabel.Name = "PlayerHPLabel"
	playerHPLabel.Size = UDim2.new(1, 0, 0, 26)
	playerHPLabel.Position = UDim2.fromOffset(0, 32)
	playerHPLabel.BackgroundTransparency = 1
	playerHPLabel.Text = "Your Base: " .. tostring(BASE_HP)
	playerHPLabel.TextColor3 = COLORS.playerColor
	playerHPLabel.TextSize = 18
	playerHPLabel.Font = Enum.Font.GothamBold
	playerHPLabel.TextXAlignment = Enum.TextXAlignment.Left
	playerHPLabel.Parent = infoPanel
	_playerHPLabel = playerHPLabel

	local botHPLabel = Instance.new("TextLabel")
	botHPLabel.Name = "BotHPLabel"
	botHPLabel.Size = UDim2.new(1, 0, 0, 26)
	botHPLabel.Position = UDim2.fromOffset(0, 60)
	botHPLabel.BackgroundTransparency = 1
	botHPLabel.Text = "Enemy Base: " .. tostring(BASE_HP)
	botHPLabel.TextColor3 = COLORS.botColor
	botHPLabel.TextSize = 18
	botHPLabel.Font = Enum.Font.GothamBold
	botHPLabel.TextXAlignment = Enum.TextXAlignment.Left
	botHPLabel.Parent = infoPanel
	_botHPLabel = botHPLabel

	-- Bottom bar: input + build + creep buttons
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(0, 700, 0, 100)
	bottomBar.Position = UDim2.new(0.5, -350, 1, -120)
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

	-- Input row: prompt + build button
	local inputRow = Instance.new("Frame")
	inputRow.Name = "InputRow"
	inputRow.Size = UDim2.new(1, 0, 0, 36)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = bottomBar

	local inputBox = Instance.new("TextBox")
	inputBox.Name = "PromptInput"
	inputBox.Size = UDim2.new(1, -130, 1, 0)
	inputBox.PlaceholderText = "Describe your tower... (50g)"
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
	buildButton.Size = UDim2.new(0, 118, 1, 0)
	buildButton.Position = UDim2.new(1, -118, 0, 0)
	buildButton.Text = "Build (50g)"
	buildButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buildButton.BackgroundColor3 = COLORS.accent
	buildButton.BorderSizePixel = 0
	buildButton.TextSize = 15
	buildButton.Font = Enum.Font.GothamBold
	buildButton.AutoButtonColor = true
	buildButton.Parent = inputRow
	makeCorner(buildButton, 6)
	_buildButton = buildButton

	-- Bottom row: creep buttons + status
	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "ButtonRow"
	buttonRow.Size = UDim2.new(1, 0, 0, 36)
	buttonRow.Position = UDim2.fromOffset(0, 44)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = bottomBar

	_scoutButton = createCreepButton(buttonRow, "Scout", 0)
	_soldierButton = createCreepButton(buttonRow, "Soldier", 96)
	_bruteButton = createCreepButton(buttonRow, "Brute", 192)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -300, 1, 0)
	statusLabel.Position = UDim2.fromOffset(296, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Build towers & send creep!"
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
	gameOverLabel.Text = "VICTORY!"
	gameOverLabel.TextColor3 = COLORS.success
	gameOverLabel.TextSize = 64
	gameOverLabel.Font = Enum.Font.GothamBlack
	gameOverLabel.Visible = false
	gameOverLabel.ZIndex = 10
	gameOverLabel.Parent = gui
	_gameOverLabel = gameOverLabel

	-- Wire events
	buildButton.Activated:Connect(submitPrompt)
	inputBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitPrompt()
		end
	end)
end

-- Lifecycle

local function resetState()
	_playerGold = STARTING_GOLD
	_botGold = STARTING_GOLD
	_playerBaseHP = BASE_HP
	_botBaseHP = BASE_HP
	_gameOver = false
	_playerTowers = {}
	_botTowers = {}
	_playerCreep = {}
	_botCreep = {}
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

	_creepFolder = Instance.new("Folder")
	_creepFolder.Name = "TD_Creep"
	_creepFolder.Parent = workspace
	table.insert(_allInstances, _creepFolder)

	_projectileFolder = Instance.new("Folder")
	_projectileFolder.Name = "TD_Projectiles"
	_projectileFolder.Parent = workspace
	table.insert(_allInstances, _projectileFolder)

	_baseFolder = Instance.new("Folder")
	_baseFolder.Name = "TD_Bases"
	_baseFolder.Parent = workspace
	table.insert(_allInstances, _baseFolder)

	-- Set up path and bases
	generateWaypoints()
	createWaypointMarkers()
	createBases()

	-- Show UI
	if _gui then
		_gui.Enabled = true
		if _gameOverLabel then
			_gameOverLabel.Visible = false
		end
	end
	updateHUD()
	setStatus("Build towers & send creep!", COLORS.textDim)

	-- Start loops
	startAttackLoop()
	startEconomyLoop()
	startBotAILoop()
end

function TowerDefenseController:Cleanup()
	_active = false
	_gameOver = true

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

	_pathFolder = nil
	_towerFolder = nil
	_creepFolder = nil
	_projectileFolder = nil
	_baseFolder = nil
	_playerBasePart = nil
	_botBasePart = nil

	_playerTowers = {}
	_botTowers = {}
	_playerCreep = {}
	_botCreep = {}
	_waypoints = {}
	_waypointParts = {}

	if _gui then
		_gui.Enabled = false
	end
end

function TowerDefenseController:KnitInit() end

function TowerDefenseController:KnitStart()
	createUI()

	-- Solo PvP TD disabled — "tower_defense" mode now handled by CoopTowerDefenseController.
	-- Kept as fallback: uncomment below to re-enable solo mode.
	-- GameMode.Changed:Connect(function(newMode: string, oldMode: string)
	-- 	if newMode == "tower_defense" then
	-- 		self:Activate()
	-- 	elseif oldMode == "tower_defense" then
	-- 		self:Cleanup()
	-- 	end
	-- end)
end

return TowerDefenseController
