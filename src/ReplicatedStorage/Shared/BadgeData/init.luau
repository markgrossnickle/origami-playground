export type GameIdString = string
export type BadgeData = {
	gameId: number,
	Badges: { [number]: number },
}

local BadgeData = {
	-- 	Experience = {
	-- 		gameId = 0,
	-- 		Badges = require(script.ExampleBadgeData),
	-- 	},
} :: { [string]: BadgeData }

local newBadgeData = {} :: { [GameIdString]: BadgeData }
for _, badgeData: BadgeData in BadgeData do
	newBadgeData[tostring(badgeData.gameId)] = table.clone(badgeData)
end

table.clear(BadgeData)
BadgeData = newBadgeData

return BadgeData
