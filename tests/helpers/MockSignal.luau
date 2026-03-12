--!strict
--[=[
	@class MockSignal
	A simple signal implementation for testing.
	Mimics RBXScriptSignal / Knit Signal interface.
]=]

local MockSignal = {}
MockSignal.__index = MockSignal

export type MockConnection = {
	Connected: boolean,
	Disconnect: (self: MockConnection) -> (),
}

export type MockSignal<T...> = typeof(setmetatable(
	{} :: {
		_listeners: { (...any) -> () },
	},
	MockSignal
))

function MockSignal.new(): MockSignal<...any>
	return setmetatable({
		_listeners = {},
	}, MockSignal) :: any
end

function MockSignal.Connect(self: MockSignal<...any>, fn: (...any) -> ()): MockConnection
	table.insert(self._listeners, fn)
	local index = #self._listeners
	local connection: MockConnection = {
		Connected = true,
		Disconnect = function(conn: MockConnection)
			conn.Connected = false
			-- Remove by finding the function
			for i, listener in self._listeners do
				if listener == fn then
					table.remove(self._listeners, i)
					break
				end
			end
		end,
	}
	return connection
end

function MockSignal.Fire(self: MockSignal<...any>, ...: any)
	-- Copy listeners in case a handler disconnects during iteration
	local listeners = table.clone(self._listeners)
	for _, fn in listeners do
		fn(...)
	end
end

function MockSignal.DisconnectAll(self: MockSignal<...any>)
	table.clear(self._listeners)
end

return MockSignal
