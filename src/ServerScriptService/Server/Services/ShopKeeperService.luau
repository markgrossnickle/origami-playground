--[[
	ShopKeeperService — spawns shopkeeper NPCs and signals clients when a player
	interacts with a shop's ProximityPrompt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ShopKeeperService = Knit.CreateService({
	Name = "ShopKeeperService",
	Client = {
		ShopOpened = Knit.CreateSignal(), -- (shopId: string, shopType: string, lockedModel: string)
	},
})

function ShopKeeperService:KnitInit() end

function ShopKeeperService:KnitStart()
	local ShopKeepers = require(ReplicatedStorage.Shared.ShopKeepers)
	ShopKeepers.Build(self)
end

return ShopKeeperService
