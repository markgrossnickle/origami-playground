local Environment = require(script.Environment)

local Enums = {
	Environment = Environment,
}

export type Enums = typeof(Enums)

export type Environment = Environment.Environment

return Enums
