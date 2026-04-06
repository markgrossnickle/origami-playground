local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

return function(_context)
	local players = Players:GetPlayers()
	if #players == 0 then
		return "No players to teleport."
	end

	local placeId = game.PlaceId

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players)
	end)

	if ok then
		return string.format("Teleporting %d player(s) to reset the server.", #players)
	else
		return string.format("Failed to teleport: %s", tostring(err))
	end
end
