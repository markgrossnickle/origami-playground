--!strict
-- CardBattlerController: Clash Royale-style card battler
-- Phase 1: Deck building (create creature cards via LLM prompts)
-- Phase 2: Real-time battle (elixir economy, auto-walking units, base destruction)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local CardBattlerController = Knit.CreateController({ Name = "CardBattlerController" })

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
	elixir = Color3.fromRGB(220, 80, 220),
	elixirBg = Color3.fromRGB(60, 20, 60),
	playerBase = Color3.fromRGB(80, 140, 255),
	botBase = Color3.fromRGB(255, 80, 80),
}

-- Deck building
local MAX_DECK_SIZE = 8
local MIN_DECK_FOR_BATTLE = 4

-- Battle arena
local ARENA_HALF_LENGTH = 40 -- player base at X=-40, bot base at X=+40
local ARENA_Y = 0.5
local BASE_HP = 100
local BASE_SIZE = Vector3.new(6, 8, 10)

-- Elixir
local MAX_ELIXIR = 10
local ELIXIR_REGEN_RATE = 0.5 -- 1 elixir per 2 seconds = 0.5/sec

-- Combat
local ATTACK_RANGE = 8
local SPLASH_RADIUS = 8
local ARMOR_REDUCTION = 0.3
local DODGE_CHANCE = 0.25
local REGEN_PER_TICK = 2
local ATTACK_COOLDOWN = 1.0
local PROJECTILE_SPEED = 0.25
local UNIT_REACH_BASE_DIST = 5

-- Bot AI
local BOT_SPAWN_MIN = 4
local BOT_SPAWN_MAX = 6

-- Strategy types
type AttackType = "single" | "splash" | "rapid" | "piercing"
type TargetPriority = "nearest" | "weakest" | "strongest" | "fastest"
type DefenseType = "none" | "armor" | "dodge" | "regen"

-- Types

type CardData = {
	name: string,
	hp: number,
	atk: number,
	speed: number,
	elixirCost: number,
	modelData: { [string]: any },
	attackType: AttackType,
	targetPriority: TargetPriority,
	defenseType: DefenseType,
}

type BattleUnit = {
	model: Model,
	card: CardData,
	hp: number,
	maxHp: number,
	position: Vector3,
	side: string, -- "player" | "bot"
	alive: boolean,
	_lastAttack: number,
	hpBar: BillboardGui?,
	hpFill: Frame?,
}

-- Bot Templates

local ENEMY_TEMPLATES = {
	{
		name = "Goblin",
		hp = 25,
		atk = 8,
		speed = 10,
		attackType = "single" :: AttackType,
		targetPriority = "nearest" :: TargetPriority,
		defenseType = "dodge" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1, 0 },
				size = { 1.5, 2, 1 },
				color = { 80, 200, 80 },
				material = "SmoothPlastic",
			},
			{
				name = "head",
				shape = "Ball",
				position = { 0, 2.5, 0 },
				size = { 1, 1, 1 },
				color = { 80, 200, 80 },
				material = "SmoothPlastic",
			},
		},
	},
	{
		name = "Imp",
		hp = 20,
		atk = 12,
		speed = 12,
		attackType = "rapid" :: AttackType,
		targetPriority = "weakest" :: TargetPriority,
		defenseType = "none" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1, 0 },
				size = { 1.2, 1.8, 1 },
				color = { 200, 60, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "head",
				shape = "Ball",
				position = { 0, 2.3, 0 },
				size = { 0.8, 0.8, 0.8 },
				color = { 200, 60, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "horn",
				shape = "Wedge",
				position = { 0, 3, 0 },
				size = { 0.3, 0.6, 0.3 },
				color = { 160, 40, 40 },
				material = "SmoothPlastic",
			},
		},
	},
	{
		name = "Slime",
		hp = 35,
		atk = 6,
		speed = 7,
		attackType = "splash" :: AttackType,
		targetPriority = "nearest" :: TargetPriority,
		defenseType = "regen" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Ball",
				position = { 0, 0.8, 0 },
				size = { 2, 1.6, 2 },
				color = { 100, 220, 200 },
				material = "Glass",
			},
			{
				name = "core",
				shape = "Ball",
				position = { 0, 0.8, 0 },
				size = { 0.8, 0.8, 0.8 },
				color = { 60, 180, 160 },
				material = "Neon",
			},
		},
	},
	{
		name = "Golem",
		hp = 60,
		atk = 10,
		speed = 4,
		attackType = "single" :: AttackType,
		targetPriority = "nearest" :: TargetPriority,
		defenseType = "armor" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1.2, 0 },
				size = { 2, 2.4, 1.5 },
				color = { 140, 120, 100 },
				material = "Concrete",
			},
			{
				name = "head",
				shape = "Block",
				position = { 0, 3, 0 },
				size = { 1.2, 1.2, 1.2 },
				color = { 140, 120, 100 },
				material = "Concrete",
			},
			{
				name = "arm_l",
				shape = "Block",
				position = { -1.5, 1.5, 0 },
				size = { 0.8, 2, 0.8 },
				color = { 120, 100, 80 },
				material = "Concrete",
			},
			{
				name = "arm_r",
				shape = "Block",
				position = { 1.5, 1.5, 0 },
				size = { 0.8, 2, 0.8 },
				color = { 120, 100, 80 },
				material = "Concrete",
			},
		},
	},
	{
		name = "Shadow",
		hp = 18,
		atk = 14,
		speed = 16,
		attackType = "piercing" :: AttackType,
		targetPriority = "weakest" :: TargetPriority,
		defenseType = "dodge" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1, 0 },
				size = { 1, 2.2, 0.6 },
				color = { 40, 20, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "head",
				shape = "Ball",
				position = { 0, 2.5, 0 },
				size = { 0.7, 0.7, 0.7 },
				color = { 60, 30, 80 },
				material = "SmoothPlastic",
			},
			{
				name = "eye",
				shape = "Ball",
				position = { 0, 2.5, -0.3 },
				size = { 0.3, 0.15, 0.15 },
				color = { 200, 50, 255 },
				material = "Neon",
			},
		},
	},
	{
		name = "Brute",
		hp = 70,
		atk = 15,
		speed = 3,
		attackType = "splash" :: AttackType,
		targetPriority = "strongest" :: TargetPriority,
		defenseType = "armor" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1.5, 0 },
				size = { 3, 3, 2 },
				color = { 100, 60, 50 },
				material = "Concrete",
			},
			{
				name = "head",
				shape = "Block",
				position = { 0, 3.5, 0 },
				size = { 1.5, 1, 1.5 },
				color = { 110, 70, 55 },
				material = "Concrete",
			},
			{
				name = "arm_l",
				shape = "Block",
				position = { -2.2, 1.5, 0 },
				size = { 1.2, 2.5, 1.2 },
				color = { 90, 55, 45 },
				material = "Concrete",
			},
			{
				name = "arm_r",
				shape = "Block",
				position = { 2.2, 1.5, 0 },
				size = { 1.2, 2.5, 1.2 },
				color = { 90, 55, 45 },
				material = "Concrete",
			},
		},
	},
	{
		name = "Healer",
		hp = 30,
		atk = 5,
		speed = 6,
		attackType = "single" :: AttackType,
		targetPriority = "weakest" :: TargetPriority,
		defenseType = "regen" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1, 0 },
				size = { 1.2, 2, 1 },
				color = { 220, 220, 240 },
				material = "SmoothPlastic",
			},
			{
				name = "head",
				shape = "Ball",
				position = { 0, 2.5, 0 },
				size = { 0.9, 0.9, 0.9 },
				color = { 230, 230, 250 },
				material = "SmoothPlastic",
			},
			{
				name = "halo",
				shape = "Cylinder",
				position = { 0, 3.2, 0 },
				size = { 0.1, 1.4, 1.4 },
				color = { 255, 255, 100 },
				material = "Neon",
			},
		},
	},
	{
		name = "Archer",
		hp = 22,
		atk = 11,
		speed = 8,
		attackType = "rapid" :: AttackType,
		targetPriority = "strongest" :: TargetPriority,
		defenseType = "none" :: DefenseType,
		parts = {
			{
				name = "body",
				shape = "Block",
				position = { 0, 1, 0 },
				size = { 1, 2, 0.8 },
				color = { 60, 140, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "head",
				shape = "Ball",
				position = { 0, 2.4, 0 },
				size = { 0.8, 0.8, 0.8 },
				color = { 60, 140, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "bow",
				shape = "Block",
				position = { 0.7, 1.2, 0 },
				size = { 0.15, 1.8, 0.15 },
				color = { 120, 80, 40 },
				material = "Wood",
			},
		},
	},
}

-- State

local _gui: ScreenGui = nil :: any
local _active = false

-- Phase
local _phase: string = "deck_building" -- "deck_building" | "battle"

-- Deck building state
local _deck: { CardData } = {}

-- Battle state
local _playerElixir = 5.0
local _botElixir = 5.0
local _hand: { CardData } = {}
local _drawPile: { CardData } = {}
local _nextCard: CardData? = nil
local _selectedHandIndex: number? = nil

local _playerUnits: { BattleUnit } = {}
local _botUnits: { BattleUnit } = {}
local _playerBaseHP = BASE_HP
local _botBaseHP = BASE_HP
local _playerBasePart: BasePart = nil :: any
local _botBasePart: BasePart = nil :: any

local _gameOver = false
local _botDeck: { CardData } = {}
local _botNextSpawnTime = 0

-- Arena
local _arenaOrigin = Vector3.new(0, ARENA_Y, 0)
local _arenaFolder: Folder = nil :: any
local _projectileFolder: Folder = nil :: any

-- UI refs
local _statusLabel: TextLabel = nil :: any
local _promptBox: TextBox = nil :: any
local _createBtn: TextButton = nil :: any
local _battleBtn: TextButton = nil :: any
local _deckFrame: Frame = nil :: any
local _handFrame: Frame = nil :: any
local _elixirBar: Frame = nil :: any
local _elixirFill: Frame = nil :: any
local _elixirLabel: TextLabel = nil :: any
local _playerHPLabel: TextLabel = nil :: any
local _botHPLabel: TextLabel = nil :: any
local _nextCardFrame: Frame = nil :: any
local _gameOverLabel: TextLabel = nil :: any
local _deckBuildPanel: Frame = nil :: any
local _battlePanel: Frame = nil :: any

-- Tracked instances + connections
local _instances: { Instance } = {}
local _connections: { RBXScriptConnection } = {}

-- Forward declarations
local createCard: () -> ()
local startBattle: () -> ()
local refreshDeckUI: () -> ()
local refreshHandUI: () -> ()
local spawnPlayerUnit: (card: CardData, pos: Vector3) -> ()

-- Helpers

local function setStatus(text: string, color: Color3?)
	if _statusLabel then
		_statusLabel.Text = text
		_statusLabel.TextColor3 = color or COLORS.textDim
		task.delay(5, function()
			if _statusLabel and _statusLabel.Text == text then
				_statusLabel.Text = ""
			end
		end)
	end
end

local function getPlayer(): Player
	return Players.LocalPlayer
end

local function calcElixirCost(hp: number, atk: number): number
	return math.clamp(math.floor((hp + atk * 2) / 20), 2, 8)
end

local function calcStats(modelData: { [string]: any }): (number, number, number)
	local parts = modelData.parts
	if not parts then
		return 20, 5, 8
	end
	local partCount = #parts
	local totalVolume = 0
	for _, p in ipairs(parts) do
		local s = p.size
		if s then
			local sx = if type(s) == "table" then (s[1] or s.x or 1) else 1
			local sy = if type(s) == "table" then (s[2] or s.y or 1) else 1
			local sz = if type(s) == "table" then (s[3] or s.z or 1) else 1
			totalVolume += sx * sy * sz
		end
	end
	local hp = partCount * 10
	local atk = math.floor(totalVolume + 0.5)
	local speed = math.clamp(12 - partCount, 4, 14)
	return math.max(hp, 10), math.max(atk, 3), speed
end

local function getArenaOrigin(): Vector3
	local char = getPlayer().Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local pos = char.HumanoidRootPart.Position
		return Vector3.new(math.round(pos.X / 4) * 4, ARENA_Y, math.round(pos.Z / 4) * 4 + 20)
	end
	return Vector3.new(0, ARENA_Y, 20)
end

local function deepCopyParts(parts: { any }): { any }
	local copy = {}
	for _, p in ipairs(parts) do
		local pc = {}
		for k, v in pairs(p) do
			if type(v) == "table" then
				local arr = {}
				for _, val in ipairs(v) do
					table.insert(arr, val)
				end
				pc[k] = arr
			else
				pc[k] = v
			end
		end
		table.insert(copy, pc)
	end
	return copy
end

local function shuffleArray<T>(arr: { T }): { T }
	local shuffled = table.clone(arr)
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	return shuffled
end

local VALID_ATTACK_TYPES: { [string]: boolean } = { single = true, splash = true, rapid = true, piercing = true }
local VALID_TARGET_PRIORITIES: { [string]: boolean } =
	{ nearest = true, weakest = true, strongest = true, fastest = true }
local VALID_DEFENSE_TYPES: { [string]: boolean } = { none = true, armor = true, dodge = true, regen = true }
local RANDOM_ATTACK_TYPES: { AttackType } = { "single", "splash", "rapid", "piercing" }
local RANDOM_TARGET_PRIORITIES: { TargetPriority } = { "nearest", "weakest", "strongest", "fastest" }
local RANDOM_DEFENSE_TYPES: { DefenseType } = { "none", "armor", "dodge", "regen" }

local function sanitizeAttackType(v: string?): AttackType
	if v and VALID_ATTACK_TYPES[v] then
		return v :: AttackType
	end
	return RANDOM_ATTACK_TYPES[math.random(1, #RANDOM_ATTACK_TYPES)]
end

local function sanitizeTargetPriority(v: string?): TargetPriority
	if v and VALID_TARGET_PRIORITIES[v] then
		return v :: TargetPriority
	end
	return RANDOM_TARGET_PRIORITIES[math.random(1, #RANDOM_TARGET_PRIORITIES)]
end

local function sanitizeDefenseType(v: string?): DefenseType
	if v and VALID_DEFENSE_TYPES[v] then
		return v :: DefenseType
	end
	return RANDOM_DEFENSE_TYPES[math.random(1, #RANDOM_DEFENSE_TYPES)]
end

local function abbreviateStrategy(at: string, tp: string, dt: string): string
	local atAbbr = ({ single = "sng", splash = "spl", rapid = "rpd", piercing = "prc" })[at] or at
	local dtAbbr = ({ none = "---", armor = "arm", dodge = "ddg", regen = "rgn" })[dt] or dt
	local tpAbbr = ({ nearest = "nr", weakest = "wk", strongest = "st", fastest = "fs" })[tp] or tp
	return atAbbr .. "/" .. tpAbbr .. "/" .. dtAbbr
end

-- ViewportFrame Card Preview

local function createViewportPreview(parent: Frame, modelData: { [string]: any })
	-- Remove old viewport if any
	local old = parent:FindFirstChild("CardViewport")
	if old then
		old:Destroy()
	end

	local vf = Instance.new("ViewportFrame")
	vf.Name = "CardViewport"
	vf.Size = UDim2.new(1, -8, 0.55, 0)
	vf.Position = UDim2.new(0, 4, 0, 4)
	vf.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	vf.BorderSizePixel = 0
	vf.Parent = parent
	local vfCorner = Instance.new("UICorner")
	vfCorner.CornerRadius = UDim.new(0, 4)
	vfCorner.Parent = vf

	-- Clone model into viewport
	local model = OrigamiBuilder.BuildModel(modelData)
	model.Parent = vf

	-- Calculate bounds
	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = maxDim * 1.8

	-- Camera
	local cam = Instance.new("Camera")
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.5, dist * 0.4, dist * 0.7), cf.Position)
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam

	-- Lighting
	vf.LightColor = Color3.new(1, 1, 1)
	vf.LightDirection = Vector3.new(-1, -1, -1)
	vf.Ambient = Color3.fromRGB(120, 120, 140)

	return vf
end

-- HP Bar for Battle Units

local function createHpBar(unit: BattleUnit)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HpBar"
	bb.Size = UDim2.new(0, 40, 0, 6)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = unit.model.PrimaryPart
	bb.Parent = unit.model

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = bb
	local bgc = Instance.new("UICorner")
	bgc.CornerRadius = UDim.new(0, 2)
	bgc.Parent = bg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = if unit.side == "player" then COLORS.success else COLORS.error
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 2)
	fc.Parent = fill

	unit.hpBar = bb
	unit.hpFill = fill
end

local function updateHpBar(unit: BattleUnit)
	if unit.hpFill then
		local pct = math.clamp(unit.hp / unit.maxHp, 0, 1)
		unit.hpFill.Size = UDim2.new(pct, 0, 1, 0)
		if pct < 0.3 then
			unit.hpFill.BackgroundColor3 = COLORS.error
		elseif pct < 0.6 then
			unit.hpFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
		end
	end
end

-- UI Helpers

local function makeFrame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.bg or COLORS.bg
	f.BorderSizePixel = 0
	f.Size = props.size or UDim2.new(0, 100, 0, 30)
	f.Position = props.position or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = props.anchor or Vector2.new(0, 0)
	if props.corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.corner)
		c.Parent = f
	end
	if props.parent then
		f.Parent = props.parent
	end
	return f
end

local function makeLabel(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = props.size or UDim2.new(1, 0, 1, 0)
	l.Position = props.position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = props.anchor or Vector2.new(0, 0)
	l.Font = Enum.Font.GothamBold
	l.TextSize = props.textSize or 14
	l.TextColor3 = props.color or COLORS.text
	l.Text = props.text or ""
	l.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	l.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	l.TextWrapped = if props.wrapped ~= nil then props.wrapped else false
	if props.parent then
		l.Parent = props.parent
	end
	return l
end

local function makeButton(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = props.bg or COLORS.accent
	b.BorderSizePixel = 0
	b.Size = props.size or UDim2.new(0, 100, 0, 36)
	b.Position = props.position or UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = props.anchor or Vector2.new(0, 0)
	b.Font = Enum.Font.GothamBold
	b.TextSize = props.textSize or 14
	b.TextColor3 = props.textColor or COLORS.text
	b.Text = props.text or "Button"
	b.AutoButtonColor = true
	if props.corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.corner)
		c.Parent = b
	end
	if props.parent then
		b.Parent = props.parent
	end
	return b
end

-- Deck Building UI

local function createDeckCardFrame(parent: Frame, index: number, card: CardData?): Frame
	local cardFrame = makeFrame({
		bg = if card then COLORS.bgLight else Color3.fromRGB(35, 35, 45),
		size = UDim2.new(0, 110, 0, 150),
		corner = 6,
		parent = parent,
	})

	if card then
		-- ViewportFrame preview
		createViewportPreview(cardFrame, card.modelData)

		-- Name
		makeLabel({
			text = card.name,
			size = UDim2.new(1, -8, 0, 14),
			position = UDim2.new(0, 4, 0.56, 2),
			textSize = 11,
			color = COLORS.text,
			alignX = Enum.TextXAlignment.Left,
			parent = cardFrame,
		})

		-- Stats
		makeLabel({
			text = "HP:" .. card.hp .. " ATK:" .. card.atk,
			size = UDim2.new(1, -8, 0, 12),
			position = UDim2.new(0, 4, 0.56, 18),
			textSize = 10,
			color = COLORS.textDim,
			alignX = Enum.TextXAlignment.Left,
			parent = cardFrame,
		})

		-- Strategy abbreviation
		makeLabel({
			text = abbreviateStrategy(card.attackType, card.targetPriority, card.defenseType),
			size = UDim2.new(1, -8, 0, 12),
			position = UDim2.new(0, 4, 0.56, 32),
			textSize = 9,
			color = COLORS.accentDim,
			alignX = Enum.TextXAlignment.Left,
			parent = cardFrame,
		})

		-- Elixir cost badge (top-right)
		local badge = makeFrame({
			bg = COLORS.elixir,
			size = UDim2.new(0, 22, 0, 22),
			position = UDim2.new(1, -4, 0, 4),
			anchor = Vector2.new(1, 0),
			corner = 11,
			parent = cardFrame,
		})
		makeLabel({
			text = tostring(card.elixirCost),
			size = UDim2.new(1, 0, 1, 0),
			textSize = 12,
			color = COLORS.text,
			parent = badge,
		})

		-- Speed
		makeLabel({
			text = "SPD:" .. card.speed,
			size = UDim2.new(1, -8, 0, 12),
			position = UDim2.new(0, 4, 1, -16),
			textSize = 9,
			color = COLORS.textDim,
			alignX = Enum.TextXAlignment.Left,
			parent = cardFrame,
		})
	else
		-- Empty slot
		makeLabel({
			text = tostring(index),
			size = UDim2.new(1, 0, 1, 0),
			textSize = 24,
			color = COLORS.disabled,
			parent = cardFrame,
		})
	end

	return cardFrame
end

refreshDeckUI = function()
	if not _deckFrame then
		return
	end

	-- Clear children except layout
	for _, child in ipairs(_deckFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for i = 1, MAX_DECK_SIZE do
		createDeckCardFrame(_deckFrame, i, _deck[i])
	end

	-- Update battle button
	if _battleBtn then
		local canBattle = #_deck >= MIN_DECK_FOR_BATTLE
		_battleBtn.BackgroundColor3 = if canBattle then COLORS.success else COLORS.disabled
		_battleBtn.Text = if canBattle
			then "Battle! (" .. #_deck .. "/" .. MAX_DECK_SIZE .. ")"
			else "Need " .. MIN_DECK_FOR_BATTLE .. "+ cards"
	end
end

-- Battle Hand UI

local function createHandCardFrame(parent: Frame, index: number, card: CardData): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "HandCard_" .. index
	btn.Size = UDim2.new(0, 90, 0, 130)
	btn.BackgroundColor3 = if _selectedHandIndex == index then COLORS.accent else COLORS.bgLight
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = true
	btn.Parent = parent
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	-- Can afford?
	local canAfford = _playerElixir >= card.elixirCost
	if not canAfford and _selectedHandIndex ~= index then
		btn.BackgroundColor3 = Color3.fromRGB(35, 30, 35)
	end

	-- ViewportFrame preview
	createViewportPreview(btn, card.modelData)

	-- Name
	makeLabel({
		text = card.name,
		size = UDim2.new(1, -4, 0, 12),
		position = UDim2.new(0, 2, 0.56, 2),
		textSize = 9,
		color = COLORS.text,
		alignX = Enum.TextXAlignment.Left,
		wrapped = true,
		parent = btn,
	})

	-- Stats
	makeLabel({
		text = "HP:" .. card.hp .. " ATK:" .. card.atk,
		size = UDim2.new(1, -4, 0, 10),
		position = UDim2.new(0, 2, 0.56, 16),
		textSize = 8,
		color = COLORS.textDim,
		alignX = Enum.TextXAlignment.Left,
		parent = btn,
	})

	-- Strategy
	makeLabel({
		text = abbreviateStrategy(card.attackType, card.targetPriority, card.defenseType),
		size = UDim2.new(1, -4, 0, 10),
		position = UDim2.new(0, 2, 1, -14),
		textSize = 8,
		color = COLORS.accentDim,
		alignX = Enum.TextXAlignment.Left,
		parent = btn,
	})

	-- Elixir badge
	local badge = makeFrame({
		bg = if canAfford then COLORS.elixir else COLORS.disabled,
		size = UDim2.new(0, 18, 0, 18),
		position = UDim2.new(1, -2, 0, 2),
		anchor = Vector2.new(1, 0),
		corner = 9,
		parent = btn,
	})
	makeLabel({
		text = tostring(card.elixirCost),
		size = UDim2.new(1, 0, 1, 0),
		textSize = 10,
		color = COLORS.text,
		parent = badge,
	})

	return btn
end

refreshHandUI = function()
	if not _handFrame then
		return
	end

	for _, child in ipairs(_handFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for i, card in ipairs(_hand) do
		local btn = createHandCardFrame(_handFrame, i, card)
		btn.Activated:Connect(function()
			if _gameOver then
				return
			end
			if _selectedHandIndex == i then
				_selectedHandIndex = nil
			else
				-- Only select if affordable
				if _playerElixir >= card.elixirCost then
					_selectedHandIndex = i
				else
					setStatus("Not enough elixir! Need " .. card.elixirCost, COLORS.elixir)
				end
			end
			refreshHandUI()
		end)
	end

	-- Update next card preview
	if _nextCardFrame then
		for _, child in ipairs(_nextCardFrame:GetChildren()) do
			if not child:IsA("UICorner") then
				child:Destroy()
			end
		end

		if _nextCard then
			makeLabel({
				text = "NEXT",
				size = UDim2.new(1, 0, 0, 12),
				position = UDim2.new(0, 0, 0, 2),
				textSize = 8,
				color = COLORS.textDim,
				parent = _nextCardFrame,
			})
			createViewportPreview(_nextCardFrame, _nextCard.modelData)
			-- Shift viewport down for "NEXT" label
			local vf = _nextCardFrame:FindFirstChild("CardViewport")
			if vf then
				vf.Position = UDim2.new(0, 4, 0, 16)
				vf.Size = UDim2.new(1, -8, 1, -20)
			end
		else
			makeLabel({
				text = "---",
				size = UDim2.new(1, 0, 1, 0),
				textSize = 12,
				color = COLORS.disabled,
				parent = _nextCardFrame,
			})
		end
	end
end

local function updateElixirUI()
	if _elixirFill then
		local pct = math.clamp(_playerElixir / MAX_ELIXIR, 0, 1)
		_elixirFill.Size = UDim2.new(pct, 0, 1, 0)
	end
	if _elixirLabel then
		_elixirLabel.Text = math.floor(_playerElixir) .. "/" .. MAX_ELIXIR
	end
end

local function updateBaseHPUI()
	if _playerHPLabel then
		_playerHPLabel.Text = "YOU: " .. math.ceil(_playerBaseHP)
		_playerHPLabel.TextColor3 = if _playerBaseHP <= 30 then COLORS.error else COLORS.playerBase
	end
	if _botHPLabel then
		_botHPLabel.Text = "BOT: " .. math.ceil(_botBaseHP)
		_botHPLabel.TextColor3 = if _botBaseHP <= 30 then COLORS.success else COLORS.botBase
	end
end

-- UI Creation

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "CardBattlerGui"
	_gui.DisplayOrder = 15
	_gui.ResetOnSpawn = false
	_gui.Enabled = false
	_gui.Parent = getPlayer():WaitForChild("PlayerGui")
	table.insert(_instances, _gui)

	-- Status label (shared between phases)
	_statusLabel = makeLabel({
		text = "",
		size = UDim2.new(0, 400, 0, 24),
		position = UDim2.new(0.5, 0, 0, 4),
		anchor = Vector2.new(0.5, 0),
		color = COLORS.textDim,
		textSize = 14,
		parent = _gui,
	})

	-- DECK BUILDING PANEL
	_deckBuildPanel = makeFrame({
		bg = Color3.fromRGB(0, 0, 0),
		size = UDim2.new(1, 0, 1, 0),
		parent = _gui,
	})
	_deckBuildPanel.BackgroundTransparency = 0.3

	-- Title
	makeLabel({
		text = "BUILD YOUR DECK",
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.new(0, 0, 0, 30),
		textSize = 20,
		color = COLORS.accent,
		parent = _deckBuildPanel,
	})

	-- Deck grid (4x2)
	_deckFrame = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(0, 480, 0, 340),
		position = UDim2.new(0.5, 0, 0.5, -30),
		anchor = Vector2.new(0.5, 0.5),
		corner = 8,
		parent = _deckBuildPanel,
	})
	local deckPad = Instance.new("UIPadding")
	deckPad.PaddingLeft = UDim.new(0, 8)
	deckPad.PaddingTop = UDim.new(0, 8)
	deckPad.Parent = _deckFrame

	local deckLayout = Instance.new("UIGridLayout")
	deckLayout.CellSize = UDim2.new(0, 110, 0, 150)
	deckLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	deckLayout.FillDirection = Enum.FillDirection.Horizontal
	deckLayout.SortOrder = Enum.SortOrder.LayoutOrder
	deckLayout.Parent = _deckFrame

	-- Prompt row at bottom
	local promptRow = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(0, 500, 0, 40),
		position = UDim2.new(0.5, 0, 1, -55),
		anchor = Vector2.new(0.5, 0),
		parent = _deckBuildPanel,
	})
	local promptLayout = Instance.new("UIListLayout")
	promptLayout.FillDirection = Enum.FillDirection.Horizontal
	promptLayout.Padding = UDim.new(0, 6)
	promptLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	promptLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	promptLayout.Parent = promptRow

	_promptBox = Instance.new("TextBox")
	_promptBox.Size = UDim2.new(0, 260, 0, 36)
	_promptBox.BackgroundColor3 = COLORS.bgLight
	_promptBox.BorderSizePixel = 0
	_promptBox.Font = Enum.Font.Gotham
	_promptBox.TextSize = 14
	_promptBox.TextColor3 = COLORS.text
	_promptBox.PlaceholderText = "Describe a creature..."
	_promptBox.PlaceholderColor3 = COLORS.textDim
	_promptBox.ClearTextOnFocus = false
	_promptBox.Parent = promptRow
	local pCorner = Instance.new("UICorner")
	pCorner.CornerRadius = UDim.new(0, 6)
	pCorner.Parent = _promptBox
	local pPad = Instance.new("UIPadding")
	pPad.PaddingLeft = UDim.new(0, 8)
	pPad.PaddingRight = UDim.new(0, 8)
	pPad.Parent = _promptBox

	_createBtn = makeButton({
		text = "Create Card",
		bg = COLORS.accent,
		size = UDim2.new(0, 110, 0, 36),
		corner = 6,
		parent = promptRow,
	})

	_battleBtn = makeButton({
		text = "Need " .. MIN_DECK_FOR_BATTLE .. "+ cards",
		bg = COLORS.disabled,
		size = UDim2.new(0, 110, 0, 36),
		corner = 6,
		parent = promptRow,
	})

	-- Wire deck building buttons
	_createBtn.Activated:Connect(function()
		if _phase ~= "deck_building" then
			return
		end
		createCard()
	end)

	_battleBtn.Activated:Connect(function()
		if _phase ~= "deck_building" then
			return
		end
		if #_deck >= MIN_DECK_FOR_BATTLE then
			startBattle()
		end
	end)

	_promptBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and _phase == "deck_building" then
			createCard()
		end
	end)

	-- BATTLE PANEL
	_battlePanel = makeFrame({
		bg = Color3.fromRGB(0, 0, 0),
		size = UDim2.new(1, 0, 1, 0),
		parent = _gui,
	})
	_battlePanel.BackgroundTransparency = 0.8
	_battlePanel.Visible = false

	-- Top bar: base HPs + elixir
	local topBar = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.new(0, 0, 0, 0),
		parent = _battlePanel,
	})

	_playerHPLabel = makeLabel({
		text = "YOU: " .. BASE_HP,
		size = UDim2.new(0, 100, 1, 0),
		position = UDim2.new(0, 10, 0, 0),
		color = COLORS.playerBase,
		textSize = 16,
		alignX = Enum.TextXAlignment.Left,
		parent = topBar,
	})

	-- Elixir bar (center)
	_elixirBar = makeFrame({
		bg = COLORS.elixirBg,
		size = UDim2.new(0, 240, 0, 20),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		corner = 4,
		parent = topBar,
	})
	_elixirFill = makeFrame({
		bg = COLORS.elixir,
		size = UDim2.new(0.5, 0, 1, 0),
		corner = 4,
		parent = _elixirBar,
	})
	_elixirLabel = makeLabel({
		text = "5/10",
		size = UDim2.new(1, 0, 1, 0),
		textSize = 12,
		color = COLORS.text,
		parent = _elixirBar,
	})

	_botHPLabel = makeLabel({
		text = "BOT: " .. BASE_HP,
		size = UDim2.new(0, 100, 1, 0),
		position = UDim2.new(1, -10, 0, 0),
		anchor = Vector2.new(1, 0),
		color = COLORS.botBase,
		textSize = 16,
		alignX = Enum.TextXAlignment.Right,
		parent = topBar,
	})

	-- Hand + next card at bottom
	local bottomBar = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(1, 0, 0, 145),
		position = UDim2.new(0, 0, 1, -145),
		parent = _battlePanel,
	})

	-- Next card preview
	_nextCardFrame = makeFrame({
		bg = Color3.fromRGB(35, 35, 50),
		size = UDim2.new(0, 60, 0, 80),
		position = UDim2.new(0, 10, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		corner = 6,
		parent = bottomBar,
	})

	-- Hand frame
	_handFrame = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(0, 400, 0, 135),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		parent = bottomBar,
	})
	local handLayout = Instance.new("UIListLayout")
	handLayout.FillDirection = Enum.FillDirection.Horizontal
	handLayout.Padding = UDim.new(0, 6)
	handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	handLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	handLayout.Parent = _handFrame

	-- Game over overlay
	_gameOverLabel = makeLabel({
		text = "",
		size = UDim2.new(0, 400, 0, 80),
		position = UDim2.new(0.5, 0, 0.4, 0),
		anchor = Vector2.new(0.5, 0.5),
		textSize = 40,
		color = COLORS.text,
		parent = _battlePanel,
	})
	_gameOverLabel.Visible = false
end

-- Arena (3D)

local function createArena()
	_arenaOrigin = getArenaOrigin()

	_arenaFolder = Instance.new("Folder")
	_arenaFolder.Name = "CB_Arena"
	_arenaFolder.Parent = Workspace
	table.insert(_instances, _arenaFolder)

	_projectileFolder = Instance.new("Folder")
	_projectileFolder.Name = "CB_Projectiles"
	_projectileFolder.Parent = Workspace
	table.insert(_instances, _projectileFolder)

	-- Ground lane
	local ground = Instance.new("Part")
	ground.Name = "ArenaGround"
	ground.Anchored = true
	ground.CanCollide = false
	ground.Size = Vector3.new(ARENA_HALF_LENGTH * 2 + 10, 0.2, 14)
	ground.Position = _arenaOrigin
	ground.Material = Enum.Material.SmoothPlastic
	ground.Color = Color3.fromRGB(50, 50, 60)
	ground.Transparency = 0.4
	ground.Parent = _arenaFolder

	-- Player base
	_playerBasePart = Instance.new("Part")
	_playerBasePart.Name = "PlayerBase"
	_playerBasePart.Anchored = true
	_playerBasePart.CanCollide = false
	_playerBasePart.Size = BASE_SIZE
	_playerBasePart.Position = _arenaOrigin + Vector3.new(-ARENA_HALF_LENGTH, BASE_SIZE.Y / 2, 0)
	_playerBasePart.Material = Enum.Material.SmoothPlastic
	_playerBasePart.Color = COLORS.playerBase
	_playerBasePart.Transparency = 0.2
	_playerBasePart.Parent = _arenaFolder

	-- Player base label
	local pbb = Instance.new("BillboardGui")
	pbb.Size = UDim2.new(0, 60, 0, 20)
	pbb.StudsOffset = Vector3.new(0, 5, 0)
	pbb.AlwaysOnTop = true
	pbb.Adornee = _playerBasePart
	pbb.Parent = _playerBasePart
	local pbl = Instance.new("TextLabel")
	pbl.Size = UDim2.new(1, 0, 1, 0)
	pbl.BackgroundTransparency = 1
	pbl.Text = "YOUR BASE"
	pbl.TextColor3 = COLORS.playerBase
	pbl.Font = Enum.Font.GothamBold
	pbl.TextSize = 14
	pbl.Parent = pbb

	-- Bot base
	_botBasePart = Instance.new("Part")
	_botBasePart.Name = "BotBase"
	_botBasePart.Anchored = true
	_botBasePart.CanCollide = false
	_botBasePart.Size = BASE_SIZE
	_botBasePart.Position = _arenaOrigin + Vector3.new(ARENA_HALF_LENGTH, BASE_SIZE.Y / 2, 0)
	_botBasePart.Material = Enum.Material.SmoothPlastic
	_botBasePart.Color = COLORS.botBase
	_botBasePart.Transparency = 0.2
	_botBasePart.Parent = _arenaFolder

	local bbb = Instance.new("BillboardGui")
	bbb.Size = UDim2.new(0, 60, 0, 20)
	bbb.StudsOffset = Vector3.new(0, 5, 0)
	bbb.AlwaysOnTop = true
	bbb.Adornee = _botBasePart
	bbb.Parent = _botBasePart
	local bbl = Instance.new("TextLabel")
	bbl.Size = UDim2.new(1, 0, 1, 0)
	bbl.BackgroundTransparency = 1
	bbl.Text = "BOT BASE"
	bbl.TextColor3 = COLORS.botBase
	bbl.Font = Enum.Font.GothamBold
	bbl.TextSize = 14
	bbl.Parent = bbb

	-- Click detector on arena ground for unit placement
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 80
	click.Parent = ground
	click.MouseClick:Connect(function(_player, position: Vector3?)
		-- ClickDetector doesn't give position; we use mouse instead
	end)

	-- Place units via mouse click on arena
	local mouse = getPlayer():GetMouse()
	table.insert(
		_connections,
		mouse.Button1Down:Connect(function()
			if _phase ~= "battle" or _gameOver then
				return
			end
			if not _selectedHandIndex or not _hand[_selectedHandIndex] then
				return
			end

			local card = _hand[_selectedHandIndex]
			if _playerElixir < card.elixirCost then
				setStatus("Not enough elixir!", COLORS.elixir)
				return
			end

			-- Check click is on player's half of arena
			local target = mouse.Target
			if not target then
				return
			end

			local hitPos = mouse.Hit.Position
			local localX = hitPos.X - _arenaOrigin.X

			-- Player can only place on left half
			if localX > 0 then
				setStatus("Place on YOUR side!", COLORS.error)
				return
			end

			-- Spawn unit
			_playerElixir -= card.elixirCost
			updateElixirUI()

			local spawnPos = Vector3.new(hitPos.X, _arenaOrigin.Y + 1.5, _arenaOrigin.Z)
			spawnPlayerUnit(card, spawnPos)

			-- Remove from hand, draw next
			table.remove(_hand, _selectedHandIndex)
			_selectedHandIndex = nil

			if _nextCard then
				table.insert(_hand, _nextCard)
				_nextCard = nil
			end
			if #_drawPile > 0 then
				_nextCard = table.remove(_drawPile, 1)
			end

			refreshHandUI()
		end)
	)
end

-- Unit Spawning

local function spawnUnit(card: CardData, pos: Vector3, side: string): BattleUnit
	local model = OrigamiBuilder.BuildModel(card.modelData)
	model.Parent = _arenaFolder

	if model.PrimaryPart then
		model:PivotTo(CFrame.new(pos))
	end

	OrigamiBuilder.ApplyAnimation(model, card.modelData.animation or "idle_bob")

	local unit: BattleUnit = {
		model = model,
		card = card,
		hp = card.hp,
		maxHp = card.hp,
		position = pos,
		side = side,
		alive = true,
		_lastAttack = 0,
		hpBar = nil,
		hpFill = nil,
	}

	createHpBar(unit)

	if side == "player" then
		table.insert(_playerUnits, unit)
	else
		table.insert(_botUnits, unit)
	end

	return unit
end

-- Forward declare assignment for arena click handler
spawnPlayerUnit = function(card: CardData, pos: Vector3)
	spawnUnit(card, pos, "player")
end

-- Combat System

local function findTarget(unit: BattleUnit, targets: { BattleUnit }): BattleUnit?
	local unitPos = unit.position
	local priority = unit.card.targetPriority
	local best: BattleUnit? = nil
	local bestScore = math.huge

	for _, target in targets do
		if target.alive then
			local dist = (target.position - unitPos).Magnitude

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
				local score = -target.card.speed
				if score < bestScore then
					bestScore = score
					best = target
				end
			end
		end
	end

	return best
end

local function killUnit(unit: BattleUnit)
	unit.alive = false
	if unit.model and unit.model.Parent then
		unit.model:Destroy()
	end
end

local function dealDamage(attacker: BattleUnit, target: BattleUnit)
	if not target.alive then
		return
	end

	if target.card.defenseType == "dodge" then
		if math.random() < DODGE_CHANCE then
			return
		end
	end

	local dmg = attacker.card.atk
	if target.card.defenseType == "armor" and attacker.card.attackType ~= "piercing" then
		dmg = dmg * (1 - ARMOR_REDUCTION)
	end

	target.hp -= dmg
	updateHpBar(target)

	if target.hp <= 0 then
		killUnit(target)
	end
end

local function fireProjectile(from: Vector3, targetUnit: BattleUnit, attacker: BattleUnit, targetList: { BattleUnit })
	local proj = Instance.new("Part")
	proj.Shape = Enum.PartType.Ball
	proj.Size = if attacker.card.attackType == "splash" then Vector3.new(1.5, 1.5, 1.5) else Vector3.new(0.8, 0.8, 0.8)
	proj.Position = from + Vector3.new(0, 2, 0)
	proj.Anchored = true
	proj.CanCollide = false
	proj.Material = Enum.Material.Neon
	proj.Color = if attacker.side == "player" then COLORS.playerBase else COLORS.botBase
	proj.Parent = _projectileFolder

	task.spawn(function()
		local startPos = proj.Position
		local elapsed = 0
		local targetPos = targetUnit.position + Vector3.new(0, 1.5, 0)

		while elapsed < PROJECTILE_SPEED and proj.Parent do
			elapsed += task.wait()
			local t = math.min(elapsed / PROJECTILE_SPEED, 1)
			-- Update target pos if still alive
			if targetUnit.alive then
				targetPos = targetUnit.position + Vector3.new(0, 1.5, 0)
			end
			proj.Position = startPos:Lerp(targetPos, t)
		end

		-- Impact
		if attacker.card.attackType == "splash" then
			local impactPos = proj.Position
			for _, other in targetList do
				if other.alive then
					local dist = (other.position - impactPos).Magnitude
					if dist <= SPLASH_RADIUS then
						dealDamage(attacker, other)
					end
				end
			end
		elseif attacker.card.attackType == "rapid" then
			local origAtk = attacker.card.atk
			attacker.card.atk = math.floor(origAtk * 0.6)
			dealDamage(attacker, targetUnit)
			if targetUnit.alive then
				dealDamage(attacker, targetUnit)
			end
			attacker.card.atk = origAtk
		else
			-- single / piercing
			dealDamage(attacker, targetUnit)
		end

		if proj.Parent then
			proj:Destroy()
		end
	end)
end

local function applyRegen(units: { BattleUnit })
	for _, unit in units do
		if unit.alive and unit.card.defenseType == "regen" and unit.hp < unit.maxHp then
			unit.hp = math.min(unit.maxHp, unit.hp + REGEN_PER_TICK * 0.016) -- per frame at ~60fps
			updateHpBar(unit)
		end
	end
end

-- Bot AI

local function buildBotDeck(): { CardData }
	local deck: { CardData } = {}
	local shuffled = shuffleArray(ENEMY_TEMPLATES)
	for i = 1, MAX_DECK_SIZE do
		local template = shuffled[((i - 1) % #shuffled) + 1]
		local parts = deepCopyParts(template.parts)
		local card: CardData = {
			name = template.name,
			hp = template.hp,
			atk = template.atk,
			speed = template.speed,
			elixirCost = calcElixirCost(template.hp, template.atk),
			modelData = { name = template.name, parts = parts, animation = "idle_bob" },
			attackType = template.attackType,
			targetPriority = template.targetPriority,
			defenseType = template.defenseType,
		}
		table.insert(deck, card)
	end
	return deck
end

local function botTrySpawn()
	if _gameOver or #_botDeck == 0 then
		return
	end

	local now = os.clock()
	if now < _botNextSpawnTime then
		return
	end

	-- Pick a random affordable card from bot deck
	local affordable = {}
	for i, card in ipairs(_botDeck) do
		if _botElixir >= card.elixirCost then
			table.insert(affordable, { index = i, card = card })
		end
	end

	if #affordable == 0 then
		return
	end

	local pick = affordable[math.random(1, #affordable)]
	_botElixir -= pick.card.elixirCost

	-- Spawn on bot's half (right side) at random Z offset
	local spawnX = _arenaOrigin.X + math.random(10, ARENA_HALF_LENGTH - 10)
	local spawnZ = _arenaOrigin.Z + math.random(-4, 4)
	local spawnPos = Vector3.new(spawnX, _arenaOrigin.Y + 1.5, spawnZ)

	spawnUnit(pick.card, spawnPos, "bot")

	-- Cycle card to back of deck
	local removed = table.remove(_botDeck, pick.index)
	table.insert(_botDeck, removed)

	_botNextSpawnTime = now + math.random(BOT_SPAWN_MIN, BOT_SPAWN_MAX)
end

-- Main Battle Loop

local function cleanDeadUnits(units: { BattleUnit }): { BattleUnit }
	local alive = {}
	for _, unit in units do
		if unit.alive then
			table.insert(alive, unit)
		end
	end
	return alive
end

local function startBattleLoop()
	local conn = RunService.Heartbeat:Connect(function(dt)
		if not _active or _phase ~= "battle" or _gameOver then
			return
		end

		-- Elixir regen
		_playerElixir = math.min(MAX_ELIXIR, _playerElixir + ELIXIR_REGEN_RATE * dt)
		_botElixir = math.min(MAX_ELIXIR, _botElixir + ELIXIR_REGEN_RATE * dt)
		updateElixirUI()

		-- Regen defense
		applyRegen(_playerUnits)
		applyRegen(_botUnits)

		-- Bot AI
		botTrySpawn()

		local now = os.clock()

		-- Process player units
		for _, unit in _playerUnits do
			if not unit.alive then
				continue
			end

			-- Find target enemy
			local target = findTarget(unit, _botUnits)
			local inCombat = false

			if target and target.alive then
				local dist = (target.position - unit.position).Magnitude
				if dist <= ATTACK_RANGE then
					-- Attack
					inCombat = true
					local cooldown = if unit.card.attackType == "rapid" then ATTACK_COOLDOWN * 0.5 else ATTACK_COOLDOWN
					if now - unit._lastAttack >= cooldown then
						unit._lastAttack = now
						fireProjectile(unit.position, target, unit, _botUnits)
					end
				end
			end

			if not inCombat then
				-- Walk toward bot base
				local targetX = _arenaOrigin.X + ARENA_HALF_LENGTH
				local moveDir = Vector3.new(1, 0, 0)
				-- Also move Z toward arena center
				local zDiff = _arenaOrigin.Z - unit.position.Z
				if math.abs(zDiff) > 1 then
					moveDir = Vector3.new(1, 0, zDiff > 0 and 0.3 or -0.3).Unit
				end

				local newPos = unit.position + moveDir * unit.card.speed * dt
				unit.position = newPos

				if unit.model and unit.model.PrimaryPart then
					unit.model:PivotTo(CFrame.lookAt(newPos, newPos + moveDir))
				end

				-- Check if reached bot base
				if unit.position.X >= _arenaOrigin.X + ARENA_HALF_LENGTH - UNIT_REACH_BASE_DIST then
					_botBaseHP -= unit.card.atk
					updateBaseHPUI()
					killUnit(unit)

					if _botBaseHP <= 0 then
						_botBaseHP = 0
						_gameOver = true
						updateBaseHPUI()
						if _gameOverLabel then
							_gameOverLabel.Text = "VICTORY!"
							_gameOverLabel.TextColor3 = COLORS.success
							_gameOverLabel.Visible = true
						end
						return
					end
				end
			end
		end

		-- Process bot units
		for _, unit in _botUnits do
			if not unit.alive then
				continue
			end

			local target = findTarget(unit, _playerUnits)
			local inCombat = false

			if target and target.alive then
				local dist = (target.position - unit.position).Magnitude
				if dist <= ATTACK_RANGE then
					inCombat = true
					local cooldown = if unit.card.attackType == "rapid" then ATTACK_COOLDOWN * 0.5 else ATTACK_COOLDOWN
					if now - unit._lastAttack >= cooldown then
						unit._lastAttack = now
						fireProjectile(unit.position, target, unit, _playerUnits)
					end
				end
			end

			if not inCombat then
				-- Walk toward player base
				local moveDir = Vector3.new(-1, 0, 0)
				local zDiff = _arenaOrigin.Z - unit.position.Z
				if math.abs(zDiff) > 1 then
					moveDir = Vector3.new(-1, 0, zDiff > 0 and 0.3 or -0.3).Unit
				end

				local newPos = unit.position + moveDir * unit.card.speed * dt
				unit.position = newPos

				if unit.model and unit.model.PrimaryPart then
					unit.model:PivotTo(CFrame.lookAt(newPos, newPos + moveDir))
				end

				-- Check if reached player base
				if unit.position.X <= _arenaOrigin.X - ARENA_HALF_LENGTH + UNIT_REACH_BASE_DIST then
					_playerBaseHP -= unit.card.atk
					updateBaseHPUI()
					killUnit(unit)

					if _playerBaseHP <= 0 then
						_playerBaseHP = 0
						_gameOver = true
						updateBaseHPUI()
						if _gameOverLabel then
							_gameOverLabel.Text = "DEFEAT!"
							_gameOverLabel.TextColor3 = COLORS.error
							_gameOverLabel.Visible = true
						end
						return
					end
				end
			end
		end

		-- Clean dead units
		_playerUnits = cleanDeadUnits(_playerUnits)
		_botUnits = cleanDeadUnits(_botUnits)

		-- Periodically refresh hand UI for elixir affordability
		-- (throttle to avoid lag)
		if math.floor(now * 2) ~= math.floor((now - dt) * 2) then
			refreshHandUI()
		end
	end)
	table.insert(_connections, conn)
end

-- Card Creation (Deck Building)

createCard = function()
	local prompt = _promptBox.Text
	if prompt == "" then
		setStatus("Type a creature description first!", COLORS.error)
		return
	end
	if #_deck >= MAX_DECK_SIZE then
		setStatus("Deck is full!", COLORS.error)
		return
	end

	_createBtn.Text = "Creating..."
	_createBtn.BackgroundColor3 = COLORS.disabled
	setStatus("Generating creature...", COLORS.accent)

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "creature", "origami", nil, "card"):await()

		if _createBtn then
			_createBtn.Text = "Create Card"
			_createBtn.BackgroundColor3 = COLORS.accent
		end

		if ok and result and result.success and result.model then
			local modelData = result.model
			local hp, atk, speed = calcStats(modelData)
			local elixirCost = calcElixirCost(hp, atk)

			local card: CardData = {
				name = modelData.name or "Creature",
				hp = hp,
				atk = atk,
				speed = speed,
				elixirCost = elixirCost,
				modelData = modelData,
				attackType = sanitizeAttackType(modelData.attackType),
				targetPriority = sanitizeTargetPriority(modelData.targetPriority),
				defenseType = sanitizeDefenseType(modelData.defenseType),
			}

			table.insert(_deck, card)
			_promptBox.Text = ""
			refreshDeckUI()
			setStatus(card.name .. " added! (E:" .. elixirCost .. " HP:" .. hp .. " ATK:" .. atk .. ")", COLORS.success)
		else
			local errMsg = if result and result.error then result.error else "Generation failed"
			setStatus("Error: " .. errMsg, COLORS.error)
		end
	end)
end

-- Phase Transition

startBattle = function()
	_phase = "battle"

	-- Hide deck building, show battle
	if _deckBuildPanel then
		_deckBuildPanel.Visible = false
	end
	if _battlePanel then
		_battlePanel.Visible = true
	end

	-- Set up arena
	createArena()

	-- Init battle state
	_playerElixir = 5.0
	_botElixir = 5.0
	_playerBaseHP = BASE_HP
	_botBaseHP = BASE_HP
	_playerUnits = {}
	_botUnits = {}
	_gameOver = false

	-- Shuffle player deck into draw pile, draw hand
	_drawPile = shuffleArray(_deck)
	_hand = {}
	for _ = 1, math.min(4, #_drawPile) do
		table.insert(_hand, table.remove(_drawPile, 1))
	end
	if #_drawPile > 0 then
		_nextCard = table.remove(_drawPile, 1)
	end

	-- Build bot deck
	_botDeck = buildBotDeck()
	_botNextSpawnTime = os.clock() + 2 -- first spawn after 2 sec

	-- Update UI
	updateElixirUI()
	updateBaseHPUI()
	refreshHandUI()
	if _gameOverLabel then
		_gameOverLabel.Visible = false
	end

	setStatus("Battle started! Tap a card, then tap the arena!", COLORS.accent)

	-- Start main loop
	startBattleLoop()
end

-- Activate / Cleanup

function CardBattlerController:Activate()
	if _active then
		return
	end
	_active = true

	-- Reset state
	_phase = "deck_building"
	_deck = {}
	_hand = {}
	_drawPile = {}
	_nextCard = nil
	_selectedHandIndex = nil
	_playerUnits = {}
	_botUnits = {}
	_playerBaseHP = BASE_HP
	_botBaseHP = BASE_HP
	_playerElixir = 5
	_botElixir = 5
	_gameOver = false
	_botDeck = {}

	-- Create UI
	createUI()
	_gui.Enabled = true
	refreshDeckUI()

	setStatus("Create creature cards to build your deck!", COLORS.accent)
end

function CardBattlerController:Cleanup()
	if not _active then
		return
	end
	_active = false

	-- Disconnect all connections
	for _, conn in _connections do
		conn:Disconnect()
	end
	_connections = {}

	-- Destroy all tracked instances
	for _, inst in ipairs(_instances) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	_instances = {}

	-- Clear references
	_gui = nil :: any
	_arenaFolder = nil :: any
	_projectileFolder = nil :: any
	_playerBasePart = nil :: any
	_botBasePart = nil :: any
	_statusLabel = nil :: any
	_promptBox = nil :: any
	_createBtn = nil :: any
	_battleBtn = nil :: any
	_deckFrame = nil :: any
	_handFrame = nil :: any
	_elixirBar = nil :: any
	_elixirFill = nil :: any
	_elixirLabel = nil :: any
	_playerHPLabel = nil :: any
	_botHPLabel = nil :: any
	_nextCardFrame = nil :: any
	_gameOverLabel = nil :: any
	_deckBuildPanel = nil :: any
	_battlePanel = nil :: any

	_deck = {}
	_hand = {}
	_drawPile = {}
	_nextCard = nil
	_selectedHandIndex = nil
	_playerUnits = {}
	_botUnits = {}
end

-- Knit Lifecycle

function CardBattlerController:KnitInit() end

function CardBattlerController:KnitStart()
	GameMode.Changed:Connect(function(newMode: string, oldMode: string)
		if newMode == "card_battler" then
			self:Activate()
		elseif oldMode == "card_battler" then
			self:Cleanup()
		end
	end)
end

return CardBattlerController
