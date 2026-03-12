--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Environment = require(ReplicatedStorage.Shared.Environment)

local CmdrHelper = {}

local GROUP_ID = 361311171
-- Rank: Developer
local MIN_RANK = 252

function CmdrHelper.HasCmdrPermissions(player: Player): boolean
	-- Always allow in Studio

	if RunService:IsStudio() then
		return true
	end

	--Always allow non-production environments
	if Environment ~= Enums.Environment.Production and Environment ~= Enums.Environment.Review then
		return true
	end

	local rank = player:GetRankInGroupAsync(GROUP_ID)
	return rank >= MIN_RANK
end

function CmdrHelper.RegisterCmdrContent(registry, container: Instance)
	local didRegisterSomething = false
	local hooks = container:FindFirstChild("Hooks")
	if hooks then
		registry:RegisterHooksIn(hooks)
		didRegisterSomething = true
	end
	local types = container:FindFirstChild("Types")
	if types then
		registry:RegisterTypesIn(types)
		didRegisterSomething = true
	end
	local commands = container:FindFirstChild("Commands")
	if commands then
		registry:RegisterCommandsIn(commands)
		didRegisterSomething = true
	end
	if not didRegisterSomething then
		warn("No Cmdr content found in " .. container:GetFullName())
	end
end

return CmdrHelper
