--[[
	WorkshopService — craft accessories, tools, costumes, and props from mining materials.
	Validates recipes, deducts materials, calls OrigamiService for LLM model data,
	creates PendingCraft entries with timers, and handles equip/unequip/prop placement.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local WorkshopConfig = require(ReplicatedStorage.Shared.WorkshopConfig)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local MaterialTiers = require(ReplicatedStorage.Shared.MaterialTiers)

local function _materialNamespace(itemId: string): string
	local role = MaterialTiers.getRole(itemId)
	if role == "bulk" or role == "ore" then
		return role
	end
	return "misc"
end

local WorkshopService = Knit.CreateService({
	Name = "WorkshopService",
	Client = {
		ItemCrafted = Knit.CreateSignal(),
		ItemClaimed = Knit.CreateSignal(),
		ItemEquipped = Knit.CreateSignal(),
		ItemUnequipped = Knit.CreateSignal(),
	},
})

-- R15 to R6 fallback map (same as OrigamiService)
local R15_TO_R6 = {
	UpperTorso = "Torso",
	LowerTorso = "Torso",
	LeftUpperArm = "Left Arm",
	LeftLowerArm = "Left Arm",
	LeftHand = "Left Arm",
	RightUpperArm = "Right Arm",
	RightLowerArm = "Right Arm",
	RightHand = "Right Arm",
	LeftUpperLeg = "Left Leg",
	LeftLowerLeg = "Left Leg",
	LeftFoot = "Left Leg",
	RightUpperLeg = "Right Leg",
	RightLowerLeg = "Right Leg",
	RightFoot = "Right Leg",
}

local function findBodyPart(character: Model, bodyPartName: string): BasePart?
	local found = character:FindFirstChild(bodyPartName)
	if found and found:IsA("BasePart") then
		return found
	end
	local r6Name = R15_TO_R6[bodyPartName]
	if r6Name then
		found = character:FindFirstChild(r6Name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

local function generateGUID(): string
	return HttpService:GenerateGUID(false)
end

-- Build LLM prompt based on item type and recipe
local function buildPrompt(recipe: WorkshopConfig.WorkshopRecipe, userPrompt: string): string
	local cleanPrompt = ""
	if userPrompt and type(userPrompt) == "string" then
		cleanPrompt = userPrompt:sub(1, 500):match("^%s*(.-)%s*$") or ""
	end

	local itemType = recipe.itemType
	local rarity = recipe.rarity:lower()

	if itemType == "accessory" then
		local attachPoint = recipe.attachPoint or "Head"
		if #cleanPrompt > 0 then
			return string.format(
				"Create a %s-rarity wearable accessory based on this description: %s. "
					.. "Style hints: %s. "
					.. "It attaches to the %s. Use body_part field set to '%s' for all parts so it can be rigged. "
					.. "Make it unique and visually interesting. Keep it small enough to wear. Category: accessory.",
				rarity,
				cleanPrompt,
				recipe.theme,
				attachPoint,
				attachPoint
			)
		else
			return string.format(
				"Create a %s-rarity wearable accessory: %s. "
					.. "It attaches to the %s. Use body_part field set to '%s' for all parts so it can be rigged. "
					.. "Make it unique and visually interesting. Keep it small enough to wear. Category: accessory.",
				rarity,
				recipe.theme,
				attachPoint,
				attachPoint
			)
		end
	elseif itemType == "tool" then
		if #cleanPrompt > 0 then
			return string.format(
				"Create a %s-rarity held weapon/tool based on this description: %s. "
					.. "Style hints: %s. "
					.. "It should have a handle grip at the bottom and a weapon head/blade at the top. "
					.. "Use body_part field set to 'RightHand' for all parts so it can be held. "
					.. "Make it unique with interesting details. Category: tool.",
				rarity,
				cleanPrompt,
				recipe.theme
			)
		else
			return string.format(
				"Create a %s-rarity held weapon/tool: %s. "
					.. "It should have a handle grip at the bottom and a weapon head/blade at the top. "
					.. "Use body_part field set to 'RightHand' for all parts so it can be held. "
					.. "Make it unique with interesting details. Category: tool.",
				rarity,
				recipe.theme
			)
		end
	elseif itemType == "costume" then
		if #cleanPrompt > 0 then
			return string.format(
				"Create a %s-rarity full-body costume based on this description: %s. "
					.. "Style hints: %s. "
					.. "Map parts to body_part fields: Head, UpperTorso, LowerTorso, "
					.. "RightUpperArm, LeftUpperArm, RightUpperLeg, LeftUpperLeg. "
					.. "It should cover the entire body as a complete avatar override. Category: avatar.",
				rarity,
				cleanPrompt,
				recipe.theme
			)
		else
			return string.format(
				"Create a %s-rarity full-body costume: %s. "
					.. "Map parts to body_part fields: Head, UpperTorso, LowerTorso, "
					.. "RightUpperArm, LeftUpperArm, RightUpperLeg, LeftUpperLeg. "
					.. "It should cover the entire body as a complete avatar override. Category: avatar.",
				rarity,
				recipe.theme
			)
		end
	elseif itemType == "prop" then
		local size = recipe.placementSize or { x = 4, y = 4, z = 4 }
		if #cleanPrompt > 0 then
			return string.format(
				"Create a %s-rarity placeable decoration based on this description: %s. "
					.. "Style hints: %s. "
					.. "It should fit within roughly %dx%dx%d studs. "
					.. "Make it a standalone decoration piece. Category: prop.",
				rarity,
				cleanPrompt,
				recipe.theme,
				size.x,
				size.y,
				size.z
			)
		else
			return string.format(
				"Create a %s-rarity placeable decoration: %s. "
					.. "It should fit within roughly %dx%dx%d studs. "
					.. "Make it a standalone decoration piece. Category: prop.",
				rarity,
				recipe.theme,
				size.x,
				size.y,
				size.z
			)
		end
	end

	return "Create a unique origami item: " .. recipe.theme
end

-- Remove equipped workshop items of a given type from the character
local function removeEquippedVisuals(character: Model, itemType: string)
	local attrName = if itemType == "accessory"
		then "OrigamiAccessory"
		elseif itemType == "tool" then "OrigamiTool"
		elseif itemType == "costume" then "OrigamiAvatar"
		else nil

	if not attrName then
		return
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute(attrName) then
			child:Destroy()
		end
	end
end

-- Weld an origami model's parts to a target body part on the character
local function weldToBodyPart(character: Model, modelData: { [string]: any }, targetPartName: string, attrName: string)
	local model = OrigamiBuilder.BuildModel(modelData)
	if not model then
		return
	end

	local targetPart = findBodyPart(character, targetPartName)
	if not targetPart then
		targetPart = character:FindFirstChild("HumanoidRootPart")
	end
	if not targetPart then
		model:Destroy()
		return
	end

	-- Undo OrigamiBuilder's 180° Y flip for body-local coords
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CFrame = CFrame.Angles(0, math.pi, 0) * child.CFrame
		end
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			part:SetAttribute(attrName, true)

			local offset = CFrame.new(part.Position)
			local partRot = part.CFrame - part.CFrame.Position
			part.CFrame = targetPart.CFrame * offset * partRot
			part.Parent = character

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = targetPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	model:Destroy()
end

-- Apply a costume using OrigamiService's ApplyAvatar (full body override)
local function applyCostume(player: Player, modelData: { [string]: any })
	local OrigamiService = Knit.GetService("OrigamiService")
	return OrigamiService.Client:ApplyAvatar(player, modelData)
end

-- Remove costume using OrigamiService's ResetAvatar
local function removeCostume(player: Player)
	local OrigamiService = Knit.GetService("OrigamiService")
	return OrigamiService.Client:ResetAvatar(player)
end

------------------------------------------------------
-- Client Methods
------------------------------------------------------

function WorkshopService.Client:GetRecipes(player: Player, itemType: string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end

	local inv = data.MiningInventory or {}
	local sourceRecipes = if itemType then WorkshopConfig.getRecipesByType(itemType) else WorkshopConfig.RECIPES

	local recipes = {}
	for _, recipe in ipairs(sourceRecipes) do
		local mats = {}
		local canCraft = true
		for _, mat in ipairs(recipe.materials) do
			local namespace = _materialNamespace(mat.itemId)
			local nsBucket = inv[namespace] or {}
			local have = nsBucket[mat.itemId] or 0
			table.insert(mats, { itemId = mat.itemId, need = mat.count, have = have })
			if have < mat.count then
				canCraft = false
			end
		end
		table.insert(recipes, {
			id = recipe.id,
			itemType = recipe.itemType,
			rarity = recipe.rarity,
			displayName = recipe.displayName,
			craftTime = recipe.craftTime,
			materials = mats,
			canCraft = canCraft,
			attachPoint = recipe.attachPoint,
			toolStats = recipe.toolStats,
			placementSize = recipe.placementSize,
		})
	end
	return recipes
end

function WorkshopService.Client:CraftItem(player: Player, recipeId: string, userPrompt: string?)
	local recipe = WorkshopConfig.getRecipeById(recipeId)
	if not recipe then
		return { success = false, error = "Invalid recipe" }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	-- Check craft capacity
	local pending = data.PendingCrafts or {}
	if #pending >= WorkshopConfig.MAX_PENDING_CRAFTS then
		return { success = false, error = "Craft queue full (max " .. WorkshopConfig.MAX_PENDING_CRAFTS .. ")" }
	end

	-- Check item collection capacity
	local crafted = data.CraftedItems or {}
	if #crafted >= WorkshopConfig.MAX_CRAFTED_ITEMS then
		return { success = false, error = "Item collection full (max " .. WorkshopConfig.MAX_CRAFTED_ITEMS .. ")" }
	end

	-- Check materials
	local inv = data.MiningInventory or {}
	for _, mat in ipairs(recipe.materials) do
		local namespace = _materialNamespace(mat.itemId)
		local nsBucket = inv[namespace] or {}
		if (nsBucket[mat.itemId] or 0) < mat.count then
			return { success = false, error = "Not enough " .. mat.itemId:gsub("_", " ") }
		end
	end

	-- Deduct materials
	for _, mat in ipairs(recipe.materials) do
		local namespace = _materialNamespace(mat.itemId)
		local current = PlayerDataService:Read(player, { "MiningInventory", namespace, mat.itemId }) or 0
		PlayerDataService:Write(player, { "MiningInventory", namespace, mat.itemId }, current - mat.count)
	end

	-- Build LLM prompt and request model
	local prompt = buildPrompt(recipe, userPrompt or "")
	local OrigamiService = Knit.GetService("OrigamiService")
	local category = if recipe.itemType == "costume" then "avatar" else recipe.itemType
	local result = OrigamiService.Client:RequestModel(player, prompt, category, "lowpoly")

	local modelData = nil
	if result and result.success and result.model then
		modelData = result.model
	end

	-- Create PendingCraft entry
	local claimTime = os.time() + recipe.craftTime
	local craft = {
		recipeId = recipe.id,
		itemType = recipe.itemType,
		rarity = recipe.rarity,
		displayName = recipe.displayName,
		claimTime = claimTime,
		modelData = modelData,
		userPrompt = prompt,
		attachPoint = recipe.attachPoint,
		toolStats = recipe.toolStats,
		placementSize = recipe.placementSize,
	}

	table.insert(pending, craft)
	PlayerDataService:Write(player, { "PendingCrafts" }, pending)

	self.ItemCrafted:Fire(player, recipe.id, #pending)

	return {
		success = true,
		craftIndex = #pending,
		claimTime = claimTime,
		rarity = recipe.rarity,
		displayName = recipe.displayName,
	}
end

function WorkshopService.Client:CheckCrafts(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end

	local pending = data.PendingCrafts or {}
	local now = os.time()
	local result = {}
	for i, craft in ipairs(pending) do
		local remaining = math.max(0, (craft.claimTime or 0) - now)
		table.insert(result, {
			index = i,
			recipeId = craft.recipeId,
			itemType = craft.itemType,
			rarity = craft.rarity,
			displayName = craft.displayName,
			remainingSeconds = remaining,
			ready = remaining <= 0,
		})
	end
	return result
end

function WorkshopService.Client:ClaimItem(player: Player, craftIndex: number)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local pending = data.PendingCrafts or {}
	local craft = pending[craftIndex]
	if not craft then
		return { success = false, error = "Invalid craft index" }
	end

	-- Check if ready
	if os.time() < (craft.claimTime or 0) then
		return { success = false, error = "Not ready yet" }
	end

	-- If modelData is nil (LLM failed at craft time), retry now
	if not craft.modelData and craft.userPrompt then
		local OrigamiService = Knit.GetService("OrigamiService")
		local category = if craft.itemType == "costume" then "avatar" else craft.itemType
		local result = OrigamiService.Client:RequestModel(player, craft.userPrompt, category, "lowpoly")
		if result and result.success and result.model then
			craft.modelData = result.model
		end
	end

	-- Create CraftedItem
	local item = {
		id = generateGUID(),
		name = craft.displayName,
		itemType = craft.itemType,
		rarity = craft.rarity,
		modelData = craft.modelData,
		userPrompt = craft.userPrompt,
		createdAt = os.time(),
		attachPoint = craft.attachPoint,
		toolStats = craft.toolStats,
		placementSize = craft.placementSize,
	}

	-- Add to collection
	local crafted = data.CraftedItems or {}
	table.insert(crafted, item)
	PlayerDataService:Write(player, { "CraftedItems" }, crafted)

	-- Remove from pending
	table.remove(pending, craftIndex)
	PlayerDataService:Write(player, { "PendingCrafts" }, pending)

	self.ItemClaimed:Fire(player, item.id, item.itemType)

	return { success = true, item = item }
end

function WorkshopService.Client:GetCraftedItems(player: Player, itemType: string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end

	local items = data.CraftedItems or {}
	if not itemType then
		return items
	end

	local filtered = {}
	for _, item in ipairs(items) do
		if item.itemType == itemType then
			table.insert(filtered, item)
		end
	end
	return filtered
end

function WorkshopService.Client:EquipItem(player: Player, itemId: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	-- Find the item
	local crafted = data.CraftedItems or {}
	local item = nil
	for _, it in ipairs(crafted) do
		if it.id == itemId then
			item = it
			break
		end
	end
	if not item then
		return { success = false, error = "Item not found" }
	end

	local character = player.Character
	if not character then
		return { success = false, error = "No character" }
	end

	local equipped = data.Equipped or {}
	local itemType = item.itemType

	if itemType == "costume" then
		-- Costumes override accessories — auto-unequip accessories and tools
		if equipped.accessory then
			removeEquippedVisuals(character, "accessory")
			equipped.accessory = nil
		end
		if equipped.tool then
			removeEquippedVisuals(character, "tool")
			equipped.tool = nil
		end

		-- Remove previous costume if any
		if equipped.costume then
			removeCostume(player)
		end

		-- Apply new costume via OrigamiService:ApplyAvatar
		if item.modelData then
			applyCostume(player, item.modelData)
		end
		equipped.costume = itemId
	elseif itemType == "accessory" then
		-- Can't equip accessories while wearing a costume
		if equipped.costume then
			return { success = false, error = "Remove costume first" }
		end

		-- Remove previous accessory
		if equipped.accessory then
			removeEquippedVisuals(character, "accessory")
		end

		-- Weld accessory to body part
		if item.modelData then
			local attachPoint = item.attachPoint or "Head"
			weldToBodyPart(character, item.modelData, attachPoint, "OrigamiAccessory")
		end
		equipped.accessory = itemId
	elseif itemType == "tool" then
		-- Can't equip tools while wearing a costume
		if equipped.costume then
			return { success = false, error = "Remove costume first" }
		end

		-- Remove previous tool
		if equipped.tool then
			removeEquippedVisuals(character, "tool")
		end

		-- Weld tool to RightHand
		if item.modelData then
			weldToBodyPart(character, item.modelData, "RightHand", "OrigamiTool")
		end

		-- Store tool stats as attributes on character for combat systems
		if item.toolStats then
			character:SetAttribute("WorkshopToolDamage", item.toolStats.damage)
			character:SetAttribute("WorkshopToolSpeed", item.toolStats.speed)
			character:SetAttribute("WorkshopToolRange", item.toolStats.range)
		end
		equipped.tool = itemId
	else
		return { success = false, error = "Cannot equip props — use PlaceProp" }
	end

	PlayerDataService:Write(player, { "Equipped" }, equipped)
	self.ItemEquipped:Fire(player, itemId, itemType)

	return { success = true }
end

function WorkshopService.Client:UnequipItem(player: Player, itemType: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local equipped = data.Equipped or {}
	local character = player.Character

	if itemType == "costume" then
		if equipped.costume and character then
			removeCostume(player)
		end
		equipped.costume = nil
	elseif itemType == "accessory" then
		if equipped.accessory and character then
			removeEquippedVisuals(character, "accessory")
		end
		equipped.accessory = nil
	elseif itemType == "tool" then
		if equipped.tool and character then
			removeEquippedVisuals(character, "tool")
			character:SetAttribute("WorkshopToolDamage", nil)
			character:SetAttribute("WorkshopToolSpeed", nil)
			character:SetAttribute("WorkshopToolRange", nil)
		end
		equipped.tool = nil
	else
		return { success = false, error = "Invalid item type" }
	end

	PlayerDataService:Write(player, { "Equipped" }, equipped)
	self.ItemUnequipped:Fire(player, itemType)

	return { success = true }
end

function WorkshopService.Client:DeleteItem(player: Player, itemId: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	-- Check if equipped — unequip first
	local equipped = data.Equipped or {}
	local character = player.Character
	if equipped.accessory == itemId then
		if character then
			removeEquippedVisuals(character, "accessory")
		end
		equipped.accessory = nil
		PlayerDataService:Write(player, { "Equipped" }, equipped)
	elseif equipped.tool == itemId then
		if character then
			removeEquippedVisuals(character, "tool")
			character:SetAttribute("WorkshopToolDamage", nil)
			character:SetAttribute("WorkshopToolSpeed", nil)
			character:SetAttribute("WorkshopToolRange", nil)
		end
		equipped.tool = nil
		PlayerDataService:Write(player, { "Equipped" }, equipped)
	elseif equipped.costume == itemId then
		if character then
			removeCostume(player)
		end
		equipped.costume = nil
		PlayerDataService:Write(player, { "Equipped" }, equipped)
	end

	-- Remove from PlacedProps if it's there
	local placed = data.PlacedProps or {}
	local newPlaced = {}
	for _, prop in ipairs(placed) do
		if prop.itemId ~= itemId then
			table.insert(newPlaced, prop)
		end
	end
	if #newPlaced ~= #placed then
		PlayerDataService:Write(player, { "PlacedProps" }, newPlaced)
	end

	-- Remove from collection
	local crafted = data.CraftedItems or {}
	local newCrafted = {}
	for _, item in ipairs(crafted) do
		if item.id ~= itemId then
			table.insert(newCrafted, item)
		end
	end
	PlayerDataService:Write(player, { "CraftedItems" }, newCrafted)

	return { success = true }
end

function WorkshopService.Client:RenameItem(player: Player, itemId: string, newName: string)
	if not newName or type(newName) ~= "string" then
		return { success = false, error = "Invalid name" }
	end
	newName = newName:sub(1, 40):match("^%s*(.-)%s*$") or ""
	if #newName == 0 then
		return { success = false, error = "Name cannot be empty" }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local crafted = data.CraftedItems or {}
	for _, item in ipairs(crafted) do
		if item.id == itemId then
			item.name = newName
			PlayerDataService:Write(player, { "CraftedItems" }, crafted)
			return { success = true }
		end
	end

	return { success = false, error = "Item not found" }
end

function WorkshopService.Client:PlaceProp(
	player: Player,
	itemId: string,
	localX: number,
	localY: number,
	localZ: number
)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	-- Verify item exists and is a prop
	local crafted = data.CraftedItems or {}
	local item = nil
	for _, it in ipairs(crafted) do
		if it.id == itemId then
			item = it
			break
		end
	end
	if not item then
		return { success = false, error = "Item not found" }
	end
	if item.itemType ~= "prop" then
		return { success = false, error = "Only props can be placed" }
	end

	-- Check plot ownership
	local plotData = data.PlotData
	if not plotData or plotData.plotIndex == -1 then
		return { success = false, error = "No plot claimed" }
	end

	-- Add to PlacedProps (or update if already placed)
	local placed = data.PlacedProps or {}
	local found = false
	for i, prop in ipairs(placed) do
		if prop.itemId == itemId then
			placed[i] = { itemId = itemId, localX = localX, localY = localY, localZ = localZ }
			found = true
			break
		end
	end
	if not found then
		table.insert(placed, { itemId = itemId, localX = localX, localY = localY, localZ = localZ })
	end

	PlayerDataService:Write(player, { "PlacedProps" }, placed)

	return { success = true }
end

function WorkshopService.Client:GetEquipped(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return {}
	end
	return data.Equipped or {}
end

------------------------------------------------------
-- Re-equip on rejoin
------------------------------------------------------

local function reequipOnSpawn(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return
	end

	local equipped = data.Equipped or {}
	local crafted = data.CraftedItems or {}

	-- Build lookup
	local itemById = {}
	for _, item in ipairs(crafted) do
		itemById[item.id] = item
	end

	local character = player.Character
	if not character then
		return
	end

	-- Wait for character to be fully loaded
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	character:WaitForChild("HumanoidRootPart", 5)

	-- Apply costume first (it overrides accessories/tools)
	if equipped.costume then
		local item = itemById[equipped.costume]
		if item and item.modelData then
			applyCostume(player, item.modelData)
		end
	else
		-- Apply accessory
		if equipped.accessory then
			local item = itemById[equipped.accessory]
			if item and item.modelData then
				local attachPoint = item.attachPoint or "Head"
				weldToBodyPart(character, item.modelData, attachPoint, "OrigamiAccessory")
			end
		end

		-- Apply tool
		if equipped.tool then
			local item = itemById[equipped.tool]
			if item and item.modelData then
				weldToBodyPart(character, item.modelData, "RightHand", "OrigamiTool")
				if item.toolStats then
					character:SetAttribute("WorkshopToolDamage", item.toolStats.damage)
					character:SetAttribute("WorkshopToolSpeed", item.toolStats.speed)
					character:SetAttribute("WorkshopToolRange", item.toolStats.range)
				end
			end
		end
	end
end

------------------------------------------------------
-- Lifecycle
------------------------------------------------------

function WorkshopService:KnitInit() end

function WorkshopService:KnitStart()
	-- Re-equip items when players spawn/respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				reequipOnSpawn(player)
			end)
		end)
	end)

	-- Handle already-connected players (Studio fast-start)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.delay(1, function()
				reequipOnSpawn(player)
			end)
		end
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				reequipOnSpawn(player)
			end)
		end)
	end
end

return WorkshopService
