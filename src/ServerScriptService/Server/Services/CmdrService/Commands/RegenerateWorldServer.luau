local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, newSeed)
	local WorldService = Knit.GetService("WorldService")

	if newSeed == nil then
		newSeed = math.random(1, 2 ^ 31 - 1)
	end

	newSeed = math.floor(newSeed)
	if newSeed < 1 then
		return "Seed must be a positive number."
	end

	-- Unsubscribe all players from their current chunks
	for _, player in Players:GetPlayers() do
		WorldService:UnsubscribeAll(player)
	end

	-- Clear world state and set new seed
	WorldService:_clearAndReseed(newSeed)

	return string.format("World regenerated with seed %d. Chunks will reload as players move.", newSeed)
end
