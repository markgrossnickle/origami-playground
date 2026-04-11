--[[
	OrigamiUnfold — paper unfolding spawn animation for origami creations.
	Three styles selectable:
		"scale"     — parts collapse to a tilted sliver and scale outward (original)
		"flip"      — parts start rotated 180° and rotate into place like pop-up pages
		"accordion" — parts start stacked/compressed vertically then spread upward like a fan

	Usage:
		OrigamiUnfold.Animate(model, spawnPos, "scale", function()
			-- start AI, etc.
		end)
		-- Backward compatible: third arg may be the callback (defaults to "scale").
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local OrigamiUnfold = {}

local TWEEN_DURATION = 0.45
local STAGGER_DEFAULT = 0.18
local STAGGER_MIN = 0.05
local MAX_TOTAL = 3.0
local PAPER_FADE_DURATION = 0.55

local function makePaperSheet(center: Vector3): Part
	local paper = Instance.new("Part")
	paper.Name = "OrigamiUnfoldPaper"
	paper.Anchored = true
	paper.CanCollide = false
	paper.CanQuery = false
	paper.CanTouch = false
	paper.Massless = true
	paper.Size = Vector3.new(3, 0.05, 3)
	paper.Color = Color3.fromRGB(248, 246, 232)
	paper.Material = Enum.Material.SmoothPlastic
	paper.Transparency = 0.05
	paper.CFrame = CFrame.new(center)
	paper.Parent = Workspace
	return paper
end

local function playFoldSound(parent: Instance)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.35
	sound.PlaybackSpeed = 1.6
	sound.Parent = parent
	sound:Play()
	task.delay(1, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function collectParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	return parts
end

type Entry = {
	part: BasePart,
	cframe: CFrame,
	size: Vector3,
	transparency: number,
	distance: number,
}

local function cacheEntries(parts: { BasePart }, center: Vector3): { Entry }
	local cached: { Entry } = {}
	for _, part in ipairs(parts) do
		table.insert(cached, {
			part = part,
			cframe = part.CFrame,
			size = part.Size,
			transparency = part.Transparency,
			distance = (part.Position - center).Magnitude,
		})
	end
	table.sort(cached, function(a, b)
		return a.distance < b.distance
	end)
	return cached
end

local function computeStagger(count: number): number
	local stagger = STAGGER_DEFAULT
	if count * stagger + TWEEN_DURATION > MAX_TOTAL then
		stagger = math.max(STAGGER_MIN, (MAX_TOTAL - TWEEN_DURATION) / count)
	end
	return stagger
end

-- Style: scale — collapse to flat sliver at center, then expand out
local function applyScale(cached: { Entry }, center: Vector3, stagger: number)
	local startSize = Vector3.new(0.1, 0.02, 0.1)
	for _, entry in ipairs(cached) do
		local part = entry.part
		local tilt = CFrame.Angles(
			math.rad(math.random(-25, 25)),
			math.rad(math.random(-180, 180)),
			math.rad(math.random(-25, 25))
		)
		part.Transparency = 1
		part.Size = startSize
		part.CFrame = CFrame.new(center) * tilt
	end

	local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i, entry in ipairs(cached) do
		task.delay((i - 1) * stagger, function()
			local part = entry.part
			if not part.Parent then
				return
			end
			TweenService:Create(part, tweenInfo, {
				CFrame = entry.cframe,
				Size = entry.size,
				Transparency = entry.transparency,
			}):Play()
		end)
	end
end

-- Style: flip — each part starts flipped 180° around local X or Z, rotates into place
local function applyFlip(cached: { Entry }, _center: Vector3, stagger: number)
	for _, entry in ipairs(cached) do
		local part = entry.part
		local flipAxis = if math.random() < 0.5 then CFrame.Angles(math.pi, 0, 0) else CFrame.Angles(0, 0, math.pi)
		part.Transparency = 1
		part.CFrame = entry.cframe * flipAxis
	end

	local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, entry in ipairs(cached) do
		task.delay((i - 1) * stagger, function()
			local part = entry.part
			if not part.Parent then
				return
			end
			TweenService:Create(part, tweenInfo, {
				CFrame = entry.cframe,
				Transparency = entry.transparency,
			}):Play()
		end)
	end
end

-- Style: accordion — all parts start stacked vertically at center Y, squished,
-- then spread outward and upward like a paper fan opening
local function applyAccordion(cached: { Entry }, center: Vector3, stagger: number)
	local startSize = Vector3.new(0.2, 0.02, 0.2)
	for _, entry in ipairs(cached) do
		local part = entry.part
		local finalPos = entry.cframe.Position
		local compressed =
			Vector3.new(center.X + (finalPos.X - center.X) * 0.2, center.Y, center.Z + (finalPos.Z - center.Z) * 0.2)
		local rot = entry.cframe - entry.cframe.Position
		part.Transparency = 1
		part.Size = startSize
		part.CFrame = CFrame.new(compressed) * rot
	end

	local tweenInfo = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i, entry in ipairs(cached) do
		task.delay((i - 1) * stagger, function()
			local part = entry.part
			if not part.Parent then
				return
			end
			TweenService:Create(part, tweenInfo, {
				CFrame = entry.cframe,
				Size = entry.size,
				Transparency = entry.transparency,
			}):Play()
		end)
	end
end

local STYLE_HANDLERS: { [string]: (cached: { Entry }, center: Vector3, stagger: number) -> () } = {
	scale = applyScale,
	flip = applyFlip,
	accordion = applyAccordion,
}

function OrigamiUnfold.Animate(
	model: Model,
	centerPosition: Vector3?,
	style: (string | (() -> ()))?,
	callback: (() -> ())?
)
	-- Backward compat: if style is a function, treat it as the callback
	local resolvedStyle: string
	local resolvedCallback: (() -> ())?
	if typeof(style) == "function" then
		resolvedCallback = style :: any
		resolvedStyle = "scale"
	else
		resolvedStyle = (style :: string?) or "scale"
		resolvedCallback = callback
	end

	if not model or not model.Parent then
		if resolvedCallback then
			resolvedCallback()
		end
		return
	end

	local parts = collectParts(model)
	if #parts == 0 then
		if resolvedCallback then
			resolvedCallback()
		end
		return
	end

	local center: Vector3 = centerPosition or model:GetPivot().Position
	local cached = cacheEntries(parts, center)

	local handler = STYLE_HANDLERS[resolvedStyle] or applyScale

	local paper = makePaperSheet(center)
	pcall(playFoldSound, paper)
	TweenService:Create(paper, TweenInfo.new(PAPER_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, 0.05, 0.2),
	}):Play()
	task.delay(PAPER_FADE_DURATION + 0.1, function()
		if paper.Parent then
			paper:Destroy()
		end
	end)

	local count = #cached
	local stagger = computeStagger(count)

	handler(cached, center, stagger)

	if resolvedCallback then
		local total = (count - 1) * stagger + TWEEN_DURATION
		task.delay(total, resolvedCallback)
	end
end

return OrigamiUnfold
