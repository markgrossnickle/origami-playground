--!strict
--[=[
	Tests for the TestHelper module itself, ensuring assertions work correctly.
]=]

local t = require("../framework")
local describe, it, expect = t.describe, t.it, t.expect
local TestHelper = require("../helpers/TestHelper")

describe("TestHelper.assertEquals", function()
	it("should pass for equal values", function()
		TestHelper.assertEquals(1, 1)
		TestHelper.assertEquals("hello", "hello")
		TestHelper.assertEquals(true, true)
	end)

	it("should fail for unequal values", function()
		expect(function()
			TestHelper.assertEquals(1, 2)
		end).to.throw()
	end)
end)

describe("TestHelper.assertNear", function()
	it("should pass for values within tolerance", function()
		TestHelper.assertNear(1.001, 1.0, 0.01)
		TestHelper.assertNear(3.14159, 3.14, 0.01)
	end)

	it("should fail for values outside tolerance", function()
		expect(function()
			TestHelper.assertNear(1.0, 2.0, 0.01)
		end).to.throw()
	end)
end)

describe("TestHelper.assertTableEquals", function()
	it("should pass for equal tables", function()
		TestHelper.assertTableEquals({ 1, 2, 3 }, { 1, 2, 3 })
		TestHelper.assertTableEquals({ a = 1, b = "two" }, { a = 1, b = "two" })
	end)

	it("should pass for nested tables", function()
		TestHelper.assertTableEquals({ a = { b = 1 } }, { a = { b = 1 } })
	end)

	it("should fail for unequal tables", function()
		expect(function()
			TestHelper.assertTableEquals({ 1, 2 }, { 1, 3 })
		end).to.throw()
	end)
end)

describe("TestHelper.assertThrows", function()
	it("should pass when function throws", function()
		TestHelper.assertThrows(function()
			error("boom")
		end)
	end)

	it("should pass when error matches expected message", function()
		TestHelper.assertThrows(function()
			error("specific error")
		end, "specific error")
	end)

	it("should fail when function does not throw", function()
		expect(function()
			TestHelper.assertThrows(function() end)
		end).to.throw()
	end)
end)

describe("TestHelper.createMockGameConfig", function()
	it("should return default config", function()
		local config = TestHelper.createMockGameConfig()
		expect(config.Player.MaxHP).to.equal(100)
		expect(config.Economy.StartingCoins).to.equal(0)
	end)

	it("should apply overrides", function()
		local config = TestHelper.createMockGameConfig({ Player = { MaxHP = 200 } })
		expect(config.Player.MaxHP).to.equal(200)
		expect(config.Player.WalkSpeed).to.equal(16)
	end)
end)

describe("TestHelper.createMockPlayerData", function()
	it("should return default player data", function()
		local data = TestHelper.createMockPlayerData()
		expect(data.Coins).to.equal(0)
		expect(data.Level).to.equal(1)
	end)

	it("should apply overrides", function()
		local data = TestHelper.createMockPlayerData({ Coins = 500, Level = 10 })
		expect(data.Coins).to.equal(500)
		expect(data.Level).to.equal(10)
	end)
end)
