--!strict
-- BlockType: Paper-themed block type enum for the mining world

local BlockType = {
	Air = 0,
	Bedrock = 1,
	PaperGrass = 2,
	PaperDirt = 3,
	Cardboard = 4,
	PaperSand = 5,
	Cardstock = 6,
	Corrugated = 7,
	Manila = 8,
	Parchment = 9,
	PressedBoard = 10,
	PaperLog = 11,
	PaperLeaves = 12,
	TissueOre = 13,
	CrepeOre = 14,
	FoilOre = 15,
	VellumOre = 16,
	CrystalOre = 17,
	NeonOre = 18,
	Water = 19,
}

export type BlockType = number

return BlockType
