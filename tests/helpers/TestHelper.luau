--!strict
--[=[
	@class TestHelper
	Common test utilities for assertions and mock data creation.
]=]

local TestHelper = {}

-- Deep equality check for tables
function TestHelper.deepEqual(a: any, b: any): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) ~= "table" then
		return a == b
	end
	for key, value in a :: { [any]: any } do
		if not TestHelper.deepEqual(value, (b :: { [any]: any })[key]) then
			return false
		end
	end
	for key, _ in b :: { [any]: any } do
		if (a :: { [any]: any })[key] == nil then
			return false
		end
	end
	return true
end

function TestHelper.assertEquals(actual: any, expected: any, message: string?)
	if actual ~= expected then
		local msg = message or `Expected {tostring(expected)}, got {tostring(actual)}`
		error(msg, 2)
	end
end

function TestHelper.assertNear(actual: number, expected: number, tolerance: number?, message: string?)
	local tol = tolerance or 0.001
	if math.abs(actual - expected) > tol then
		local msg = message or `Expected {expected} +/- {tol}, got {actual}`
		error(msg, 2)
	end
end

function TestHelper.assertTableEquals(actual: any, expected: any, message: string?)
	if not TestHelper.deepEqual(actual, expected) then
		local msg = message or "Tables are not equal"
		error(msg, 2)
	end
end

function TestHelper.assertThrows(fn: () -> (), expectedError: string?)
	local ok, err = pcall(fn)
	if ok then
		error("Expected function to throw, but it didn't", 2)
	end
	if expectedError and not string.find(tostring(err), expectedError, 1, true) then
		error(`Expected error containing "{expectedError}", got "{tostring(err)}"`, 2)
	end
end

function TestHelper.assertTruthy(value: any, message: string?)
	if not value then
		error(message or `Expected truthy value, got {tostring(value)}`, 2)
	end
end

function TestHelper.assertFalsy(value: any, message: string?)
	if value then
		error(message or `Expected falsy value, got {tostring(value)}`, 2)
	end
end

-- Creates a mock GameConfig with sensible defaults, with optional overrides
function TestHelper.createMockGameConfig(overrides: { [string]: any }?): { [string]: any }
	local config = {
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
	if overrides then
		for key, value in overrides do
			if typeof(value) == "table" and typeof(config[key]) == "table" then
				for k, v in value :: { [string]: any } do
					(config[key] :: { [string]: any })[k] = v
				end
			else
				config[key] = value
			end
		end
	end
	return config
end

-- Creates a mock PlayerData structure with optional overrides
function TestHelper.createMockPlayerData(overrides: { [string]: any }?): { [string]: any }
	local data = {
		Coins = 0,
		Gems = 0,
		Level = 1,
		XP = 0,
		SessionCount = 0,
		TotalPlayTime = 0,
		DailyRewardDay = 0,
		DailyRewardLastClaim = 0,
		Purchases = {},
		Inventory = {},
	}
	if overrides then
		for key, value in overrides do
			data[key] = value
		end
	end
	return data
end

return TestHelper
