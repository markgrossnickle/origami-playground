--!strict
-- CardBattlerController: 3v3 turn-based card battler using origami creatures
-- Players create creature cards via LLM prompts, place them on a 3x2 field, and battle AI opponents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local CardBattlerController = Knit.CreateController({ Name = "CardBattlerController" })

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

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

local MAX_HAND_SIZE = 5
local FIELD_SLOTS = 3 -- per side
local SLOT_SIZE = 4
local SLOT_HEIGHT = 0.2
local SLOT_GAP = 6 -- center-to-center distance between slots
local FIELD_ROW_GAP = 10 -- distance between player and enemy rows
local FIELD_Y = 0.1 -- ground level for markers

local STARTING_HP = 100

-- Enemy stat scaling
local ENEMY_BASE_HP = 20
local ENEMY_HP_PER_TURN = 10
local ENEMY_BASE_ATK = 5
local ENEMY_ATK_PER_TURN = 3

-- Pre-built enemy creature templates (simple block creatures)
local ENEMY_TEMPLATES = {
	{
		name = "Goblin",
		color = { 80, 200, 80 },
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
		color = { 200, 60, 60 },
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
		color = { 100, 220, 200 },
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
		color = { 140, 120, 100 },
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
}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type CardData = {
	name: string,
	hp: number,
	maxHp: number,
	atk: number,
	modelData: { [string]: any },
	model: Model?,
	isEnemy: boolean,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local _gui: ScreenGui = nil :: any
local _active = false

-- Field state
local _fieldFolder: Folder = nil :: any
local _fieldOrigin = Vector3.new(0, FIELD_Y, 0)
local _slotMarkers: { [string]: Part } = {} -- "player_1", "enemy_2", etc.
local _fieldCards: { [string]: CardData? } = {} -- same keys

-- Hand
local _hand: { CardData } = {}
local _selectedHandIndex: number? = nil

-- HP
local _playerHP = STARTING_HP
local _enemyHP = STARTING_HP
local _turnNumber = 0
local _gameOver = false
local _resolving = false

-- UI references
local _handFrame: Frame = nil :: any
local _playerHPLabel: TextLabel = nil :: any
local _enemyHPLabel: TextLabel = nil :: any
local _turnLabel: TextLabel = nil :: any
local _statusLabel: TextLabel = nil :: any
local _promptBox: TextBox = nil :: any
local _createBtn: TextButton = nil :: any
local _endTurnBtn: TextButton = nil :: any
local _fieldSlotFrames: { [string]: Frame } = {}

-- Tracked instances for cleanup
local _instances: { Instance } = {}

-- Forward declarations
local createCard: () -> ()
local endTurn: () -> ()
local playCardToSlot: (handIndex: number, slotKey: string) -> ()

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

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

local function getFieldOrigin(): Vector3
	local char = getPlayer().Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local pos = char.HumanoidRootPart.Position
		return Vector3.new(math.round(pos.X / 4) * 4, FIELD_Y, math.round(pos.Z / 4) * 4 + 15)
	end
	return Vector3.new(0, FIELD_Y, 15)
end

local function slotWorldPos(side: string, index: number): Vector3
	local xOffset = (index - 2) * SLOT_GAP -- index 1,2,3 → -GAP, 0, +GAP
	local zOffset = if side == "player" then FIELD_ROW_GAP / 2 else -FIELD_ROW_GAP / 2
	return _fieldOrigin + Vector3.new(xOffset, 0, zOffset)
end

local function calcStats(modelData: { [string]: any }): (number, number)
	local parts = modelData.parts
	if not parts then
		return 20, 5
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
	return math.max(hp, 10), math.max(atk, 3)
end

--------------------------------------------------------------------------------
-- 3D Field
--------------------------------------------------------------------------------

local function createFieldMarkers()
	_fieldOrigin = getFieldOrigin()
	_fieldFolder = Instance.new("Folder")
	_fieldFolder.Name = "CardBattlerField"
	_fieldFolder.Parent = Workspace
	table.insert(_instances, _fieldFolder)

	for _, side in ipairs({ "player", "enemy" }) do
		for i = 1, FIELD_SLOTS do
			local key = side .. "_" .. i
			local marker = Instance.new("Part")
			marker.Name = key
			marker.Anchored = true
			marker.CanCollide = false
			marker.Size = Vector3.new(SLOT_SIZE, SLOT_HEIGHT, SLOT_SIZE)
			marker.Position = slotWorldPos(side, i)
			marker.Material = Enum.Material.SmoothPlastic
			marker.Color = if side == "player" then COLORS.accentDim else COLORS.danger
			marker.Transparency = 0.5
			marker.Parent = _fieldFolder

			-- Selection detection for player slots
			if side == "player" then
				local click = Instance.new("ClickDetector")
				click.MaxActivationDistance = 50
				click.Parent = marker
				click.MouseClick:Connect(function()
					if _gameOver or _resolving then
						return
					end
					if _selectedHandIndex and _hand[_selectedHandIndex] and not _fieldCards[key] then
						playCardToSlot(_selectedHandIndex, key)
					end
				end)
			end

			_slotMarkers[key] = marker
			_fieldCards[key] = nil
		end
	end
end

local function placeModelOnSlot(card: CardData, slotKey: string)
	local marker = _slotMarkers[slotKey]
	if not marker then
		return
	end

	local model = OrigamiBuilder.BuildModel(card.modelData)
	model.Parent = _fieldFolder
	card.model = model

	-- Position model on top of slot marker
	if model.PrimaryPart then
		local _, size = model:GetBoundingBox()
		local pos = marker.Position + Vector3.new(0, SLOT_HEIGHT / 2 + size.Y / 2, 0)
		model:PivotTo(CFrame.new(pos))
	end

	OrigamiBuilder.ApplyAnimation(model, card.modelData.animation or "idle_bob")
end

local function removeModelFromSlot(slotKey: string)
	local card = _fieldCards[slotKey]
	if card and card.model then
		card.model:Destroy()
		card.model = nil
	end
	_fieldCards[slotKey] = nil
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

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

local function createUI()
	_gui = Instance.new("ScreenGui")
	_gui.Name = "CardBattlerGui"
	_gui.DisplayOrder = 15
	_gui.ResetOnSpawn = false
	_gui.Enabled = false
	_gui.Parent = getPlayer():WaitForChild("PlayerGui")
	table.insert(_instances, _gui)

	-- Top bar: HP bars + turn counter
	local topBar = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(1, 0, 0, 50),
		position = UDim2.new(0, 0, 0, 0),
		parent = _gui,
	})
	local topPad = Instance.new("UIPadding")
	topPad.PaddingLeft = UDim.new(0, 20)
	topPad.PaddingRight = UDim.new(0, 20)
	topPad.Parent = topBar

	_playerHPLabel = makeLabel({
		text = "You: 100 HP",
		size = UDim2.new(0.3, 0, 1, 0),
		position = UDim2.new(0, 0, 0, 0),
		color = COLORS.success,
		textSize = 18,
		alignX = Enum.TextXAlignment.Left,
		parent = topBar,
	})

	_turnLabel = makeLabel({
		text = "Turn 0",
		size = UDim2.new(0.4, 0, 1, 0),
		position = UDim2.new(0.3, 0, 0, 0),
		color = COLORS.accent,
		textSize = 18,
		parent = topBar,
	})

	_enemyHPLabel = makeLabel({
		text = "Enemy: 100 HP",
		size = UDim2.new(0.3, 0, 1, 0),
		position = UDim2.new(0.7, 0, 0, 0),
		color = COLORS.error,
		textSize = 18,
		alignX = Enum.TextXAlignment.Right,
		parent = topBar,
	})

	-- Field display (UI overlay showing slot info)
	local fieldPanel = makeFrame({
		bg = Color3.fromRGB(0, 0, 0),
		size = UDim2.new(0, 420, 0, 160),
		position = UDim2.new(0.5, 0, 0, 60),
		anchor = Vector2.new(0.5, 0),
		corner = 8,
		parent = _gui,
	})
	fieldPanel.BackgroundTransparency = 0.6

	-- Enemy row (top)
	for i = 1, FIELD_SLOTS do
		local key = "enemy_" .. i
		local slotFrame = makeFrame({
			bg = COLORS.danger,
			size = UDim2.new(0, 120, 0, 60),
			position = UDim2.new(0, 10 + (i - 1) * 135, 0, 10),
			corner = 6,
			parent = fieldPanel,
		})
		slotFrame.BackgroundTransparency = 0.5
		makeLabel({
			text = "Empty",
			size = UDim2.new(1, 0, 1, 0),
			color = COLORS.textDim,
			textSize = 12,
			parent = slotFrame,
		})
		_fieldSlotFrames[key] = slotFrame
	end

	-- Player row (bottom)
	for i = 1, FIELD_SLOTS do
		local key = "player_" .. i
		local slotFrame = makeFrame({
			bg = COLORS.accentDim,
			size = UDim2.new(0, 120, 0, 60),
			position = UDim2.new(0, 10 + (i - 1) * 135, 0, 85),
			corner = 6,
			parent = fieldPanel,
		})
		slotFrame.BackgroundTransparency = 0.5
		makeLabel({
			text = "Empty",
			size = UDim2.new(1, 0, 1, 0),
			color = COLORS.textDim,
			textSize = 12,
			parent = slotFrame,
		})
		_fieldSlotFrames[key] = slotFrame
	end

	-- Bottom area: hand + controls
	local bottomBar = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(1, 0, 0, 140),
		position = UDim2.new(0, 0, 1, -140),
		parent = _gui,
	})

	-- Hand cards
	_handFrame = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(0, MAX_HAND_SIZE * 110 + 10, 0, 90),
		position = UDim2.new(0.5, 0, 0, 5),
		anchor = Vector2.new(0.5, 0),
		parent = bottomBar,
	})
	local handLayout = Instance.new("UIListLayout")
	handLayout.FillDirection = Enum.FillDirection.Horizontal
	handLayout.Padding = UDim.new(0, 6)
	handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	handLayout.Parent = _handFrame

	-- Prompt row
	local promptRow = makeFrame({
		bg = COLORS.bg,
		size = UDim2.new(1, -40, 0, 36),
		position = UDim2.new(0.5, 0, 0, 100),
		anchor = Vector2.new(0.5, 0),
		parent = bottomBar,
	})
	local promptLayout = Instance.new("UIListLayout")
	promptLayout.FillDirection = Enum.FillDirection.Horizontal
	promptLayout.Padding = UDim.new(0, 6)
	promptLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	promptLayout.Parent = promptRow

	_promptBox = Instance.new("TextBox")
	_promptBox.Size = UDim2.new(0, 300, 0, 36)
	_promptBox.BackgroundColor3 = COLORS.bgLight
	_promptBox.BorderSizePixel = 0
	_promptBox.Font = Enum.Font.Gotham
	_promptBox.TextSize = 14
	_promptBox.TextColor3 = COLORS.text
	_promptBox.PlaceholderText = "Describe a creature..."
	_promptBox.PlaceholderColor3 = COLORS.textDim
	_promptBox.ClearTextOnFocus = false
	_promptBox.Parent = promptRow
	local promptCorner = Instance.new("UICorner")
	promptCorner.CornerRadius = UDim.new(0, 6)
	promptCorner.Parent = _promptBox
	local promptPad = Instance.new("UIPadding")
	promptPad.PaddingLeft = UDim.new(0, 8)
	promptPad.PaddingRight = UDim.new(0, 8)
	promptPad.Parent = _promptBox

	_createBtn = makeButton({
		text = "Create Card",
		bg = COLORS.accent,
		size = UDim2.new(0, 120, 0, 36),
		corner = 6,
		parent = promptRow,
	})

	_endTurnBtn = makeButton({
		text = "End Turn",
		bg = COLORS.success,
		size = UDim2.new(0, 100, 0, 36),
		corner = 6,
		parent = promptRow,
	})

	-- Status
	_statusLabel = makeLabel({
		text = "",
		size = UDim2.new(0, 400, 0, 24),
		position = UDim2.new(0.5, 0, 1, -145),
		anchor = Vector2.new(0.5, 1),
		color = COLORS.textDim,
		textSize = 14,
		parent = _gui,
	})

	-- Wire up buttons
	_createBtn.Activated:Connect(function()
		if _gameOver or _resolving then
			return
		end
		createCard()
	end)

	_endTurnBtn.Activated:Connect(function()
		if _gameOver or _resolving then
			return
		end
		endTurn()
	end)

	_promptBox.FocusLost:Connect(function(enterPressed)
		if enterPressed and not _gameOver and not _resolving then
			createCard()
		end
	end)
end

--------------------------------------------------------------------------------
-- UI Updates
--------------------------------------------------------------------------------

local function updateHPDisplay()
	if _playerHPLabel then
		_playerHPLabel.Text = "You: " .. _playerHP .. " HP"
		_playerHPLabel.TextColor3 = if _playerHP <= 30 then COLORS.error else COLORS.success
	end
	if _enemyHPLabel then
		_enemyHPLabel.Text = "Enemy: " .. _enemyHP .. " HP"
		_enemyHPLabel.TextColor3 = if _enemyHP <= 30 then COLORS.success else COLORS.error
	end
	if _turnLabel then
		_turnLabel.Text = "Turn " .. _turnNumber
	end
end

local function updateSlotFrame(key: string)
	local frame = _fieldSlotFrames[key]
	if not frame then
		return
	end
	local label = frame:FindFirstChildWhichIsA("TextLabel")
	if not label then
		return
	end

	local card = _fieldCards[key]
	if card then
		label.Text = card.name .. "\nHP:" .. card.hp .. " ATK:" .. card.atk
		label.TextColor3 = COLORS.text
		label.TextSize = 11
		frame.BackgroundTransparency = 0.2
	else
		label.Text = "Empty"
		label.TextColor3 = COLORS.textDim
		label.TextSize = 12
		frame.BackgroundTransparency = 0.5
	end
end

local function updateAllSlotFrames()
	for key in pairs(_fieldSlotFrames) do
		updateSlotFrame(key)
	end
end

local function refreshHand()
	-- Clear existing hand UI
	for _, child in ipairs(_handFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for i, card in ipairs(_hand) do
		local cardBtn = makeButton({
			text = card.name .. "\nHP:" .. card.hp .. " ATK:" .. card.atk,
			bg = if _selectedHandIndex == i then COLORS.accent else COLORS.bgLight,
			textColor = if _selectedHandIndex == i then COLORS.bg else COLORS.text,
			size = UDim2.new(0, 100, 0, 80),
			corner = 6,
			textSize = 11,
			parent = _handFrame,
		})
		cardBtn.TextWrapped = true
		cardBtn.RichText = false

		cardBtn.Activated:Connect(function()
			if _gameOver or _resolving then
				return
			end
			if _selectedHandIndex == i then
				_selectedHandIndex = nil
			else
				_selectedHandIndex = i
			end
			refreshHand()
		end)
	end
end

--------------------------------------------------------------------------------
-- Card Creation
--------------------------------------------------------------------------------

createCard = function()
	local prompt = _promptBox.Text
	if prompt == "" then
		setStatus("Type a creature description first!", COLORS.error)
		return
	end
	if #_hand >= MAX_HAND_SIZE then
		setStatus("Hand is full! Play a card first.", COLORS.error)
		return
	end

	_createBtn.Text = "Creating..."
	_createBtn.BackgroundColor3 = COLORS.disabled
	setStatus("Generating creature...", COLORS.accent)

	task.spawn(function()
		local OrigamiService = Knit.GetService("OrigamiService")
		local ok, result = OrigamiService:RequestModel(prompt, "creature", "origami"):await()

		if _createBtn then
			_createBtn.Text = "Create Card"
			_createBtn.BackgroundColor3 = COLORS.accent
		end

		if ok and result and result.success and result.model then
			local modelData = result.model
			local hp, atk = calcStats(modelData)

			local card: CardData = {
				name = modelData.name or "Creature",
				hp = hp,
				maxHp = hp,
				atk = atk,
				modelData = modelData,
				model = nil,
				isEnemy = false,
			}

			table.insert(_hand, card)
			_promptBox.Text = ""
			refreshHand()
			setStatus("Created " .. card.name .. " (HP:" .. hp .. " ATK:" .. atk .. ")", COLORS.success)
		else
			local errMsg = if result and result.error then result.error else "Generation failed"
			setStatus("Error: " .. errMsg, COLORS.error)
		end
	end)
end

--------------------------------------------------------------------------------
-- Card Placement
--------------------------------------------------------------------------------

playCardToSlot = function(handIndex: number, slotKey: string)
	local card = _hand[handIndex]
	if not card then
		return
	end
	if _fieldCards[slotKey] then
		setStatus("Slot is occupied!", COLORS.error)
		return
	end

	table.remove(_hand, handIndex)
	_selectedHandIndex = nil
	_fieldCards[slotKey] = card

	placeModelOnSlot(card, slotKey)
	updateSlotFrame(slotKey)
	refreshHand()
	setStatus("Played " .. card.name .. " to field", COLORS.accent)
end

--------------------------------------------------------------------------------
-- Enemy AI
--------------------------------------------------------------------------------

local function makeEnemyCard(): CardData
	local template = ENEMY_TEMPLATES[math.random(1, #ENEMY_TEMPLATES)]
	local hp = ENEMY_BASE_HP + _turnNumber * ENEMY_HP_PER_TURN
	local atk = ENEMY_BASE_ATK + _turnNumber * ENEMY_ATK_PER_TURN

	-- Deep copy parts so we don't mutate templates
	local parts = {}
	for _, p in ipairs(template.parts) do
		local copy = {}
		for k, v in pairs(p) do
			if type(v) == "table" then
				local arr = {}
				for _, val in ipairs(v) do
					table.insert(arr, val)
				end
				copy[k] = arr
			else
				copy[k] = v
			end
		end
		table.insert(parts, copy)
	end

	local modelData = {
		name = template.name,
		parts = parts,
		animation = "idle_bob",
	}

	return {
		name = template.name,
		hp = hp,
		maxHp = hp,
		atk = atk,
		modelData = modelData,
		model = nil,
		isEnemy = true,
	}
end

local function enemyPlayCards()
	for i = 1, FIELD_SLOTS do
		local key = "enemy_" .. i
		if not _fieldCards[key] then
			local card = makeEnemyCard()
			_fieldCards[key] = card
			placeModelOnSlot(card, key)
			updateSlotFrame(key)
		end
	end
end

--------------------------------------------------------------------------------
-- Combat Resolution
--------------------------------------------------------------------------------

local function resolveCombat()
	_resolving = true
	setStatus("Resolving combat...", COLORS.accent)

	-- Resolve left to right
	for i = 1, FIELD_SLOTS do
		local playerKey = "player_" .. i
		local enemyKey = "enemy_" .. i
		local playerCard = _fieldCards[playerKey]
		local enemyCard = _fieldCards[enemyKey]

		if playerCard and enemyCard then
			-- Both sides attack each other
			enemyCard.hp -= playerCard.atk
			playerCard.hp -= enemyCard.atk

			if enemyCard.hp <= 0 then
				removeModelFromSlot(enemyKey)
				updateSlotFrame(enemyKey)
			end
			if playerCard.hp <= 0 then
				removeModelFromSlot(playerKey)
				updateSlotFrame(playerKey)
			else
				updateSlotFrame(playerKey)
			end
			if enemyCard.hp > 0 then
				updateSlotFrame(enemyKey)
			end
		elseif playerCard and not enemyCard then
			-- Direct damage to enemy
			_enemyHP -= playerCard.atk
		elseif enemyCard and not playerCard then
			-- Direct damage to player
			_playerHP -= enemyCard.atk
		end
	end

	_playerHP = math.max(_playerHP, 0)
	_enemyHP = math.max(_enemyHP, 0)
	updateHPDisplay()
	updateAllSlotFrames()

	-- Check game over
	if _playerHP <= 0 then
		_gameOver = true
		setStatus("DEFEAT! You were destroyed on turn " .. _turnNumber, COLORS.error)
		_resolving = false
		return
	end
	if _enemyHP <= 0 then
		_gameOver = true
		setStatus("VICTORY! You won on turn " .. _turnNumber .. "!", COLORS.success)
		_resolving = false
		return
	end

	_resolving = false
end

endTurn = function()
	_turnNumber += 1

	resolveCombat()

	if not _gameOver then
		-- Enemy plays new cards into empty slots
		enemyPlayCards()
		updateHPDisplay()
		setStatus("Turn " .. _turnNumber .. " — play cards and end turn", COLORS.accent)
	end
end

--------------------------------------------------------------------------------
-- Activate / Cleanup
--------------------------------------------------------------------------------

function CardBattlerController:Activate()
	if _active then
		return
	end
	_active = true

	-- Reset state
	_hand = {}
	_selectedHandIndex = nil
	_fieldCards = {}
	_playerHP = STARTING_HP
	_enemyHP = STARTING_HP
	_turnNumber = 1
	_gameOver = false
	_resolving = false

	-- Create 3D field
	createFieldMarkers()

	-- Create UI
	createUI()
	_gui.Enabled = true

	-- Initial enemy wave
	enemyPlayCards()
	updateHPDisplay()
	updateAllSlotFrames()
	refreshHand()

	setStatus("Turn 1 — create creatures and place them on the field!", COLORS.accent)
end

function CardBattlerController:Cleanup()
	if not _active then
		return
	end
	_active = false

	-- Destroy all tracked instances (UI + field)
	for _, inst in ipairs(_instances) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	_instances = {}

	-- Clear references
	_gui = nil :: any
	_fieldFolder = nil :: any
	_slotMarkers = {}
	_fieldCards = {}
	_fieldSlotFrames = {}
	_hand = {}
	_selectedHandIndex = nil
	_handFrame = nil :: any
	_playerHPLabel = nil :: any
	_enemyHPLabel = nil :: any
	_turnLabel = nil :: any
	_statusLabel = nil :: any
	_promptBox = nil :: any
	_createBtn = nil :: any
	_endTurnBtn = nil :: any
end

--------------------------------------------------------------------------------
-- Knit Lifecycle
--------------------------------------------------------------------------------

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
