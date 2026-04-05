--[[
	EggCraftingController — stub. UI moved to BackpackController.
	Kept alive for Knit registration only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local EggCraftingController = Knit.CreateController({ Name = "EggCraftingController" })

function EggCraftingController:KnitInit() end

function EggCraftingController:KnitStart() end

return EggCraftingController
