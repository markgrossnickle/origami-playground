--[[
	VFXUtil — lightweight VFX helpers for particle bursts and glows.
	All effects auto-cleanup after their lifetime.
]]

local VFXUtil = {}

-- Emit a burst of sparkle particles at a position.
function VFXUtil.sparkle(position: Vector3, color: Color3?, count: number?, lifetime: number?)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 230, 100))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(5, 12)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rate = 0
	emitter.LightEmission = 1
	emitter.Parent = part

	emitter:Emit(count or 20)

	task.delay(lifetime or 1.5, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- Flash-glow effect on a part (brief neon pulse).
function VFXUtil.glow(target: BasePart, color: Color3?, duration: number?)
	local dur = duration or 0.5
	local origColor = target.Color
	local origMaterial = target.Material
	local origTransparency = target.Transparency

	target.Material = Enum.Material.Neon
	target.Color = color or Color3.fromRGB(255, 255, 200)

	task.delay(dur, function()
		if target.Parent then
			target.Material = origMaterial
			target.Color = origColor
			target.Transparency = origTransparency
		end
	end)
end

-- Pop effect: scale up briefly then destroy (for creep deaths).
function VFXUtil.pop(target: BasePart, color: Color3?)
	VFXUtil.sparkle(target.Position, color or target.Color, 10, 1)
	if target.Parent then
		target:Destroy()
	end
end

-- Rising text effect (e.g. "+10g", "Hatched!").
function VFXUtil.risingText(position: Vector3, text: string, color: Color3?)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Adornee = part
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextSize = 18
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	-- Animate rising
	task.spawn(function()
		local elapsed = 0
		while elapsed < 1.5 and part.Parent do
			elapsed += task.wait()
			part.Position = position + Vector3.new(0, elapsed * 3, 0)
			label.TextTransparency = math.clamp(elapsed - 0.8, 0, 1)
			label.TextStrokeTransparency = math.clamp(0.3 + elapsed, 0, 1)
		end
		if part.Parent then
			part:Destroy()
		end
	end)
end

return VFXUtil
