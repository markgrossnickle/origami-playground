--!strict
--[=[
	@class MockInstance
	Creates fake Roblox instances for testing.
]=]

local MockInstance = {}

export type MockInstance = {
	ClassName: string,
	Name: string,
	Parent: MockInstance?,
	_children: { MockInstance },
	_attributes: { [string]: any },
	_properties: { [string]: any },
	_destroyed: boolean,
	FindFirstChild: (self: MockInstance, name: string) -> MockInstance?,
	GetChildren: (self: MockInstance) -> { MockInstance },
	SetAttribute: (self: MockInstance, name: string, value: any) -> (),
	GetAttribute: (self: MockInstance, name: string) -> any?,
	Destroy: (self: MockInstance) -> (),
	Clone: (self: MockInstance) -> MockInstance,
	IsA: (self: MockInstance, className: string) -> boolean,
}

local MockInstanceMT = {}
MockInstanceMT.__index = function(self: any, key: string): any
	-- Check methods first
	local methods = rawget(self, "_methods")
	if methods and methods[key] then
		return methods[key]
	end
	-- Check properties
	local props = rawget(self, "_properties")
	if props and props[key] ~= nil then
		return props[key]
	end
	-- Check children by name
	local children = rawget(self, "_children")
	if children then
		for _, child in children do
			if child.Name == key then
				return child
			end
		end
	end
	return nil
end

function MockInstance.new(className: string, props: { [string]: any }?): MockInstance
	local p = props or {}

	local instance: any = {
		ClassName = className,
		Name = p.Name or className,
		Parent = p.Parent or nil,
		_children = {},
		_attributes = {},
		_properties = {},
		_destroyed = false,
	}

	-- Copy extra props into _properties
	for key, value in p do
		if key ~= "Name" and key ~= "Parent" then
			instance._properties[key] = value
		end
	end

	instance._methods = {
		FindFirstChild = function(self: any, name: string): MockInstance?
			for _, child in self._children do
				if child.Name == name then
					return child
				end
			end
			return nil
		end,

		GetChildren = function(self: any): { MockInstance }
			return self._children
		end,

		SetAttribute = function(self: any, name: string, value: any)
			self._attributes[name] = value
		end,

		GetAttribute = function(self: any, name: string): any?
			return self._attributes[name]
		end,

		Destroy = function(self: any)
			self._destroyed = true
			self.Parent = nil
		end,

		Clone = function(self: any): MockInstance
			local clone = MockInstance.new(self.ClassName, { Name = self.Name })
			for key, value in self._attributes do
				(clone :: any)._attributes[key] = value
			end
			for key, value in self._properties do
				(clone :: any)._properties[key] = value
			end
			return clone
		end,

		IsA = function(self: any, className: string): boolean
			return self.ClassName == className
		end,
	}

	return setmetatable(instance, MockInstanceMT) :: any
end

-- Helper to add a child to a mock instance
function MockInstance.addChild(parent: MockInstance, child: MockInstance)
	table.insert((parent :: any)._children, child);
	(child :: any).Parent = parent
end

return MockInstance
