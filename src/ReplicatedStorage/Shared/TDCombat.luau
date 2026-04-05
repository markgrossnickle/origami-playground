--[[
	TDCombat — shared combat functions for Tower Defense modes (solo + co-op).
	Extracted from TowerDefenseController for reuse.
]]

local TDCombat = {}

-- Combat constants
TDCombat.ARMOR_REDUCTION = 0.7
TDCombat.DODGE_CHANCE = 0.25
TDCombat.REGEN_PER_TICK = 3
TDCombat.SPLASH_RADIUS = 8

export type AttackType = "single" | "splash" | "rapid" | "piercing"
export type TargetPriority = "nearest" | "weakest" | "strongest" | "fastest"
export type DefenseType = "none" | "armor" | "dodge" | "regen"

export type Creep = {
	part: BasePart?,
	position: Vector3?, -- server-authoritative position (co-op)
	hp: number,
	maxHp: number,
	waypointIndex: number,
	speed: number,
	alive: boolean,
	side: string,
	tier: string,
	defenseType: DefenseType,
}

TDCombat.VALID_ATTACK_TYPES = { single = true, splash = true, rapid = true, piercing = true }
TDCombat.VALID_TARGET_PRIORITIES = { nearest = true, weakest = true, strongest = true, fastest = true }

-- Find best creep target within range based on priority.
function TDCombat.findCreepTarget(pos: Vector3, range: number, creepList: { Creep }, priority: TargetPriority): Creep?
	local best: Creep? = nil
	local bestScore = math.huge

	for _, creep in ipairs(creepList) do
		if creep.alive then
			local creepPos = if creep.part and creep.part.Parent then creep.part.Position else creep.position
			if not creepPos then
				continue
			end

			local dist = (creepPos - pos).Magnitude
			if dist <= range then
				if priority == "nearest" then
					if dist < bestScore then
						bestScore = dist
						best = creep
					end
				elseif priority == "weakest" then
					if creep.hp < bestScore then
						bestScore = creep.hp
						best = creep
					end
				elseif priority == "strongest" then
					local score = -creep.maxHp
					if score < bestScore then
						bestScore = score
						best = creep
					end
				elseif priority == "fastest" then
					-- "Fastest" = closest to reaching the base (most dangerous)
					local progress: number
					if creep.side == "player" then
						progress = -creep.waypointIndex
					else
						progress = creep.waypointIndex
					end
					if progress < bestScore then
						bestScore = progress
						best = creep
					end
				end
			end
		end
	end
	return best
end

-- Apply damage to a creep, handling armor/dodge/piercing. Returns actual damage dealt.
-- onKill callback is called with the creep if it dies.
function TDCombat.damageCreep(creep: Creep, damage: number, attackType: AttackType, onKill: ((Creep) -> ())?): number
	if not creep.alive then
		return 0
	end

	-- Dodge check
	if creep.defenseType == "dodge" then
		if math.random() < TDCombat.DODGE_CHANCE then
			return 0
		end
	end

	-- Armor reduction
	local dmg = damage
	if creep.defenseType == "armor" and attackType ~= "piercing" then
		dmg = dmg * (1 - TDCombat.ARMOR_REDUCTION)
	end

	creep.hp -= dmg
	if creep.hp <= 0 then
		creep.alive = false
		if creep.part and creep.part.Parent then
			creep.part:Destroy()
		end
		if onKill then
			onKill(creep)
		end
	end

	return dmg
end

-- Derive tower stats (damage, range) from a model's bounding box.
function TDCombat.deriveTowerStats(model: Model | BasePart): { damage: number, range: number }
	if model:IsA("Model") then
		local _, size = model:GetBoundingBox()
		local volume = size.X * size.Y * size.Z
		local maxDim = math.max(size.X, size.Y, size.Z)
		return {
			damage = math.max(5, math.floor(volume / 2)),
			range = math.max(15, maxDim * 2),
		}
	else
		return { damage = 10, range = 20 }
	end
end

-- Apply HP regeneration to creeps with "regen" defense type.
function TDCombat.applyCreepRegen(creepList: { Creep }, dt: number)
	for _, creep in ipairs(creepList) do
		if creep.alive and creep.defenseType == "regen" and creep.hp < creep.maxHp then
			creep.hp = math.min(creep.maxHp, creep.hp + TDCombat.REGEN_PER_TICK * dt)
		end
	end
end

return TDCombat
