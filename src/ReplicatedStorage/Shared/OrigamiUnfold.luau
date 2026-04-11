--[[
	OrigamiUnfold — paper unfolding spawn animation for origami creatures.
	Hides all parts, then reveals them one-by-one (inner → outer) with a
	flat-to-full tween for a folding/popping effect.

	Usage:
		local model = OrigamiBuilder.BuildModel(data)
		model.Parent = workspace
		model:PivotTo(CFrame.new(spawnPos))
		OrigamiUnfold.Animate(model, spawnPos, function()
			-- start AI, etc.
		end)
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

-- Animate `model` unfolding around `centerPosition`. Calls `callback` when done.
function OrigamiUnfold.Animate(model: Model, centerPosition: Vector3?, callback: (() -> ())?)
	if not model or not model.Parent then
		if callback then
			callback()
		end
		return
	end

	local parts: { BasePart } = {}
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end

	if #parts == 0 then
		if callback then
			callback()
		end
		return
	end

	local center: Vector3
	if centerPosition then
		center = centerPosition
	else
		center = model:GetPivot().Position
	end

	-- Cache final state per part
	local cached = {}
	for _, part in ipairs(parts) do
		table.insert(cached, {
			part = part,
			cframe = part.CFrame,
			size = part.Size,
			transparency = part.Transparency,
			distance = (part.Position - center).Magnitude,
		})
	end

	-- Inner → outer for natural unfold cascade
	table.sort(cached, function(a, b)
		return a.distance < b.distance
	end)

	-- Collapse every part to a tiny flat sliver at the center with a random tilt
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

	-- Paper sheet at spawn point that fades as parts emerge
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

	-- Fit total animation under MAX_TOTAL
	local count = #cached
	local stagger = STAGGER_DEFAULT
	if count * stagger + TWEEN_DURATION > MAX_TOTAL then
		stagger = math.max(STAGGER_MIN, (MAX_TOTAL - TWEEN_DURATION) / count)
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

	if callback then
		local total = (count - 1) * stagger + TWEEN_DURATION
		task.delay(total, callback)
	end
end

return OrigamiUnfold
