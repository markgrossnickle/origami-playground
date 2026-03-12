--!strict
--[=[
	Tests for ShopConfig: validates shop items, currencies, and categories.
]=]

local fs = require("@lune/fs")
local t = require("../framework")
local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach

local function loadShopConfig(): { [string]: any }
	local source = fs.readFile("src/ReplicatedStorage/Shared/ShopConfig.luau")
	source = source:gsub("%-%-!strict\n", "")
	source = source:gsub("export%s+type%s+%w+%s*=%s*%b{}\n*", "")
	local chunk = assert(loadstring(source, "@ShopConfig"))
	return chunk()
end

local Config: any = nil

describe("ShopConfig", function()
	beforeEach(function()
		Config = loadShopConfig()
	end)

	it("should have Currencies defined", function()
		expect(Config.Currencies).to.be.ok()
	end)

	it("should have currencies with Name and DisplayOrder", function()
		for key, currency in Config.Currencies do
			expect(currency.Name).to.be.a("string")
			expect(currency.DisplayOrder).to.be.a("number")
		end
	end)

	it("should have CategoryOrder as a non-empty array", function()
		expect(#Config.CategoryOrder).to.be.greaterThan(0)
	end)

	it("should have Items as a non-empty array", function()
		expect(#Config.Items).to.be.greaterThan(0)
	end)

	it("should have valid items with required fields", function()
		for _, item in Config.Items do
			expect(item.Id).to.be.a("string")
			expect(item.Name).to.be.a("string")
			expect(item.Category).to.be.a("string")
			expect(item.Price).to.be.greaterThan(0)
			expect(item.Currency).to.be.a("string")
			expect(item.Description).to.be.a("string")
		end
	end)

	it("should have unique item IDs", function()
		local seen: { [string]: boolean } = {}
		for _, item in Config.Items do
			expect(seen[item.Id]).to.equal(nil)
			seen[item.Id] = true
		end
	end)

	it("should reference valid currencies in items", function()
		for _, item in Config.Items do
			expect(Config.Currencies[item.Currency]).to.be.ok()
		end
	end)

	it("should have ItemsById lookup matching Items", function()
		expect(Config.ItemsById).to.be.ok()
		for _, item in Config.Items do
			expect(Config.ItemsById[item.Id]).to.be.ok()
			expect(Config.ItemsById[item.Id].Name).to.equal(item.Name)
		end
	end)

	it("should have all item categories in CategoryOrder", function()
		local categorySet: { [string]: boolean } = {}
		for _, cat in Config.CategoryOrder do
			categorySet[cat] = true
		end
		for _, item in Config.Items do
			expect(categorySet[item.Category]).to.be.ok()
		end
	end)
end)
