--!strict
--[=[
	Tests for the mock system: MockInstance, MockPlayer, MockSignal, MockServices.
]=]

local t = require("../framework")
local describe, it, expect = t.describe, t.it, t.expect
local MockInstance = require("../helpers/MockInstance")
local MockPlayer = require("../helpers/MockPlayer")
local MockSignal = require("../helpers/MockSignal")
local MockServices = require("../helpers/MockServices")

describe("MockInstance", function()
	it("should create an instance with className and name", function()
		local inst = MockInstance.new("Part", { Name = "TestPart" })
		expect(inst.ClassName).to.equal("Part")
		expect(inst.Name).to.equal("TestPart")
	end)

	it("should default name to className", function()
		local inst = MockInstance.new("Model")
		expect(inst.Name).to.equal("Model")
	end)

	it("should support attributes", function()
		local inst = MockInstance.new("Part")
		inst:SetAttribute("Health", 100)
		expect(inst:GetAttribute("Health")).to.equal(100)
		expect(inst:GetAttribute("Missing")).to.equal(nil)
	end)

	it("should support children via addChild and FindFirstChild", function()
		local parent = MockInstance.new("Model", { Name = "Parent" })
		local child = MockInstance.new("Part", { Name = "Child" })
		MockInstance.addChild(parent, child)

		expect(parent:FindFirstChild("Child")).to.be.ok()
		expect(parent:FindFirstChild("Missing")).to.equal(nil)
		expect(#parent:GetChildren()).to.equal(1)
	end)

	it("should support property access via dot notation for children", function()
		local parent = MockInstance.new("Model", { Name = "Parent" })
		local child = MockInstance.new("Part", { Name = "MyPart" })
		MockInstance.addChild(parent, child)

		expect((parent :: any).MyPart).to.be.ok()
		expect((parent :: any).MyPart.Name).to.equal("MyPart")
	end)

	it("should support Destroy", function()
		local inst = MockInstance.new("Part")
		inst:Destroy()
		expect((inst :: any)._destroyed).to.equal(true)
	end)

	it("should support Clone", function()
		local inst = MockInstance.new("Part", { Name = "Original" })
		inst:SetAttribute("HP", 50)
		local clone = inst:Clone()
		expect(clone.Name).to.equal("Original")
		expect(clone:GetAttribute("HP")).to.equal(50)
	end)

	it("should support IsA", function()
		local inst = MockInstance.new("Part")
		expect(inst:IsA("Part")).to.equal(true)
		expect(inst:IsA("Model")).to.equal(false)
	end)
end)

describe("MockPlayer", function()
	it("should create a player with defaults", function()
		local player = MockPlayer.new()
		expect(player.Name).to.equal("TestPlayer")
		expect(player.UserId).to.equal(12345)
	end)

	it("should accept overrides", function()
		local player = MockPlayer.new({ Name = "Alice", UserId = 99 })
		expect(player.Name).to.equal("Alice")
		expect(player.UserId).to.equal(99)
	end)

	it("should support attributes", function()
		local player = MockPlayer.new()
		player:SetAttribute("Score", 42)
		expect(player:GetAttribute("Score")).to.equal(42)
	end)
end)

describe("MockSignal", function()
	it("should fire connected listeners", function()
		local signal = MockSignal.new()
		local received: any = nil
		signal:Connect(function(value: any)
			received = value
		end)
		signal:Fire("hello")
		expect(received).to.equal("hello")
	end)

	it("should support multiple listeners", function()
		local signal = MockSignal.new()
		local count = 0
		signal:Connect(function()
			count += 1
		end)
		signal:Connect(function()
			count += 1
		end)
		signal:Fire()
		expect(count).to.equal(2)
	end)

	it("should support disconnect", function()
		local signal = MockSignal.new()
		local count = 0
		local conn = signal:Connect(function()
			count += 1
		end)
		signal:Fire()
		expect(count).to.equal(1)
		conn:Disconnect()
		signal:Fire()
		expect(count).to.equal(1)
	end)

	it("should support DisconnectAll", function()
		local signal = MockSignal.new()
		local count = 0
		signal:Connect(function()
			count += 1
		end)
		signal:Connect(function()
			count += 1
		end)
		signal:DisconnectAll()
		signal:Fire()
		expect(count).to.equal(0)
	end)
end)

describe("MockServices", function()
	it("should create Players service with PlayerAdded/Removing signals", function()
		local players = MockServices.createPlayers()
		local addedPlayer: any = nil
		players.PlayerAdded:Connect(function(p: any)
			addedPlayer = p
		end)
		players:_addPlayer({ Name = "TestPlayer" })
		expect(addedPlayer).to.be.ok()
		expect(addedPlayer.Name).to.equal("TestPlayer")
		expect(#players:GetPlayers()).to.equal(1)
	end)

	it("should create RunService mock", function()
		local run = MockServices.createRunService()
		expect(run.IsStudio()).to.equal(true)
		expect(run.IsServer()).to.equal(true)
	end)

	it("should create CollectionService mock with tag support", function()
		local cs = MockServices.createCollectionService()
		local inst = { Name = "TestPart" }
		cs:AddTag(inst, "Enemy")
		expect(cs:HasTag(inst, "Enemy")).to.equal(true)
		expect(#cs:GetTagged("Enemy")).to.equal(1)
		cs:RemoveTag(inst, "Enemy")
		expect(cs:HasTag(inst, "Enemy")).to.equal(false)
	end)
end)
