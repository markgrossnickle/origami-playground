--!strict
--[=[
	@class MockPlayer
	Creates a fake Player object for testing services.
]=]

local MockInstance = require("./MockInstance")

local MockPlayer = {}

export type MockPlayer = {
	Name: string,
	UserId: number,
	Team: any?,
	Character: MockInstance.MockInstance?,
	AccountAge: number,
	MembershipType: number,
	_attributes: { [string]: any },
	GetAttribute: (self: MockPlayer, name: string) -> any?,
	SetAttribute: (self: MockPlayer, name: string, value: any) -> (),
}

function MockPlayer.new(overrides: { [string]: any }?): MockPlayer
	local o = overrides or {}
	local player: MockPlayer = {
		Name = o.Name or "TestPlayer",
		UserId = o.UserId or 12345,
		Team = o.Team or nil,
		Character = o.Character or MockInstance.new("Model", { Name = "TestPlayer" }),
		AccountAge = o.AccountAge or 365,
		MembershipType = o.MembershipType or 0,
		_attributes = {},

		GetAttribute = function(self: MockPlayer, name: string): any?
			return self._attributes[name]
		end,

		SetAttribute = function(self: MockPlayer, name: string, value: any)
			self._attributes[name] = value
		end,
	}
	return player
end

return MockPlayer
