--!strict
--[[
	ZonePermissions — pure permission rules per zone × action.
	No state, no service deps. Server-side gates use this; clients can mirror.
]]

local ZonePermissions = {}

export type Action = "mine" | "place"
export type Decision = { allowed: boolean, reason: string? }

function ZonePermissions.canAct(zone: string, action: Action, isOwner: boolean): Decision
	if zone == "hearth" then
		return { allowed = false, reason = "hearth_locked" }
	end
	if zone == "wilds" then
		return { allowed = true }
	end
	if zone == "regions" then
		if isOwner then
			return { allowed = true }
		end
		return { allowed = false, reason = "not_your_region" }
	end
	return { allowed = false, reason = "unknown_zone" }
end

return ZonePermissions
