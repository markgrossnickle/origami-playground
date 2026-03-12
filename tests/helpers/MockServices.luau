--!strict
--[=[
	@class MockServices
	Provides mock Roblox service globals for testing.
]=]

local MockSignal = require("./MockSignal")
local MockInstance = require("./MockInstance")

local MockServices = {}

-- Mock Players service
function MockServices.createPlayers()
	return {
		_players = {} :: { any },
		PlayerAdded = MockSignal.new(),
		PlayerRemoving = MockSignal.new(),
		GetPlayers = function(self: any): { any }
			return self._players
		end,
		-- Helper: add a player to the mock
		_addPlayer = function(self: any, player: any)
			table.insert(self._players, player)
			self.PlayerAdded:Fire(player)
		end,
		-- Helper: remove a player from the mock
		_removePlayer = function(self: any, player: any)
			for i, p in self._players do
				if p == player then
					table.remove(self._players, i)
					break
				end
			end
			self.PlayerRemoving:Fire(player)
		end,
	}
end

-- Mock ReplicatedStorage
function MockServices.createReplicatedStorage()
	return MockInstance.new("ReplicatedStorage")
end

-- Mock ServerScriptService
function MockServices.createServerScriptService()
	return MockInstance.new("ServerScriptService")
end

-- Mock RunService
function MockServices.createRunService()
	return {
		IsStudio = function(): boolean
			return true
		end,
		IsServer = function(): boolean
			return true
		end,
		IsClient = function(): boolean
			return false
		end,
		Heartbeat = MockSignal.new(),
		Stepped = MockSignal.new(),
	}
end

-- Mock CollectionService
function MockServices.createCollectionService()
	local tags: { [string]: { any } } = {}
	return {
		GetTagged = function(_self: any, tag: string): { any }
			return tags[tag] or {}
		end,
		AddTag = function(_self: any, instance: any, tag: string)
			if not tags[tag] then
				tags[tag] = {}
			end
			table.insert(tags[tag], instance)
		end,
		RemoveTag = function(_self: any, instance: any, tag: string)
			if tags[tag] then
				for i, inst in tags[tag] do
					if inst == instance then
						table.remove(tags[tag], i)
						break
					end
				end
			end
		end,
		HasTag = function(_self: any, instance: any, tag: string): boolean
			if not tags[tag] then
				return false
			end
			for _, inst in tags[tag] do
				if inst == instance then
					return true
				end
			end
			return false
		end,
	}
end

return MockServices
