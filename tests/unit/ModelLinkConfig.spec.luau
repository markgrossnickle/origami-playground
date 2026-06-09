--!strict
--[=[
	Tests for ModelLinkConfig: validates the BYOM + subscription gate config.
]=]

local fs = require("@lune/fs")
local t = require("../framework")
local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach

local function loadModelLinkConfig(): { [string]: any }
	local source = fs.readFile("src/ReplicatedStorage/Shared/ModelLinkConfig.luau")
	source = source:gsub("%-%-!strict\n", "")
	source = source:gsub("export%s+type%s+%w+%s*=%s*%b{}\n*", "")
	-- Strip the type annotation on the local declaration so plain Lua can load it.
	source = source:gsub("local ModelLinkConfig: ModelLinkConfigType =", "local ModelLinkConfig =")
	local chunk = assert(loadstring(source, "@ModelLinkConfig"))
	return chunk()
end

local Config: any = nil

describe("ModelLinkConfig", function()
	beforeEach(function()
		Config = loadModelLinkConfig()
	end)

	it("should default the gate to disabled (usable before Subscription exists)", function()
		expect(Config.GateEnabled).to.equal(false)
	end)

	it("should have a SubscriptionId string field", function()
		expect(Config.SubscriptionId).to.be.a("string")
	end)

	it("should have a LinkPath that starts with a slash", function()
		expect(Config.LinkPath).to.be.a("string")
		expect(Config.LinkPath:sub(1, 1)).to.equal("/")
	end)

	it("should have positive prompt/response length caps", function()
		expect(Config.MaxPromptLength).to.be.greaterThan(0)
		expect(Config.MaxResponseLength).to.be.greaterThan(0)
	end)

	it("should have a non-empty demo system prompt", function()
		expect(Config.DemoSystemPrompt).to.be.a("string")
		expect(#Config.DemoSystemPrompt).to.be.greaterThan(0)
	end)
end)
