local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local ServerConfig = require(ReplicatedStorage.Assets.Configuration.Server)

local DMService = Knit.CreateService({
	Name = "DMService",

	Client = {
		SceneProgress = Knit.CreateSignal(), -- (step: number, total: number, itemName: string)
	},
})

-- Scene tracking per player
-- _activeScenes[userId] = { name, folder, items, anchorPosition, nextItemId }
local _activeScenes: { [number]: any } = {}

-----------------------------------------------------------
-- Helpers
-----------------------------------------------------------

local function getApiUrl(): string
	return ServerConfig.API_URL or OrigamiConfig.API_URL
end

local function getApiKey(): string
	return ServerConfig.API_KEY or OrigamiConfig.API_KEY
end

-- Call /api/generate to get model data for a single item
local function callGenerateAPI(
	prompt: string,
	playerId: string,
	category: string,
	style: string,
	aiModel: string,
	dmMode: boolean?
): (boolean, any)
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		return false, "api_not_configured"
	end

	local isRaw = category == "raw"
	local requestBody = {
		prompt = prompt,
		player_id = playerId,
		category = if isRaw then nil else category,
		style = style or "origami",
		model = aiModel or OrigamiConfig.DM.DEFAULT_MODEL,
		raw = if isRaw then true else nil,
		dm_mode = if dmMode then true else nil,
	}

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = apiUrl .. "/api/generate",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["X-Api-Key"] = getApiKey(),
			},
			Body = HttpService:JSONEncode(requestBody),
		})
	end)

	if not ok then
		warn("[DMService] HTTP request failed:", response)
		return false, "request_failed: " .. tostring(response)
	end

	if not response.Success then
		warn("[DMService] API error:", response.StatusCode, response.Body)
		local detail = ""
		local decodeOk, errBody = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if decodeOk and errBody then
			if type(errBody.detail) == "string" then
				detail = errBody.detail
			elseif errBody.error then
				detail = errBody.error
			end
		end
		return false, "api_error(" .. response.StatusCode .. "): " .. detail
	end

	local parseOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not parseOk or not data then
		return false, "parse_error"
	end

	if not data.success then
		return false, data.error or "generation_failed"
	end

	return true, data.model
end

-- Call /api/generate-scene to get a scene plan from the LLM
local function callScenePlannerAPI(prompt: string, playerId: string, aiModel: string): (boolean, any)
	local apiUrl = getApiUrl()
	if apiUrl == "" then
		return false, "api_not_configured"
	end

	local requestBody = {
		prompt = prompt,
		player_id = playerId,
		model = aiModel or OrigamiConfig.DM.DEFAULT_MODEL,
	}

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = apiUrl .. "/api/generate-scene",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["X-Api-Key"] = getApiKey(),
			},
			Body = HttpService:JSONEncode(requestBody),
		})
	end)

	if not ok then
		warn("[DMService] Scene planner HTTP request failed:", response)
		return false, "request_failed: " .. tostring(response)
	end

	if not response.Success then
		warn("[DMService] Scene planner API error:", response.StatusCode, response.Body)
		return false, "api_error(" .. response.StatusCode .. ")"
	end

	local parseOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if not parseOk or not data then
		return false, "parse_error"
	end

	if not data.success then
		return false, data.error or "scene_planning_failed"
	end

	return true, data.scene
end

-- Raycast to find ground Y at a given X, Z position
local function raycastGround(x: number, z: number, baseY: number, excludeInstances: { Instance }?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeInstances or {}

	local result = workspace:Raycast(Vector3.new(x, baseY + 50, z), Vector3.new(0, -200, 0), params)
	return if result then result.Position.Y else baseY
end

-- Add a BillboardGui name label to a model
local function addNameLabel(model: Model, name: string, isEnemy: boolean?)
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
	label.TextColor3 = if isEnemy then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(255, 255, 255)
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

-- Build a model from API response data and place it in the world
local function buildAndPlace(
	modelData: { [string]: any },
	position: Vector3,
	rotationY: number,
	parentFolder: Folder,
	isEnemy: boolean?
): Model?
	local buildOk, model = pcall(function()
		return OrigamiBuilder.BuildModel(modelData)
	end)

	if not buildOk or not model then
		warn("[DMService] Failed to build model:", model)
		return nil
	end

	-- Parent to folder so GetBoundingBox works
	model.Parent = parentFolder

	-- Compute pivot offset from bottom for flush ground placement
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)

	-- Raycast to find ground
	local groundY = raycastGround(position.X, position.Z, position.Y, { model })

	-- Place flush on ground with rotation
	model:PivotTo(
		CFrame.new(position.X, groundY + pivotAboveBottom, position.Z) * CFrame.Angles(0, math.rad(rotationY), 0)
	)

	-- Add name label (red for enemies, white for friendlies)
	local modelName = modelData.name or "Creation"
	addNameLabel(model, modelName, isEnemy)

	-- Set enemy attributes (data-only stubs for future combat)
	if isEnemy then
		model:SetAttribute("Enemy", true)
		model:SetAttribute("MaxHealth", 100)
		model:SetAttribute("Health", 100)
	end

	-- Apply non-creature animation (creatures use CreatureAI instead)
	local resolvedCategory = modelData.category
	if resolvedCategory ~= "creature" then
		local animType = modelData.animation or "idle_bob"
		OrigamiBuilder.ApplyAnimation(model, animType)
	end

	return model
end

-- Ensure a scene exists for the player, or create one
local function ensureScene(player: Player, anchorPosition: Vector3?)
	local userId = player.UserId
	if _activeScenes[userId] then
		return _activeScenes[userId]
	end

	local folder = Instance.new("Folder")
	folder.Name = "DMScene_" .. player.Name
	folder.Parent = workspace

	_activeScenes[userId] = {
		name = "Scene",
		folder = folder,
		items = {},
		anchorPosition = anchorPosition or Vector3.new(0, 0, 0),
		nextItemId = 0,
	}

	return _activeScenes[userId]
end

-- Clean up a player's entire scene
local function cleanupScene(userId: number)
	local scene = _activeScenes[userId]
	if not scene then
		return
	end

	-- Stop all creature AIs
	for _, item in ipairs(scene.items) do
		if item.aiCleanup then
			item.aiCleanup()
		end
	end

	-- Destroy folder (and all models inside it)
	if scene.folder and scene.folder.Parent then
		scene.folder:Destroy()
	end

	_activeScenes[userId] = nil
end

-----------------------------------------------------------
-- Client methods
-----------------------------------------------------------

-- Add a single item to the DM scene
function DMService.Client:AddToScene(
	player: Player,
	prompt: string,
	category: string,
	style: string?,
	aiModel: string?,
	position: Vector3?,
	rotationY: number?
)
	print("[DMService] AddToScene called by", player.Name, "prompt:", prompt, "category:", category)

	local scene = ensureScene(player, position)
	local playerId = tostring(player.UserId)

	-- Determine placement position
	local placePos = position or scene.anchorPosition
	local rotation = rotationY or 0

	-- Fire progress signal
	self.Server.Client.SceneProgress:Fire(player, 1, 1, prompt:sub(1, 30))

	-- Call external API to generate model data (dm_mode for relaxed rate limits)
	local ok, modelData = callGenerateAPI(
		prompt,
		playerId,
		category or "prop",
		style or "origami",
		aiModel or OrigamiConfig.DM.DEFAULT_MODEL,
		true
	)
	if not ok then
		warn("[DMService] API call failed for:", prompt, "error:", modelData)
		return { success = false, error = tostring(modelData) }
	end

	-- Build and place the model
	local builtModel = buildAndPlace(modelData, placePos, rotation, scene.folder, false)
	if not builtModel then
		return { success = false, error = "build_failed" }
	end

	-- Track item in scene
	scene.nextItemId += 1
	local itemId = scene.nextItemId

	-- Start creature AI if this is a creature
	local aiCleanup = nil
	local resolvedCategory = modelData.category or category or "prop"
	if resolvedCategory == "creature" then
		aiCleanup = CreatureAI.Start(
			builtModel,
			modelData,
			builtModel:GetPivot().Position,
			{ builtModel },
			OrigamiConfig.DM.CREATURE_TICK_RATE
		)
	end

	table.insert(scene.items, {
		id = itemId,
		model = builtModel,
		category = resolvedCategory,
		description = prompt,
		enemy = false,
		aiCleanup = aiCleanup,
	})

	print("[DMService] Item added:", builtModel.Name, "id:", itemId, "category:", resolvedCategory)

	return {
		success = true,
		itemId = itemId,
		name = modelData.name or "Creation",
		category = resolvedCategory,
	}
end

-- Build an entire scene from a world description
function DMService.Client:RequestScene(
	player: Player,
	prompt: string,
	style: string?,
	aiModel: string?,
	anchorPosition: Vector3?
)
	print("[DMService] RequestScene called by", player.Name, "prompt:", prompt)

	-- Clear any existing scene first
	cleanupScene(player.UserId)

	local scene = ensureScene(player, anchorPosition)
	scene.name = prompt:sub(1, 40)
	local playerId = tostring(player.UserId)
	local resolvedModel = aiModel or OrigamiConfig.DM.DEFAULT_MODEL
	local resolvedStyle = style or "origami"

	-- Step 1: Call the scene planner to get a list of items
	self.Server.Client.SceneProgress:Fire(player, 0, 1, "Planning scene...")

	local planOk, scenePlan = callScenePlannerAPI(prompt, playerId, resolvedModel)
	if not planOk then
		warn("[DMService] Scene planner failed:", scenePlan)
		return { success = false, error = tostring(scenePlan) }
	end

	local items = scenePlan.items
	if not items or #items == 0 then
		return { success = false, error = "empty_scene_plan" }
	end

	-- Update scene name from the plan
	if scenePlan.name then
		scene.name = scenePlan.name
	end

	local totalItems = #items
	local builtCount = 0
	local failedCount = 0

	print("[DMService] Scene plan has", totalItems, "items. Building...")

	-- Step 2: Generate and place each item
	for i, planItem in ipairs(items) do
		local itemDesc = planItem.description or "unknown item"
		local itemCategory = planItem.category or "prop"
		local itemPos = planItem.position or { 0, 0, 0 }
		local itemRotation = planItem.rotation_y or 0
		local itemEnemy = planItem.enemy or false

		-- Fire progress signal
		self.Server.Client.SceneProgress:Fire(player, i, totalItems, itemDesc:sub(1, 30))

		-- Convert position array to world position (relative to anchor)
		local anchor = scene.anchorPosition
		local worldPos =
			Vector3.new(anchor.X + (itemPos[1] or 0), anchor.Y + (itemPos[2] or 0), anchor.Z + (itemPos[3] or 0))

		-- Generate model data via API
		local genOk, modelData = callGenerateAPI(itemDesc, playerId, itemCategory, resolvedStyle, resolvedModel, true)

		if genOk and modelData then
			-- Build and place
			local builtModel = buildAndPlace(modelData, worldPos, itemRotation, scene.folder, itemEnemy)

			if builtModel then
				-- Track item
				scene.nextItemId += 1
				local itemId = scene.nextItemId

				-- Start creature AI if applicable
				local aiCleanup = nil
				local resolvedCategory = modelData.category or itemCategory
				if resolvedCategory == "creature" then
					aiCleanup = CreatureAI.Start(
						builtModel,
						modelData,
						builtModel:GetPivot().Position,
						{ builtModel },
						OrigamiConfig.DM.CREATURE_TICK_RATE
					)
				end

				table.insert(scene.items, {
					id = itemId,
					model = builtModel,
					category = resolvedCategory,
					description = itemDesc,
					enemy = itemEnemy,
					aiCleanup = aiCleanup,
				})

				builtCount += 1
				print("[DMService] Scene item", i, "/", totalItems, "built:", builtModel.Name)
			else
				failedCount += 1
				warn("[DMService] Failed to build scene item:", itemDesc)
			end
		else
			failedCount += 1
			warn("[DMService] Failed to generate scene item:", itemDesc, "error:", modelData)
		end

		-- Small yield between items to prevent server exhaustion
		task.wait(0.1)
	end

	print("[DMService] Scene complete:", builtCount, "built,", failedCount, "failed")

	return {
		success = true,
		sceneName = scene.name,
		builtCount = builtCount,
		failedCount = failedCount,
		totalPlanned = totalItems,
	}
end

-- Remove a single item from the scene by ID
function DMService.Client:RemoveFromScene(player: Player, itemId: number)
	local scene = _activeScenes[player.UserId]
	if not scene then
		return { success = false, error = "no_scene" }
	end

	for i, item in ipairs(scene.items) do
		if item.id == itemId then
			-- Stop creature AI if running
			if item.aiCleanup then
				item.aiCleanup()
			end

			-- Destroy model
			if item.model and item.model.Parent then
				item.model:Destroy()
			end

			table.remove(scene.items, i)
			print("[DMService] Removed item:", itemId)
			return { success = true }
		end
	end

	return { success = false, error = "item_not_found" }
end

-- Clear the entire scene
function DMService.Client:ClearScene(player: Player)
	print("[DMService] ClearScene called by", player.Name)
	cleanupScene(player.UserId)
	return { success = true }
end

-- Get list of items in the scene (for client UI to display)
function DMService.Client:GetSceneItems(player: Player)
	local scene = _activeScenes[player.UserId]
	if not scene then
		return { success = true, items = {}, sceneName = "" }
	end

	local itemList = {}
	for _, item in ipairs(scene.items) do
		local pos = nil
		if item.model and item.model.PrimaryPart then
			local p = item.model.PrimaryPart.Position
			pos = { X = p.X, Y = p.Y, Z = p.Z }
		end

		table.insert(itemList, {
			id = item.id,
			name = if item.model then item.model.Name else "Unknown",
			category = item.category,
			description = item.description,
			enemy = item.enemy,
			position = pos,
		})
	end

	return { success = true, items = itemList, sceneName = scene.name }
end

-----------------------------------------------------------
-- Lifecycle
-----------------------------------------------------------

function DMService:KnitInit()
	-- Clean up scenes when players leave
	Players.PlayerRemoving:Connect(function(player)
		cleanupScene(player.UserId)
	end)
end

function DMService:KnitStart()
	print("[DMService] Started")
end

return DMService
