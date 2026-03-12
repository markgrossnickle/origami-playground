--!strict
--[=[
	Tests for GameConfig: validates that all config values are valid and consistent.
]=]

local fs = require("@lune/fs")
local t = require("../framework")
local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach

local function loadGameConfig(): { [string]: any }
	local source = fs.readFile("src/ReplicatedStorage/Shared/GameConfig.luau")
	source = source:gsub("%-%-!strict\n", "")
	local chunk = assert(loadstring(source, "@GameConfig"))
	return chunk()
end

local GameConfig: any = nil

describe("GameConfig", function()
	beforeEach(function()
		GameConfig = loadGameConfig()
	end)

	it("should have a Player section", function()
		expect(GameConfig.Player).to.be.ok()
	end)

	it("should have positive player MaxHP", function()
		expect(GameConfig.Player.MaxHP).to.be.greaterThan(0)
	end)

	it("should have positive WalkSpeed", function()
		expect(GameConfig.Player.WalkSpeed).to.be.greaterThan(0)
	end)

	it("should have positive JumpPower", function()
		expect(GameConfig.Player.JumpPower).to.be.greaterThan(0)
	end)

	it("should have non-negative RespawnTime", function()
		expect(GameConfig.Player.RespawnTime).to.be.greaterThanOrEqual(0)
	end)

	it("should have an Economy section", function()
		expect(GameConfig.Economy).to.be.ok()
	end)

	it("should have non-negative starting currencies", function()
		expect(GameConfig.Economy.StartingCoins).to.be.greaterThanOrEqual(0)
		expect(GameConfig.Economy.StartingGems).to.be.greaterThanOrEqual(0)
	end)

	it("should have max currencies greater than starting currencies", function()
		expect(GameConfig.Economy.MaxCoins).to.be.greaterThan(GameConfig.Economy.StartingCoins)
		expect(GameConfig.Economy.MaxGems).to.be.greaterThan(GameConfig.Economy.StartingGems)
	end)

	it("should have a Gameplay section", function()
		expect(GameConfig.Gameplay).to.be.ok()
	end)

	it("should have positive MaxPlayersPerTeam", function()
		expect(GameConfig.Gameplay.MaxPlayersPerTeam).to.be.greaterThan(0)
	end)

	it("should have positive round duration", function()
		expect(GameConfig.Gameplay.RoundDuration).to.be.greaterThan(0)
	end)

	it("should have positive intermission duration", function()
		expect(GameConfig.Gameplay.IntermissionDuration).to.be.greaterThan(0)
	end)

	it("should have round duration longer than intermission", function()
		expect(GameConfig.Gameplay.RoundDuration).to.be.greaterThan(GameConfig.Gameplay.IntermissionDuration)
	end)
end)
