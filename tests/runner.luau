--!strict
--[=[
	Test runner entry point.
	Discovers and runs all .spec.luau files in tests/ using require().
	Run with: lune run tests
]=]

local fs = require("@lune/fs")
local framework = require("./framework")

-- Discover spec files recursively
local function discoverSpecs(dir: string): { string }
	local specs: { string } = {}
	if not fs.isDir(dir) then
		return specs
	end
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			for _, spec in discoverSpecs(path) do
				table.insert(specs, spec)
			end
		elseif entry:match("%.spec%.luau$") then
			table.insert(specs, path)
		end
	end
	return specs
end

-- Main
print("\n=== Roblox Template Test Runner ===\n")

local testDir = "tests"
local specs = discoverSpecs(testDir)
table.sort(specs)

if #specs == 0 then
	print("No spec files found in tests/")
	require("@lune/process").exit(1)
end

print(`Found {#specs} spec file(s):\n`)
for _, spec in specs do
	print(`  {spec}`)
end
print("")

-- Require each spec file. They register themselves with the framework on load.
-- Convert file paths to require paths: "tests/unit/Foo.spec.luau" -> "./unit/Foo.spec"
for _, spec in specs do
	local requirePath = "./" .. spec:gsub("^tests/", ""):gsub("%.luau$", "")
	require(requirePath)
end

-- Report results
framework.report()
