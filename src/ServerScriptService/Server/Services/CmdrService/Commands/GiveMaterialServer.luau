local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, player, materialId, amount)
	local PlayerDataService = Knit.GetService("PlayerDataService")

	local currentCount = PlayerDataService:Read(player, { "MiningInventory", materialId }) or 0
	PlayerDataService:Write(player, { "MiningInventory", materialId }, currentCount + amount)

	return string.format("Gave %d %s to %s (now has %d).", amount, materialId, player.Name, currentCount + amount)
end
