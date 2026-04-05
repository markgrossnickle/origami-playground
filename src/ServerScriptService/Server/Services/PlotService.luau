--[[
	PlotService — server-side surface plot management.
	Claim plots, place/remove blocks, assign/unassign creatures.
	Blocks stored as dictionary: { "x,y,z" = materialId } in PlayerData.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PlotConfig = require(ReplicatedStorage.Shared.PlotConfig)

local PlotService = Knit.CreateService({
	Name = "PlotService",
	Client = {
		BlockPlaced = Knit.CreateSignal(), -- (ownerUserId, key, materialId)
		BlockRemoved = Knit.CreateSignal(), -- (ownerUserId, key)
		CreatureAssigned = Knit.CreateSignal(), -- (ownerUserId, creatureId, localX, localZ)
		CreatureUnassigned = Knit.CreateSignal(), -- (ownerUserId, creatureId)
	},
})

-- Track claimed plot indices to prevent double-claims
local _claimedPlots: { [number]: number } = {} -- plotIndex → userId
local _nextPlotIndex = 0

-- Subscribers: userId → { [Player]: true } for live updates when visiting plots
local _subscribers: { [number]: { [Player]: true } } = {}

local function getPlotData(player: Player): { [string]: any }?
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return nil
	end
	-- Migration: add PlotData if missing
	if not data.PlotData then
		data.PlotData = { plotIndex = -1, placedBlocks = {}, assignedCreatures = {} }
		PlayerDataService:Write(player, { "PlotData" }, data.PlotData)
	end
	return data.PlotData
end

local function countBlocks(placedBlocks: { [string]: string }): number
	local count = 0
	for _ in pairs(placedBlocks) do
		count += 1
	end
	return count
end

local function notifySubscribers(ownerUserId: number, signalName: string, ...)
	local subs = _subscribers[ownerUserId]
	if not subs then
		return
	end
	local signal = PlotService.Client[signalName]
	if not signal then
		return
	end
	for subscriber in pairs(subs) do
		if subscriber.Parent then
			signal:Fire(subscriber, ownerUserId, ...)
		else
			subs[subscriber] = nil
		end
	end
end

-- Claim a plot. Assigns a grid index to the player.
function PlotService.Client:ClaimPlot(player: Player)
	local plotData = getPlotData(player)
	if not plotData then
		return { success = false, error = "Player data not loaded" }
	end

	if plotData.plotIndex >= 0 then
		return { success = false, error = "You already have a plot", plotIndex = plotData.plotIndex }
	end

	-- Find next unclaimed index
	while _claimedPlots[_nextPlotIndex] do
		_nextPlotIndex += 1
	end

	local plotIndex = _nextPlotIndex
	_claimedPlots[plotIndex] = player.UserId
	_nextPlotIndex += 1

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:Write(player, { "PlotData", "plotIndex" }, plotIndex)

	return {
		success = true,
		plotIndex = plotIndex,
		origin = {
			PlotConfig.getPlotOrigin(plotIndex).X,
			PlotConfig.getPlotOrigin(plotIndex).Y,
			PlotConfig.getPlotOrigin(plotIndex).Z,
		},
	}
end

-- Place a block at local coordinates. Deducts material from MiningInventory.
function PlotService.Client:PlaceBlock(
	player: Player,
	localX: number,
	localY: number,
	localZ: number,
	materialItemId: string
)
	local plotData = getPlotData(player)
	if not plotData or plotData.plotIndex < 0 then
		return { success = false, error = "No plot claimed" }
	end

	-- Validate coordinates
	localX = math.floor(localX)
	localY = math.floor(localY)
	localZ = math.floor(localZ)
	if not PlotConfig.isInBounds(localX, localY, localZ) then
		return { success = false, error = "Out of bounds" }
	end

	-- Validate material
	if not PlotConfig.PLACEABLE_BLOCKS[materialItemId] then
		return { success = false, error = "Material not placeable" }
	end

	-- Check block limit
	if countBlocks(plotData.placedBlocks) >= PlotConfig.MAX_BLOCKS then
		return { success = false, error = "Block limit reached (" .. PlotConfig.MAX_BLOCKS .. ")" }
	end

	-- Check if position already occupied
	local key = string.format("%d,%d,%d", localX, localY, localZ)
	if plotData.placedBlocks[key] then
		return { success = false, error = "Position occupied" }
	end

	-- Check material in inventory
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local invCount = PlayerDataService:Read(player, { "MiningInventory", materialItemId }) or 0
	if invCount < 1 then
		return { success = false, error = "No " .. materialItemId:gsub("_", " ") .. " available" }
	end

	-- Deduct material
	PlayerDataService:Write(player, { "MiningInventory", materialItemId }, invCount - 1)

	-- Place block
	plotData.placedBlocks[key] = materialItemId
	PlayerDataService:Write(player, { "PlotData", "placedBlocks" }, plotData.placedBlocks)

	notifySubscribers(player.UserId, "BlockPlaced", key, materialItemId)

	return { success = true, key = key, materialId = materialItemId }
end

-- Remove a block at local coordinates. Refunds material to MiningInventory.
function PlotService.Client:RemoveBlock(player: Player, localX: number, localY: number, localZ: number)
	local plotData = getPlotData(player)
	if not plotData or plotData.plotIndex < 0 then
		return { success = false, error = "No plot claimed" }
	end

	localX = math.floor(localX)
	localY = math.floor(localY)
	localZ = math.floor(localZ)

	local key = string.format("%d,%d,%d", localX, localY, localZ)
	local materialItemId = plotData.placedBlocks[key]
	if not materialItemId then
		return { success = false, error = "No block at position" }
	end

	-- Refund material
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local invCount = PlayerDataService:Read(player, { "MiningInventory", materialItemId }) or 0
	PlayerDataService:Write(player, { "MiningInventory", materialItemId }, invCount + 1)

	-- Remove block
	plotData.placedBlocks[key] = nil
	PlayerDataService:Write(player, { "PlotData", "placedBlocks" }, plotData.placedBlocks)

	notifySubscribers(player.UserId, "BlockRemoved", key)

	return { success = true, refundedMaterial = materialItemId }
end

-- Assign a creature to the plot.
function PlotService.Client:AssignCreature(player: Player, creatureId: string, localX: number, localZ: number)
	local plotData = getPlotData(player)
	if not plotData or plotData.plotIndex < 0 then
		return { success = false, error = "No plot claimed" }
	end

	-- Validate creature exists
	local CreatureService = Knit.GetService("CreatureService")
	local creature = CreatureService:GetCreatureById(player, creatureId)
	if not creature then
		return { success = false, error = "Creature not found" }
	end

	-- Check creature limit
	local assigned = plotData.assignedCreatures or {}
	if #assigned >= PlotConfig.MAX_CREATURES then
		return { success = false, error = "Creature limit reached (" .. PlotConfig.MAX_CREATURES .. ")" }
	end

	-- Check not already assigned
	for _, entry in ipairs(assigned) do
		if entry.creatureId == creatureId then
			return { success = false, error = "Creature already assigned" }
		end
	end

	table.insert(assigned, { creatureId = creatureId, localX = localX, localZ = localZ })
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:Write(player, { "PlotData", "assignedCreatures" }, assigned)

	notifySubscribers(player.UserId, "CreatureAssigned", creatureId, localX, localZ)

	return { success = true }
end

-- Unassign a creature from the plot.
function PlotService.Client:UnassignCreature(player: Player, creatureId: string)
	local plotData = getPlotData(player)
	if not plotData or plotData.plotIndex < 0 then
		return { success = false, error = "No plot claimed" }
	end

	local assigned = plotData.assignedCreatures or {}
	for i, entry in ipairs(assigned) do
		if entry.creatureId == creatureId then
			table.remove(assigned, i)
			local PlayerDataService = Knit.GetService("PlayerDataService")
			PlayerDataService:Write(player, { "PlotData", "assignedCreatures" }, assigned)

			notifySubscribers(player.UserId, "CreatureUnassigned", creatureId)
			return { success = true }
		end
	end
	return { success = false, error = "Creature not assigned" }
end

-- Get your own plot data.
function PlotService.Client:GetPlotData(player: Player)
	local plotData = getPlotData(player)
	if not plotData then
		return nil
	end
	return {
		plotIndex = plotData.plotIndex,
		placedBlocks = plotData.placedBlocks,
		assignedCreatures = plotData.assignedCreatures,
		blockCount = countBlocks(plotData.placedBlocks),
		origin = if plotData.plotIndex >= 0
			then {
				PlotConfig.getPlotOrigin(plotData.plotIndex).X,
				PlotConfig.getPlotOrigin(plotData.plotIndex).Y,
				PlotConfig.getPlotOrigin(plotData.plotIndex).Z,
			}
			else nil,
	}
end

-- Get another player's plot data (for visiting).
function PlotService.Client:GetPlotDataForVisit(player: Player, ownerUserId: number)
	local Players = game:GetService("Players")
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return { success = false, error = "Player not found" }
	end

	local plotData = getPlotData(owner)
	if not plotData or plotData.plotIndex < 0 then
		return { success = false, error = "Player has no plot" }
	end

	return {
		success = true,
		plotIndex = plotData.plotIndex,
		placedBlocks = plotData.placedBlocks,
		assignedCreatures = plotData.assignedCreatures,
		blockCount = countBlocks(plotData.placedBlocks),
		origin = {
			PlotConfig.getPlotOrigin(plotData.plotIndex).X,
			PlotConfig.getPlotOrigin(plotData.plotIndex).Y,
			PlotConfig.getPlotOrigin(plotData.plotIndex).Z,
		},
		ownerName = owner.DisplayName,
	}
end

-- Subscribe to live updates for a plot (when visiting).
function PlotService.Client:SubscribePlot(player: Player, ownerUserId: number)
	if not _subscribers[ownerUserId] then
		_subscribers[ownerUserId] = {}
	end
	_subscribers[ownerUserId][player] = true
	return { success = true }
end

-- Unsubscribe from plot updates.
function PlotService.Client:UnsubscribePlot(player: Player, ownerUserId: number)
	if _subscribers[ownerUserId] then
		_subscribers[ownerUserId][player] = nil
	end
	return { success = true }
end

-- Get list of online players who have plots (for visit menu).
function PlotService.Client:GetPlotOwners(player: Player)
	local Players = game:GetService("Players")
	local owners = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p == player then
			continue
		end
		local pd = getPlotData(p)
		if pd and pd.plotIndex >= 0 then
			table.insert(owners, {
				userId = p.UserId,
				displayName = p.DisplayName,
				plotIndex = pd.plotIndex,
			})
		end
	end
	return owners
end

function PlotService:KnitInit()
	-- Restore claimed plots from existing player data on server start
	local Players = game:GetService("Players")
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local PlayerDataService = Knit.GetService("PlayerDataService")
			-- Wait for profile
			task.wait(3)
			local data = PlayerDataService:Read(player)
			if data and data.PlotData and data.PlotData.plotIndex >= 0 then
				_claimedPlots[data.PlotData.plotIndex] = player.UserId
				if data.PlotData.plotIndex >= _nextPlotIndex then
					_nextPlotIndex = data.PlotData.plotIndex + 1
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Clean up subscriptions
		for userId, subs in pairs(_subscribers) do
			subs[player] = nil
		end
		-- Note: don't unclaim plots — they persist
	end)
end

function PlotService:KnitStart() end

return PlotService
