--[[
	CompetitionGrid — spawns a grid of AI-generated models for side-by-side comparison.
	Supports multiple styles, each in its own section along the X axis.
	Columns = LLM models, Rows = prompts (simple→complex).
	Called from Server:_setupWorld().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local CompetitionGrid = {}

-- Grid layout constants
local COL_SPACING = 20 -- studs between model columns
local ROW_SPACING = 15 -- studs between prompt rows
local SECTION_GAP = 2 -- extra rows between category sections (creature/prop/vehicle)
local STYLE_GAP = 150 -- studs between style grids along X axis
local MODEL_Y_OFFSET = 3 -- raise models above ground

local FOLDER_NAME = "CompetitionGrid"

----------------------------------------------------------------------
-- Billboard helpers
----------------------------------------------------------------------

local function makeBillboard(parent: Instance, text: string, offset: Vector3, size: UDim2?, textSize: number?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.StudsOffset = offset
	bb.Size = size or UDim2.new(0, 140, 0, 40)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 200

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = false
	label.TextSize = textSize or 10
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextWrapped = true
	label.Parent = bb

	bb.Adornee = parent
	bb.Parent = parent
	return bb
end

local function makeFailPlaceholder(folder: Folder, position: Vector3, labelText: string): Part
	local part = Instance.new("Part")
	part.Name = "Failed"
	part.Size = Vector3.new(4, 4, 4)
	part.Position = position
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(200, 80, 80)
	part.Transparency = 0.4
	part.Parent = folder

	makeBillboard(part, labelText, Vector3.new(0, 5, 0))
	return part
end

----------------------------------------------------------------------
-- Grid builder
----------------------------------------------------------------------

local function buildStyleGrid(gridFolder: Folder, styleKey: string, styleResults: { [string]: any },
	models: { string }, modelDisplay: { [string]: string }, prompts: { any }, originX: number)

	-- Center the grid vertically (Z) on the baseplate
	local totalRows = #prompts + 2 * SECTION_GAP -- 30 prompts + 4 gap rows = 34
	local originZ = -math.floor((totalRows - 1) * ROW_SPACING / 2)
	local gridCenterX = originX + math.floor((#models - 1) * COL_SPACING / 2)

	-- Style title billboard (big sign above the grid)
	local titlePart = Instance.new("Part")
	titlePart.Name = "StyleTitle_" .. styleKey
	titlePart.Size = Vector3.new(#models * COL_SPACING, 0.5, 6)
	titlePart.Position = Vector3.new(gridCenterX, 0.3, originZ - ROW_SPACING * 1.8)
	titlePart.Anchored = true
	titlePart.Material = Enum.Material.SmoothPlastic
	titlePart.Color = Color3.fromRGB(180, 140, 220)
	titlePart.Parent = gridFolder

	makeBillboard(
		titlePart,
		string.upper(styleKey),
		Vector3.new(0, 4, 0),
		UDim2.new(0, 200, 0, 40),
		20
	)

	-- Column headers (model names)
	for col, modelKey in ipairs(models) do
		local x = originX + (col - 1) * COL_SPACING
		local z = originZ - ROW_SPACING

		local headerPart = Instance.new("Part")
		headerPart.Name = "Header_" .. modelKey
		headerPart.Size = Vector3.new(COL_SPACING - 2, 0.5, 4)
		headerPart.Position = Vector3.new(x, 0.5, z)
		headerPart.Anchored = true
		headerPart.Material = Enum.Material.SmoothPlastic
		headerPart.Color = Color3.fromRGB(100, 150, 220)
		headerPart.Parent = gridFolder

		local displayName = modelDisplay[modelKey] or modelKey
		makeBillboard(headerPart, displayName, Vector3.new(0, 3, 0), UDim2.new(0, 120, 0, 30), 14)
	end

	-- Rows
	local currentCategory = ""
	local sectionOffset = 0

	for row, promptInfo in ipairs(prompts) do
		if promptInfo.category ~= currentCategory then
			if currentCategory ~= "" then
				sectionOffset = sectionOffset + SECTION_GAP
			end
			currentCategory = promptInfo.category

			local sectionZ = originZ + (row - 1 + sectionOffset) * ROW_SPACING - ROW_SPACING * 0.4
			local sectionPart = Instance.new("Part")
			sectionPart.Name = "Section_" .. currentCategory
			sectionPart.Size = Vector3.new(#models * COL_SPACING, 0.5, 2)
			sectionPart.Position = Vector3.new(gridCenterX, 0.3, sectionZ)
			sectionPart.Anchored = true
			sectionPart.Material = Enum.Material.SmoothPlastic
			sectionPart.Color = Color3.fromRGB(255, 200, 100)
			sectionPart.Transparency = 0.5
			sectionPart.Parent = gridFolder

			makeBillboard(
				sectionPart,
				string.upper(currentCategory) .. "S",
				Vector3.new(0, 2, 0),
				UDim2.new(0, 200, 0, 30),
				16
			)
		end

		local z = originZ + (row - 1 + sectionOffset) * ROW_SPACING

		-- Row label
		local rowLabelPart = Instance.new("Part")
		rowLabelPart.Name = "RowLabel_" .. tostring(row)
		rowLabelPart.Size = Vector3.new(2, 0.5, 4)
		rowLabelPart.Position = Vector3.new(originX - COL_SPACING, 0.5, z)
		rowLabelPart.Anchored = true
		rowLabelPart.Transparency = 1
		rowLabelPart.CanCollide = false
		rowLabelPart.Parent = gridFolder

		local promptShort = promptInfo.prompt
		if #promptShort > 50 then
			promptShort = string.sub(promptShort, 1, 47) .. "..."
		end
		makeBillboard(
			rowLabelPart,
			"#" .. tostring(((row - 1) % 10) + 1) .. ": " .. promptShort,
			Vector3.new(0, 4, 0),
			UDim2.new(0, 200, 0, 35),
			9
		)

		-- Each model column
		for col, modelKey in ipairs(models) do
			local x = originX + (col - 1) * COL_SPACING
			local cellPos = Vector3.new(x, MODEL_Y_OFFSET, z)

			local key = tostring(row) .. "_" .. modelKey
			local modelData = styleResults[key]

			if modelData and modelData.parts then
				local builtOk, builtModel = pcall(function()
					return OrigamiBuilder.BuildModel(modelData)
				end)

				if builtOk and builtModel then
					for _, part in builtModel:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = true
						end
					end

					builtModel:PivotTo(CFrame.new(cellPos))
					builtModel.Parent = gridFolder

					-- Apply animation from model data
					local animType = modelData.animation
					if animType and animType ~= "none" then
						pcall(function()
							OrigamiBuilder.ApplyAnimation(builtModel, animType)
						end)
					end

					local primaryPart = builtModel.PrimaryPart or builtModel:FindFirstChildWhichIsA("BasePart")
					if primaryPart then
						local displayName = modelDisplay[modelKey] or modelKey
						local modelName = modelData.name or "?"
						local partCount = #modelData.parts
						local labelText = modelName .. "\n" .. displayName .. " | " .. partCount .. " parts"
						makeBillboard(primaryPart, labelText, Vector3.new(0, 6, 0))
					end
				else
					makeFailPlaceholder(gridFolder, cellPos, "BUILD ERR\n" .. (modelDisplay[modelKey] or modelKey))
				end
			else
				makeFailPlaceholder(gridFolder, cellPos, "FAILED\n" .. (modelDisplay[modelKey] or modelKey))
			end
		end
	end
end

function CompetitionGrid.Build()
	CompetitionGrid.Clear()

	local ok, CompetitionData = pcall(function()
		return require(ReplicatedStorage.Shared.CompetitionData)
	end)
	if not ok then
		warn("[CompetitionGrid] CompetitionData module not found — run convert_competition.py first")
		return
	end

	local models = CompetitionData.MODELS
	local modelDisplay = CompetitionData.MODEL_DISPLAY
	local prompts = CompetitionData.PROMPTS
	local styles = CompetitionData.STYLES
	local allResults = CompetitionData.RESULTS

	local gridFolder = Instance.new("Folder")
	gridFolder.Name = FOLDER_NAME
	gridFolder.Parent = workspace

	-- Layout each style side by side along X
	local gridWidth = (#models - 1) * COL_SPACING
	local totalWidth = #styles * (gridWidth + STYLE_GAP) - STYLE_GAP
	local startX = -math.floor(totalWidth / 2)

	for styleIndex, styleKey in ipairs(styles) do
		local originX = startX + (styleIndex - 1) * (gridWidth + STYLE_GAP)
		local styleResults = allResults[styleKey] or {}
		buildStyleGrid(gridFolder, styleKey, styleResults, models, modelDisplay, prompts, originX)
	end

	-- Count results
	local total = #prompts * #models * #styles
	local placed = 0
	for _, child in gridFolder:GetDescendants() do
		if child:IsA("Model") then
			placed += 1
		end
	end
	print(string.format("[CompetitionGrid] Built %d/%d models across %d styles", placed, total, #styles))
end

function CompetitionGrid.Clear()
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

return CompetitionGrid
