--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, player: Player, amount: number)
	amount = math.clamp(math.floor(amount), 0, 999999)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local old = PlayerDataService:Read(player, { "Folds" }) or 0
	PlayerDataService:Write(player, { "Folds" }, amount)
	return `Set {player.Name}'s Folds: {old} -> {amount}`
end
