--!strict
--[[
	ExpeditionRecords — pure helpers behind the Backpack "Records" tab: the
	GDD's read-only "records & discovery" counters (blocks mined, deepest
	layer, items folded, ...).

	Deliberately requires nothing: the Lune test runner loads modules with
	loadstring (no `script` context), so keeping this dependency-free is what
	makes it unit-testable. Layer data is injected by the caller — pass
	BiomeConfig.DepthLayers at runtime so layer names/boundaries keep a single
	source of truth.
]]

local ExpeditionRecords = {}

export type LayerInfo = { name: string, minDepth: number, maxDepth: number }

export type Snapshot = {
	blocksMined: number,
	depthReached: number, -- studs below the surface, 0 = never mined underground
	craftedCount: number,
	playTimeSeconds: number,
	sessionCount: number,
	giftsGiven: number,
}

export type Stat = { icon: string, label: string, value: string }

-- 12345 -> "12,345". Negative values clamp to 0 (counters can't go below).
function ExpeditionRecords.formatCount(n: number): string
	local s = tostring(math.max(0, math.floor(n)))
	while true do
		local replaced
		s, replaced = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return s
end

-- Seconds -> "<1m" | "42m" | "3h 07m"
function ExpeditionRecords.formatPlayTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s < 60 then
		return "<1m"
	end
	local minutes = math.floor(s / 60)
	if minutes < 60 then
		return string.format("%dm", minutes)
	end
	return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

-- The layer containing `depth`, or nil when the player has never mined
-- underground (depth <= 0). Layers must be ordered shallow -> deep.
function ExpeditionRecords.layerForDepth(depth: number, layers: { LayerInfo }): LayerInfo?
	if depth <= 0 or #layers == 0 then
		return nil
	end
	for _, layer in layers do
		if depth < layer.maxDepth then
			return layer
		end
	end
	return layers[#layers]
end

-- How many layers the player has dug into (a layer counts once its band is
-- entered, i.e. depth exceeds its minDepth).
function ExpeditionRecords.layersExplored(depth: number, layers: { LayerInfo }): number
	local count = 0
	for _, layer in layers do
		if depth > layer.minDepth then
			count += 1
		end
	end
	return count
end

-- Ordered stat tiles for the Records tab.
function ExpeditionRecords.buildStats(snapshot: Snapshot, layers: { LayerInfo }): { Stat }
	local deepest = ExpeditionRecords.layerForDepth(snapshot.depthReached, layers)
	local stats: { Stat } = {
		{ icon = "\u{1F9F1}", label = "Blocks Mined", value = ExpeditionRecords.formatCount(snapshot.blocksMined) },
		{ icon = "\u{26CF}\u{FE0F}", label = "Deepest Reach", value = if deepest then deepest.name else "Surface" },
		{
			icon = "\u{1F5FA}\u{FE0F}",
			label = "Layers Explored",
			value = string.format("%d of %d", ExpeditionRecords.layersExplored(snapshot.depthReached, layers), #layers),
		},
		{
			icon = "\u{2702}\u{FE0F}",
			label = "Items Folded",
			value = ExpeditionRecords.formatCount(snapshot.craftedCount),
		},
		{
			icon = "\u{23F3}",
			label = "Time Exploring",
			value = ExpeditionRecords.formatPlayTime(snapshot.playTimeSeconds),
		},
		{ icon = "\u{1F388}", label = "Expeditions", value = ExpeditionRecords.formatCount(snapshot.sessionCount) },
	}
	if snapshot.giftsGiven > 0 then
		table.insert(
			stats,
			{ icon = "\u{1F381}", label = "Gifts Given", value = ExpeditionRecords.formatCount(snapshot.giftsGiven) }
		)
	end
	return stats
end

return ExpeditionRecords
