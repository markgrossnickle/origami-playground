--!strict
--[=[
	Tests for MonetizationConfig: validates GamePasses, DevProducts, and DailyRewards.
]=]

local fs = require("@lune/fs")
local t = require("../framework")
local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach

local function loadMonetizationConfig(): { [string]: any }
	local source = fs.readFile("src/ReplicatedStorage/Shared/MonetizationConfig.luau")
	source = source:gsub("%-%-!strict\n", "")
	source = source:gsub("export%s+type%s+%w+%s*=%s*%b{}\n*", "")
	local chunk = assert(loadstring(source, "@MonetizationConfig"))
	return chunk()
end

local Config: any = nil

describe("MonetizationConfig", function()
	beforeEach(function()
		Config = loadMonetizationConfig()
	end)

	it("should have GamePasses table", function()
		expect(Config.GamePasses).to.be.ok()
	end)

	it("should have valid GamePass entries with Id and Name", function()
		for key, pass in Config.GamePasses do
			expect(pass.Id).to.be.a("number")
			expect(pass.Name).to.be.a("string")
		end
	end)

	it("should have DevProducts table", function()
		expect(Config.DevProducts).to.be.ok()
	end)

	it("should have valid DevProduct entries with Id, Name, and Handler", function()
		for key, product in Config.DevProducts do
			expect(product.Id).to.be.a("number")
			expect(product.Name).to.be.a("string")
			expect(product.Handler).to.be.a("string")
		end
	end)

	it("should have DailyRewards as an array with 7 entries", function()
		expect(#Config.DailyRewards).to.equal(7)
	end)

	it("should have valid DailyReward entries", function()
		for _, reward in Config.DailyRewards do
			expect(reward.Type).to.be.a("string")
			expect(reward.Description).to.be.a("string")
			if reward.Type == "Currency" then
				expect(reward.Currency).to.be.a("string")
				expect(reward.Amount).to.be.greaterThan(0)
			end
		end
	end)

	it("should have a positive PremiumMultiplier", function()
		expect(Config.PremiumMultiplier).to.be.greaterThan(1)
	end)

	it("should have coin amounts for all coin products", function()
		for key, product in Config.DevProducts do
			if product.Handler == "_handleCoinProduct" then
				expect(Config.DevProductCoinAmounts[key]).to.be.greaterThan(0)
			end
		end
	end)
end)
