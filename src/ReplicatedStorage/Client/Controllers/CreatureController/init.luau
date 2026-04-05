--[[
	CreatureController — stub. UI moved to BackpackController.
	Kept alive for Knit registration only. DespawnActiveCreature is now a no-op;
	BackpackController owns creature spawning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CreatureController = Knit.CreateController({ Name = "CreatureController" })

function CreatureController:KnitInit() end

function CreatureController:KnitStart() end

function CreatureController:DespawnActiveCreature() end

return CreatureController
