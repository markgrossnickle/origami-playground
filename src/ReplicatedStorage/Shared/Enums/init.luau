local Environment = require(script.Environment)
local BlockType = require(script.BlockType)

local Enums = {
	Environment = Environment,
	BlockType = BlockType,
}

export type Enums = typeof(Enums)

export type Environment = Environment.Environment
export type BlockType = BlockType.BlockType

return Enums
