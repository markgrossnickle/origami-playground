--!strict
--[=[
	@class GameConfig
	Shared baseline configuration for runtime-tunable values.
	LiveConfigService reads this as the baseline. Use Cmdr to override at runtime.

	Organize values in nested tables by domain. Access via dot-path:
	  LiveConfigService:GetValue("Player.MaxHP") --> 100

	Add your game's tunable constants here.
]=]

local GameConfig = {
	Player = {
		MaxHP = 100,
		WalkSpeed = 16,
		JumpPower = 50,
		RespawnTime = 5,
	},
	Economy = {
		StartingCoins = 0,
		StartingGems = 0,
		MaxCoins = 999999,
		MaxGems = 99999,
	},
	Gameplay = {
		MaxPlayersPerTeam = 4,
		RoundDuration = 120,
		IntermissionDuration = 15,
	},
}

return GameConfig
