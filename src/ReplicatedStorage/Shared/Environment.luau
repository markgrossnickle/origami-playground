local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Enums = require(ReplicatedStorage.Shared.Enums)
local EnvironmentEnum = Enums.Environment

-- All other game IDs default to Production
local DefaultEnvironment = EnvironmentEnum.Production

-- These game IDs are explicitly set to a specific environment
local GameIds = {
	-- [GameId as string]: EnvironmentEnum (string)
	-- https://create.roblox.com/dashboard/creations/experiences/9068389781/overview
	["-1"] = EnvironmentEnum.Production,
	["-2"] = EnvironmentEnum.Review,
	-- https://create.roblox.com/dashboard/creations/experiences/87323133780360/overview
	["-3"] = EnvironmentEnum.Staging,
}

local Environment = GameIds[tostring(game.GameId)] or DefaultEnvironment
if RunService:IsStudio() then
	Environment = EnvironmentEnum.Studio
end

return Environment
