-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Badge = game:GetService("BadgeService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

-- Modules
local BadgeData = require(ReplicatedStorage.Shared.BadgeData)

-- Types
type BadgeData = BadgeData.BadgeData

-- Constants
local ROBLOX_BULK_RATELIMIT = 10

local BadgeService = Knit.CreateService({
	Name = "BadgeService",
	BadgeAwarded = Signal.new(),
	Client = {
		BadgeAwarded = Knit.CreateSignal(), -- sends bool if badge was successfully awarded, and corresponding badge data
	},
})

BadgeService.Badges = {}

function BadgeService:KnitStart() end

function BadgeService:KnitInit()
	self:LoadBadgeData()
end

-- Initialize BadgeData with live BadgeInfo from Roblox
function BadgeService:LoadBadgeData()
	-- Prevent loading badges from hanging up the rest of the inits
	task.defer(function()
		local gameIdString = `{game.GameId}`
		local badgeData = BadgeData[gameIdString]
		if not badgeData or not badgeData.Badges then
			return
		end
		for _, badgeId in badgeData.Badges do
			local badge = {
				Id = badgeId,
			}
			local success, badgeInfo = pcall(function()
				return Badge:GetBadgeInfoAsync(badgeId)
			end)
			if success then
				for key, value in badgeInfo do
					badge[key] = value
				end
				self.Badges[badgeId] = badge
			else
				warn("Unable to load BadgeID:", badge.Id)
			end
		end
	end)
end

--[[
    Returns Badge Data
    @param Id number - Id of the specific badge
]]
function BadgeService:GetBadgeData(Id: number)
	return self.Badges[Id]
end

--[[
    @param player -- Player to award badge to
    @param Id number -- Id of badge to award
]]
function BadgeService:AwardBadge(player: Player, Id: number): boolean
	if not (self.Badges[Id] and self.Badges[Id].IsEnabled) then
		warn("AwardBadge failure. Badge ID invaid, or Badge is not enabled.")
		return false
	end
	local success, result = pcall(function()
		return Badge:AwardBadge(player.UserId, Id)
	end)

	if not success then
		warn("Error when awarding Badge.", result)
		return false
	end

	local wasAwarded = (success and RunService:IsStudio()) or result
	if not wasAwarded then
		warn("Failed to award Badge.")
	end
	self.BadgeAwarded:Fire(player, wasAwarded, self.Badges[Id])
	self.Client.BadgeAwarded:Fire(player, wasAwarded, self.Badges[Id])
	return wasAwarded
end

--[[
    @param player -- Player we are checking
    @param Id number -- Id of badge to check
]]
function BadgeService:UserHasBadge(player: Player, Id: number): boolean
	if not self.Badges[Id] then
		warn("UserHasBadge failure. Badge ID invalid.")
		return false
	end
	local success, hasBadge = pcall(function()
		return Badge:UserHasBadgeAsync(player.UserId, Id)
	end)

	if not success then
		warn("Error when checking for badge.")
		return false
	end
	return hasBadge
end

--[[
    @param player -- Player we are checking
    @param Id array of numbers -- Ids of badges to check
	returns an array of BadgeIds the player has
]]
function BadgeService:UserHasBadgeBulk(player: Player, Ids: { number }): { number }
	local batchSize = ROBLOX_BULK_RATELIMIT
	local numFullBatches = math.floor(#Ids / batchSize)
	local remainingElements = #Ids % batchSize

	local badgeList = {}
	for i = 1, numFullBatches do
		local batchStart = (i - 1) * batchSize + 1
		local batchEnd = i * batchSize

		local batch = {}
		for j = batchStart, batchEnd do
			table.insert(batch, Ids[j])
		end

		local success, result = pcall(function()
			return Badge:CheckUserBadgesAsync(player.UserId, batch)
		end)
		if not success then
			warn("Unable to process a batch of Ids.", result)
		else
			for _, value in result do
				table.insert(badgeList, value)
			end
		end
	end

	if remainingElements > 0 then
		local batchStart = numFullBatches * batchSize + 1
		local batchEnd = #Ids

		local batch = {}
		for j = batchStart, batchEnd do
			table.insert(batch, Ids[j])
		end

		local success, result = pcall(function()
			return Badge:CheckUserBadgesAsync(player.UserId, batch)
		end)
		if not success then
			warn("Unable to process a batch of Ids.", result)
		else
			for _, value in result do
				table.insert(badgeList, value)
			end
		end
	end
	return badgeList
end

function BadgeService.Client:GetBadgeData(_player: Player, Id: number)
	return self.Server:GetBadgeData(Id)
end

function BadgeService.Client:UserHasBadge(player: Player, Id: number)
	return self.Server:UserHasBadge(player, Id)
end

return BadgeService
