--[[
	TDPathGenerator — generates waypoint paths for Tower Defense modes.
	Supports linear (solo) and converging (co-op) path layouts.
]]

local TDPathGenerator = {}

-- Generate a linear path with sine-wave curvature (existing solo TD pattern).
-- Returns array of Vector3 waypoints.
function TDPathGenerator.generateLinearPath(
	origin: Vector3,
	length: number,
	count: number,
	curvature: number?
): { Vector3 }
	local curve = curvature or 15
	local waypoints = {}
	for i = 1, count do
		local t = (i - 1) / (count - 1)
		local x = origin.X + t * length
		local z = origin.Z + math.sin(t * math.pi) * curve
		table.insert(waypoints, Vector3.new(x, origin.Y, z))
	end
	return waypoints
end

-- Generate N paths that converge on a central point from different directions.
-- Used for co-op TD where enemies come from multiple sides.
-- Returns { [directionIndex]: { Vector3 } } — one waypoint array per direction.
function TDPathGenerator.generateConvergingPaths(
	center: Vector3,
	directionCount: number,
	pathLength: number,
	waypointsPerPath: number
): { { Vector3 } }
	local paths = {}
	local angleStep = (2 * math.pi) / directionCount

	for d = 1, directionCount do
		local angle = angleStep * (d - 1) -- N, E, S, W for 4 directions
		local dirX = math.sin(angle)
		local dirZ = math.cos(angle)

		-- Start far out, end at center
		local startPos = center + Vector3.new(dirX * pathLength, 0, dirZ * pathLength)
		local waypoints = {}

		for i = 1, waypointsPerPath do
			local t = (i - 1) / (waypointsPerPath - 1)
			-- Slight S-curve for visual interest
			local perpX = -dirZ -- perpendicular direction
			local perpZ = dirX
			local curvature = math.sin(t * math.pi) * (pathLength * 0.08)

			local pos = startPos:Lerp(center, t) + Vector3.new(perpX * curvature, 0, perpZ * curvature)
			table.insert(waypoints, Vector3.new(pos.X, center.Y, pos.Z))
		end

		table.insert(paths, waypoints)
	end

	return paths
end

return TDPathGenerator
