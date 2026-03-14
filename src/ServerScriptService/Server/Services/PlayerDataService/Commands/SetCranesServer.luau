--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, player: Player, amount: number)
	amount = math.clamp(math.floor(amount), 0, 99999)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local old = PlayerDataService:Read(player, { "Cranes" }) or 0
	PlayerDataService:Write(player, { "Cranes" }, amount)
	return `Set {player.Name}'s Cranes: {old} -> {amount}`
end
