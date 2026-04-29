local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local MaterialTiers = require(ReplicatedStorage.Shared.MaterialTiers)

local function _namespaceFor(materialId: string): string
	local role = MaterialTiers.getRole(materialId)
	if role == "bulk" or role == "ore" then
		return role
	end
	return "misc"
end

return function(_context, player, materialId, amount)
	local PlayerDataService = Knit.GetService("PlayerDataService")

	local namespace = _namespaceFor(materialId)
	local currentCount = PlayerDataService:Read(player, { "MiningInventory", namespace, materialId }) or 0
	PlayerDataService:Write(player, { "MiningInventory", namespace, materialId }, currentCount + amount)

	return string.format("Gave %d %s to %s (now has %d).", amount, materialId, player.Name, currentCount + amount)
end
