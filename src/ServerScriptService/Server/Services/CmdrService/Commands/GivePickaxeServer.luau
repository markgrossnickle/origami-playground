local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local ToolRegistry = require(ReplicatedStorage.Shared.ToolRegistry)

return function(_context, player, toolId)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local MiningService = Knit.GetService("MiningService")

	local toolConfig = ToolRegistry.get(toolId)
	if not toolConfig then
		return "Unknown tool: " .. toolId
	end

	-- Add to inventory
	local currentCount = PlayerDataService:Read(player, { "MiningInventory", "tools", toolId }) or 0
	PlayerDataService:Write(player, { "MiningInventory", "tools", toolId }, currentCount + 1)

	-- Equip it
	PlayerDataService:Write(player, { "EquippedTool" }, toolId)
	MiningService.Client.ToolEquipped:Fire(player, toolId)

	return string.format("Gave %s to %s and equipped it.", toolConfig.name, player.Name)
end
