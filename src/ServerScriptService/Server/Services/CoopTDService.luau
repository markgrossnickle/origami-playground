--[[
	CoopTDService — server-authoritative co-op tower defense.
	2-4 players defend a shared base from waves of enemies converging from multiple directions.
	Activated when players select the "Tower Defense" game mode.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TDCombat = require(ReplicatedStorage.Shared.TDCombat)
local TDPathGenerator = require(ReplicatedStorage.Shared.TDPathGenerator)

local CoopTDService = Knit.CreateService({
	Name = "CoopTDService",
	Client = {
		LobbyUpdated = Knit.CreateSignal(),
		WaveStarted = Knit.CreateSignal(),
		CreepSpawned = Knit.CreateSignal(),
		CreepDied = Knit.CreateSignal(),
		CreepReachedBase = Knit.CreateSignal(),
		BaseHPChanged = Knit.CreateSignal(),
		TowerPlaced = Knit.CreateSignal(),
		TowerAttacked = Knit.CreateSignal(),
		WaveCleared = Knit.CreateSignal(),
		GameOver = Knit.CreateSignal(),
		GoldChanged = Knit.CreateSignal(),
		PrepPhaseStarted = Knit.CreateSignal(),
	},
})

-- Constants
local MAX_PLAYERS = 4
local MIN_PLAYERS = 1 -- allow solo for testing
local BASE_HP_PER_PLAYER = 50
local BASE_HP_START = 200
local STARTING_GOLD = 100
local TOWER_COST = 50
local KILL_BONUS = 10
local PREP_TIME = 15
local CREEP_MOVE_INTERVAL = 0.1

-- Lobby state (single lobby for now)
local _lobby = nil

local function createLobby()
	return {
		players = {} :: { Player },
		ready = {} :: { [number]: boolean }, -- userId → ready
		gold = {} :: { [number]: number }, -- userId → gold
		baseHP = BASE_HP_START,
		wave = 0,
		phase = "waiting", -- waiting, prep, combat, gameover
		creeps = {} :: { any },
		towers = {} :: { any },
		nextCreepId = 0,
		nextTowerId = 0,
		center = Vector3.new(0, 0.5, 0),
		waypoints = {} :: { { Vector3 } }, -- per-direction paths
		prepTimer = 0,
		combatLoop = nil,
	}
end

local function broadcastLobbyState(lobby)
	local playerNames = {}
	local readyState = {}
	for _, p in ipairs(lobby.players) do
		table.insert(playerNames, { name = p.DisplayName, userId = p.UserId, ready = lobby.ready[p.UserId] or false })
		readyState[p.UserId] = lobby.ready[p.UserId] or false
	end

	for _, p in ipairs(lobby.players) do
		CoopTDService.Client.LobbyUpdated:Fire(p, {
			players = playerNames,
			wave = lobby.wave,
			phase = lobby.phase,
			baseHP = lobby.baseHP,
			gold = lobby.gold[p.UserId] or STARTING_GOLD,
			playerCount = #lobby.players,
		})
	end
end

local function broadcastAll(lobby, signalName: string, ...)
	local signal = CoopTDService.Client[signalName]
	if signal then
		for _, p in ipairs(lobby.players) do
			signal:Fire(p, ...)
		end
	end
end

local function getCreepStats(wave: number)
	return {
		hp = 40 + wave * 15,
		count = 3 + wave * 2,
		speed = 8 + wave * 0.5,
	}
end

local function getCreepDefense(wave: number): TDCombat.DefenseType
	if wave <= 3 then
		return "none"
	elseif wave <= 6 then
		local types: { TDCombat.DefenseType } = { "armor", "dodge" }
		return types[math.random(1, #types)]
	else
		local types: { TDCombat.DefenseType } = { "none", "armor", "dodge", "regen" }
		return types[math.random(1, #types)]
	end
end

local function setupPaths(lobby)
	local dirCount = math.max(2, #lobby.players)
	lobby.waypoints = TDPathGenerator.generateConvergingPaths(lobby.center, dirCount, 80, 8)
end

local function spawnWave(lobby)
	local stats = getCreepStats(lobby.wave)
	local dirCount = #lobby.waypoints

	for dir = 1, dirCount do
		local path = lobby.waypoints[dir]
		if not path or #path < 2 then continue end

		for i = 1, stats.count do
			lobby.nextCreepId += 1
			local creep = {
				id = lobby.nextCreepId,
				hp = stats.hp,
				maxHp = stats.hp,
				speed = stats.speed,
				alive = true,
				side = "enemy",
				tier = "wave" .. lobby.wave,
				defenseType = getCreepDefense(lobby.wave),
				waypointIndex = 1,
				direction = dir,
				position = path[1],
				spawnDelay = (i - 1) * 0.8, -- stagger spawns
			}
			table.insert(lobby.creeps, creep)

			-- Broadcast spawn (with delay for stagger)
			task.delay(creep.spawnDelay, function()
				if not creep.alive then return end
				broadcastAll(lobby, "CreepSpawned", {
					id = creep.id,
					hp = creep.hp,
					maxHp = creep.maxHp,
					position = { x = creep.position.X, y = creep.position.Y, z = creep.position.Z },
					direction = dir,
					defenseType = creep.defenseType,
					speed = creep.speed,
				})
			end)
		end
	end
end

local function moveCreeps(lobby, dt: number)
	for _, creep in ipairs(lobby.creeps) do
		if not creep.alive then continue end
		if creep.spawnDelay and creep.spawnDelay > 0 then
			creep.spawnDelay -= dt
			continue
		end

		local path = lobby.waypoints[creep.direction]
		if not path then continue end

		local nextIdx = creep.waypointIndex + 1
		if nextIdx > #path then
			-- Reached the base
			creep.alive = false
			lobby.baseHP = math.max(0, lobby.baseHP - 10)
			broadcastAll(lobby, "CreepReachedBase", { id = creep.id })
			broadcastAll(lobby, "BaseHPChanged", lobby.baseHP)

			if lobby.baseHP <= 0 then
				lobby.phase = "gameover"
				broadcastAll(lobby, "GameOver", { wave = lobby.wave })

				-- Update player data
				local PlayerDataService = Knit.GetService("PlayerDataService")
				for _, p in ipairs(lobby.players) do
					local highestWave = PlayerDataService:Read(p, { "CoopTDHighestWave" }) or 0
					if lobby.wave > highestWave then
						PlayerDataService:Write(p, { "CoopTDHighestWave" }, lobby.wave)
					end
				end
			end
			continue
		end

		local target = path[nextIdx]
		local dir = (target - creep.position).Unit
		local moveAmount = creep.speed * dt
		local dist = (target - creep.position).Magnitude

		if moveAmount >= dist then
			creep.position = target
			creep.waypointIndex = nextIdx
		else
			creep.position = creep.position + dir * moveAmount
		end
	end
end

local function towerAttackLoop(lobby, dt: number)
	for _, tower in ipairs(lobby.towers) do
		local now = os.clock()
		local interval = if tower.attackType == "rapid" then 0.5 else 1.0
		if now - (tower._lastAttack or 0) < interval then continue end

		-- Build temp creep list for TDCombat
		local creepTargets = {}
		for _, c in ipairs(lobby.creeps) do
			if c.alive and (not c.spawnDelay or c.spawnDelay <= 0) then
				table.insert(creepTargets, {
					alive = c.alive,
					position = c.position,
					hp = c.hp,
					maxHp = c.maxHp,
					waypointIndex = c.waypointIndex,
					speed = c.speed,
					side = c.side,
					tier = c.tier,
					defenseType = c.defenseType,
					_ref = c, -- back-reference
				})
			end
		end

		local target = TDCombat.findCreepTarget(tower.position, tower.range, creepTargets, tower.targetPriority)
		if not target then continue end

		tower._lastAttack = now
		local dmg = if tower.attackType == "rapid" then math.floor(tower.damage * 0.6) else tower.damage

		-- Apply damage
		local actualCreep = target._ref
		if tower.attackType == "splash" then
			for _, c in ipairs(lobby.creeps) do
				if c.alive and (c.position - actualCreep.position).Magnitude <= TDCombat.SPLASH_RADIUS then
					local killed = c.hp <= dmg
					TDCombat.damageCreep(c, dmg, tower.attackType, function()
						-- On kill
						local ownerUserId = tower.ownerUserId
						if ownerUserId and lobby.gold[ownerUserId] then
							lobby.gold[ownerUserId] += KILL_BONUS
							-- Find player to notify
							for _, p in ipairs(lobby.players) do
								if p.UserId == ownerUserId then
									CoopTDService.Client.GoldChanged:Fire(p, lobby.gold[ownerUserId])
									break
								end
							end
						end
						broadcastAll(lobby, "CreepDied", { id = c.id })
					end)
				end
			end
		else
			TDCombat.damageCreep(actualCreep, dmg, tower.attackType, function()
				local ownerUserId = tower.ownerUserId
				if ownerUserId and lobby.gold[ownerUserId] then
					lobby.gold[ownerUserId] += KILL_BONUS
					for _, p in ipairs(lobby.players) do
						if p.UserId == ownerUserId then
							CoopTDService.Client.GoldChanged:Fire(p, lobby.gold[ownerUserId])
							break
						end
					end
				end
				broadcastAll(lobby, "CreepDied", { id = actualCreep.id })
			end)
		end

		-- Broadcast attack visual
		broadcastAll(lobby, "TowerAttacked", {
			towerId = tower.id,
			targetId = actualCreep.id,
			attackType = tower.attackType,
			position = { x = tower.position.X, y = tower.position.Y, z = tower.position.Z },
			targetPos = { x = actualCreep.position.X, y = actualCreep.position.Y, z = actualCreep.position.Z },
		})
	end
end

local function checkWaveCleared(lobby)
	for _, c in ipairs(lobby.creeps) do
		if c.alive then return false end
	end
	return true
end

local function startCombatLoop(lobby)
	if lobby.combatLoop then
		lobby.combatLoop:Disconnect()
	end

	lobby.combatLoop = RunService.Heartbeat:Connect(function(dt: number)
		if lobby.phase ~= "combat" then return end

		moveCreeps(lobby, dt)
		towerAttackLoop(lobby, dt)
		TDCombat.applyCreepRegen(lobby.creeps, dt)

		if lobby.phase == "gameover" then
			if lobby.combatLoop then
				lobby.combatLoop:Disconnect()
				lobby.combatLoop = nil
			end
			return
		end

		if checkWaveCleared(lobby) then
			-- Wave cleared!
			local bonus = math.floor((50 + lobby.wave * 10) / #lobby.players)
			for _, p in ipairs(lobby.players) do
				lobby.gold[p.UserId] = (lobby.gold[p.UserId] or 0) + bonus
				CoopTDService.Client.GoldChanged:Fire(p, lobby.gold[p.UserId])
			end

			-- Update wins
			local PlayerDataService = Knit.GetService("PlayerDataService")
			for _, p in ipairs(lobby.players) do
				local wins = PlayerDataService:Read(p, { "CoopTDWins" }) or 0
				PlayerDataService:Write(p, { "CoopTDWins" }, wins + 1)
				local highestWave = PlayerDataService:Read(p, { "CoopTDHighestWave" }) or 0
				if lobby.wave > highestWave then
					PlayerDataService:Write(p, { "CoopTDHighestWave" }, lobby.wave)
				end
			end

			broadcastAll(lobby, "WaveCleared", { wave = lobby.wave, goldBonus = bonus })

			-- Start prep phase for next wave
			lobby.phase = "prep"
			lobby.creeps = {}
			lobby.prepTimer = PREP_TIME

			broadcastAll(lobby, "PrepPhaseStarted", { duration = PREP_TIME, nextWave = lobby.wave + 1 })

			task.spawn(function()
				local remaining = PREP_TIME
				while remaining > 0 and lobby.phase == "prep" do
					task.wait(1)
					remaining -= 1
				end
				if lobby.phase == "prep" then
					startNextWave(lobby)
				end
			end)
		end
	end)
end

function startNextWave(lobby)
	lobby.wave += 1
	lobby.phase = "combat"
	lobby.creeps = {}

	broadcastAll(lobby, "WaveStarted", { wave = lobby.wave })
	spawnWave(lobby)
	startCombatLoop(lobby)
end

---------- Client Methods ----------

function CoopTDService.Client:JoinLobby(player: Player)
	if not _lobby then
		_lobby = createLobby()
	end

	-- Check if already in lobby
	for _, p in ipairs(_lobby.players) do
		if p == player then
			return { success = false, error = "Already in lobby" }
		end
	end

	if #_lobby.players >= MAX_PLAYERS then
		return { success = false, error = "Lobby full (max " .. MAX_PLAYERS .. ")" }
	end

	if _lobby.phase ~= "waiting" then
		return { success = false, error = "Game already in progress" }
	end

	table.insert(_lobby.players, player)
	_lobby.gold[player.UserId] = STARTING_GOLD
	_lobby.ready[player.UserId] = false
	_lobby.baseHP = BASE_HP_START + #_lobby.players * BASE_HP_PER_PLAYER

	broadcastLobbyState(_lobby)

	return {
		success = true,
		playerCount = #_lobby.players,
		baseHP = _lobby.baseHP,
		gold = STARTING_GOLD,
	}
end

function CoopTDService.Client:LeaveLobby(player: Player)
	if not _lobby then
		return { success = false, error = "No lobby" }
	end

	for i, p in ipairs(_lobby.players) do
		if p == player then
			table.remove(_lobby.players, i)
			_lobby.gold[player.UserId] = nil
			_lobby.ready[player.UserId] = nil
			break
		end
	end

	if #_lobby.players == 0 then
		if _lobby.combatLoop then
			_lobby.combatLoop:Disconnect()
		end
		_lobby = nil
	else
		_lobby.baseHP = BASE_HP_START + #_lobby.players * BASE_HP_PER_PLAYER
		broadcastLobbyState(_lobby)
	end

	return { success = true }
end

function CoopTDService.Client:ReadyUp(player: Player)
	if not _lobby then
		return { success = false, error = "No lobby" }
	end

	_lobby.ready[player.UserId] = true
	broadcastLobbyState(_lobby)

	-- Check if all ready
	local allReady = true
	for _, p in ipairs(_lobby.players) do
		if not _lobby.ready[p.UserId] then
			allReady = false
			break
		end
	end

	if allReady and #_lobby.players >= MIN_PLAYERS then
		-- Find center position (average of all players)
		local sum = Vector3.zero
		local count = 0
		for _, p in ipairs(_lobby.players) do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				sum += root.Position
				count += 1
			end
		end
		if count > 0 then
			local avg = sum / count
			_lobby.center = Vector3.new(avg.X, 0.5, avg.Z)
		end

		setupPaths(_lobby)

		-- Send path data to clients
		local pathData = {}
		for i, path in ipairs(_lobby.waypoints) do
			local points = {}
			for _, wp in ipairs(path) do
				table.insert(points, { x = wp.X, y = wp.Y, z = wp.Z })
			end
			table.insert(pathData, points)
		end

		broadcastAll(_lobby, "LobbyUpdated", {
			phase = "starting",
			center = { x = _lobby.center.X, y = _lobby.center.Y, z = _lobby.center.Z },
			paths = pathData,
			baseHP = _lobby.baseHP,
		})

		-- Start prep phase
		_lobby.phase = "prep"
		_lobby.prepTimer = PREP_TIME
		broadcastAll(_lobby, "PrepPhaseStarted", { duration = PREP_TIME, nextWave = 1 })

		task.spawn(function()
			task.wait(PREP_TIME)
			if _lobby and _lobby.phase == "prep" then
				startNextWave(_lobby)
			end
		end)
	end

	return { success = true, allReady = allReady }
end

function CoopTDService.Client:PlaceTower(player: Player, modelData: any, position: { x: number, y: number, z: number })
	if not _lobby then
		return { success = false, error = "No lobby" }
	end

	local gold = _lobby.gold[player.UserId] or 0
	if gold < TOWER_COST then
		return { success = false, error = "Need " .. TOWER_COST .. " gold" }
	end

	_lobby.gold[player.UserId] = gold - TOWER_COST
	self.GoldChanged:Fire(player, _lobby.gold[player.UserId])

	_lobby.nextTowerId += 1
	local pos = Vector3.new(position.x, position.y, position.z)

	-- Derive stats from model data
	local damage = 10
	local range = 20
	if modelData and modelData.parts then
		-- Estimate from part count and sizes
		local totalVol = 0
		local maxDim = 0
		for _, part in ipairs(modelData.parts) do
			if part.size then
				local sx = part.size[1] or 1
				local sy = part.size[2] or 1
				local sz = part.size[3] or 1
				totalVol += sx * sy * sz
				maxDim = math.max(maxDim, sx, sy, sz)
			end
		end
		damage = math.max(5, math.floor(totalVol / 2))
		range = math.max(15, maxDim * 2)
	end

	local attackType: TDCombat.AttackType = "single"
	local targetPriority: TDCombat.TargetPriority = "nearest"
	if modelData then
		if modelData.attackType and TDCombat.VALID_ATTACK_TYPES[modelData.attackType] then
			attackType = modelData.attackType
		end
		if modelData.targetPriority and TDCombat.VALID_TARGET_PRIORITIES[modelData.targetPriority] then
			targetPriority = modelData.targetPriority
		end
	end

	local tower = {
		id = _lobby.nextTowerId,
		position = pos,
		damage = damage,
		range = range,
		attackType = attackType,
		targetPriority = targetPriority,
		ownerUserId = player.UserId,
		ownerName = player.DisplayName,
		_lastAttack = 0,
		modelData = modelData,
	}

	table.insert(_lobby.towers, tower)

	broadcastAll(_lobby, "TowerPlaced", {
		id = tower.id,
		position = { x = pos.X, y = pos.Y, z = pos.Z },
		ownerName = player.DisplayName,
		ownerUserId = player.UserId,
		damage = damage,
		range = range,
		attackType = attackType,
		targetPriority = targetPriority,
		modelData = modelData,
	})

	return { success = true, towerId = tower.id }
end

function CoopTDService.Client:GiftGold(player: Player, targetUserId: number, amount: number)
	if not _lobby then
		return { success = false, error = "No lobby" }
	end

	if amount <= 0 then
		return { success = false, error = "Invalid amount" }
	end

	local gold = _lobby.gold[player.UserId] or 0
	if gold < amount then
		return { success = false, error = "Not enough gold" }
	end

	-- Find target
	local targetPlayer = nil
	for _, p in ipairs(_lobby.players) do
		if p.UserId == targetUserId then
			targetPlayer = p
			break
		end
	end
	if not targetPlayer then
		return { success = false, error = "Player not in lobby" }
	end

	_lobby.gold[player.UserId] = gold - amount
	_lobby.gold[targetUserId] = (_lobby.gold[targetUserId] or 0) + amount

	self.GoldChanged:Fire(player, _lobby.gold[player.UserId])
	self.GoldChanged:Fire(targetPlayer, _lobby.gold[targetUserId])

	return { success = true }
end

function CoopTDService.Client:GetLobbyState(player: Player)
	if not _lobby then
		return nil
	end

	local playerNames = {}
	for _, p in ipairs(_lobby.players) do
		table.insert(playerNames, { name = p.DisplayName, userId = p.UserId, ready = _lobby.ready[p.UserId] or false })
	end

	return {
		players = playerNames,
		wave = _lobby.wave,
		phase = _lobby.phase,
		baseHP = _lobby.baseHP,
		gold = _lobby.gold[player.UserId] or 0,
		playerCount = #_lobby.players,
	}
end

---------- Lifecycle ----------

function CoopTDService:KnitInit() end

function CoopTDService:KnitStart()
	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player)
		if _lobby then
			self.Client:LeaveLobby(player)
		end
	end)
end

return CoopTDService
