--!strict
--[=[
	Tests for ExpeditionRecords: the pure helpers behind the Backpack
	"Records" tab (count/time formatting, depth -> layer resolution, stat
	tile assembly).
]=]

local fs = require("@lune/fs")
local t = require("../framework")
local describe, it, expect = t.describe, t.it, t.expect

local function loadModule(): any
	local source = fs.readFile("src/ReplicatedStorage/Shared/ExpeditionRecords.luau")
	source = source:gsub("%-%-!strict\n", "")
	local chunk = assert(loadstring(source, "@ExpeditionRecords"))
	return chunk()
end

local Records = loadModule()

-- Mirrors the shape (and real boundaries) of BiomeConfig.DepthLayers.
local LAYERS = {
	{ name = "Paper Fields", minDepth = 0, maxDepth = 80 },
	{ name = "Pulp Caverns", minDepth = 80, maxDepth = 240 },
	{ name = "Fold Tunnels", minDepth = 240, maxDepth = 480 },
	{ name = "Origami Depths", minDepth = 480, maxDepth = 800 },
	{ name = "Crystal Lattice", minDepth = 800, maxDepth = 1200 },
	{ name = "Void Seams", minDepth = 1200, maxDepth = 1600 },
	{ name = "The Core", minDepth = 1600, maxDepth = 2000 },
}

describe("ExpeditionRecords.formatCount", function()
	it("should pass small numbers through", function()
		expect(Records.formatCount(0)).to.equal("0")
		expect(Records.formatCount(999)).to.equal("999")
	end)

	it("should insert thousands separators", function()
		expect(Records.formatCount(1000)).to.equal("1,000")
		expect(Records.formatCount(12345)).to.equal("12,345")
		expect(Records.formatCount(1234567)).to.equal("1,234,567")
	end)

	it("should clamp negatives to zero and floor decimals", function()
		expect(Records.formatCount(-5)).to.equal("0")
		expect(Records.formatCount(1234.9)).to.equal("1,234")
	end)
end)

describe("ExpeditionRecords.formatPlayTime", function()
	it("should show <1m under a minute", function()
		expect(Records.formatPlayTime(0)).to.equal("<1m")
		expect(Records.formatPlayTime(59)).to.equal("<1m")
	end)

	it("should show minutes under an hour", function()
		expect(Records.formatPlayTime(60)).to.equal("1m")
		expect(Records.formatPlayTime(59 * 60 + 59)).to.equal("59m")
	end)

	it("should show hours with zero-padded minutes", function()
		expect(Records.formatPlayTime(3600)).to.equal("1h 00m")
		expect(Records.formatPlayTime(3 * 3600 + 7 * 60)).to.equal("3h 07m")
	end)
end)

describe("ExpeditionRecords.layerForDepth", function()
	it("should return nil at the surface", function()
		expect(Records.layerForDepth(0, LAYERS)).to.equal(nil)
		expect(Records.layerForDepth(-10, LAYERS)).to.equal(nil)
	end)

	it("should resolve depths to their layer band", function()
		expect(Records.layerForDepth(1, LAYERS).name).to.equal("Paper Fields")
		expect(Records.layerForDepth(79, LAYERS).name).to.equal("Paper Fields")
		expect(Records.layerForDepth(80, LAYERS).name).to.equal("Pulp Caverns")
		expect(Records.layerForDepth(500, LAYERS).name).to.equal("Origami Depths")
	end)

	it("should clamp beyond-bottom depths to the last layer", function()
		expect(Records.layerForDepth(99999, LAYERS).name).to.equal("The Core")
	end)
end)

describe("ExpeditionRecords.layersExplored", function()
	it("should be zero at the surface", function()
		expect(Records.layersExplored(0, LAYERS)).to.equal(0)
	end)

	it("should count each layer band entered", function()
		expect(Records.layersExplored(1, LAYERS)).to.equal(1)
		expect(Records.layersExplored(80, LAYERS)).to.equal(1)
		expect(Records.layersExplored(81, LAYERS)).to.equal(2)
		expect(Records.layersExplored(99999, LAYERS)).to.equal(7)
	end)
end)

describe("ExpeditionRecords.buildStats", function()
	local snapshot = {
		blocksMined = 1234,
		depthReached = 150,
		craftedCount = 8,
		playTimeSeconds = 3660,
		sessionCount = 5,
		giftsGiven = 0,
	}

	it("should build the six core tiles in order", function()
		local stats = Records.buildStats(snapshot, LAYERS)
		expect(#stats).to.equal(6)
		expect(stats[1].label).to.equal("Blocks Mined")
		expect(stats[1].value).to.equal("1,234")
		expect(stats[2].value).to.equal("Pulp Caverns")
		expect(stats[3].value).to.equal("2 of 7")
		expect(stats[4].value).to.equal("8")
		expect(stats[5].value).to.equal("1h 01m")
		expect(stats[6].value).to.equal("5")
	end)

	it("should show Surface before any underground mining", function()
		local fresh = {
			blocksMined = 0,
			depthReached = 0,
			craftedCount = 0,
			playTimeSeconds = 0,
			sessionCount = 1,
			giftsGiven = 0,
		}
		local stats = Records.buildStats(fresh, LAYERS)
		expect(stats[2].value).to.equal("Surface")
		expect(stats[3].value).to.equal("0 of 7")
	end)

	it("should append a gifts tile only when gifts were given", function()
		local giver = {
			blocksMined = 1,
			depthReached = 1,
			craftedCount = 0,
			playTimeSeconds = 0,
			sessionCount = 1,
			giftsGiven = 3,
		}
		local stats = Records.buildStats(giver, LAYERS)
		expect(#stats).to.equal(7)
		expect(stats[7].label).to.equal("Gifts Given")
		expect(stats[7].value).to.equal("3")
	end)

	it("should have icon, label, and value on every tile", function()
		for _, stat in Records.buildStats(snapshot, LAYERS) do
			expect(type(stat.icon)).to.equal("string")
			expect(type(stat.label)).to.equal("string")
			expect(type(stat.value)).to.equal("string")
		end
	end)
end)
