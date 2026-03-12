--!strict
--[=[
	Test framework: provides describe/it/expect/beforeEach/afterEach.
	Spec files require this module to get test globals.
	The runner calls framework.run() to execute and report.
]=]

local process = require("@lune/process")

local framework = {}

type TestResult = {
	name: string,
	passed: boolean,
	error: string?,
}

type SuiteResult = {
	name: string,
	tests: { TestResult },
}

local allSuites: { SuiteResult } = {}
local currentSuite: SuiteResult? = nil
local beforeEachFn: (() -> ())? = nil
local afterEachFn: (() -> ())? = nil

-- Expect object for assertions
local function createExpect(value: any)
	local negate = false

	local function check(condition: boolean, msg: string)
		if negate then
			condition = not condition
			msg = "NOT " .. msg
		end
		if not condition then
			error(msg, 4)
		end
	end

	-- Build the "be" table
	local be: any = {}

	function be.ok()
		check(value ~= nil and value ~= false, `Expected {tostring(value)} to be truthy`)
	end

	function be.near(expected: number, tolerance: number?)
		local tol = tolerance or 0.001
		check(math.abs((value :: number) - expected) <= tol, `Expected {value} to be near {expected} (tolerance {tol})`)
	end

	function be.a(expectedType: string)
		check(typeof(value) == expectedType, `Expected {tostring(value)} to be a {expectedType}, got {typeof(value)}`)
	end

	function be.greaterThan(expected: number)
		check((value :: number) > expected, `Expected {value} > {expected}`)
	end

	function be.greaterThanOrEqual(expected: number)
		check((value :: number) >= expected, `Expected {value} >= {expected}`)
	end

	function be.lessThan(expected: number)
		check((value :: number) < expected, `Expected {value} < {expected}`)
	end

	function be.lessThanOrEqual(expected: number)
		check((value :: number) <= expected, `Expected {value} <= {expected}`)
	end

	-- Build the "to" table
	local to: any = { be = be }

	function to.equal(expected: any)
		check(value == expected, `Expected {tostring(expected)}, got {tostring(value)}`)
	end

	function to.throw()
		check(typeof(value) == "function", "Expected a function for .to.throw()")
		local ok = pcall(value :: () -> ())
		check(not ok, "Expected function to throw, but it didn't")
	end

	-- Build the "never" proxy
	local never: any = {}
	setmetatable(never, {
		__index = function(_, key)
			negate = true
			if key == "to" then
				return to
			end
			return nil
		end,
	})

	return { to = to, never = never }
end

function framework.describe(name: string, fn: () -> ())
	local suite: SuiteResult = { name = name, tests = {} }
	local parentSuite = currentSuite
	local parentBeforeEach = beforeEachFn
	local parentAfterEach = afterEachFn
	currentSuite = suite
	beforeEachFn = nil
	afterEachFn = nil

	local ok, err = pcall(fn)
	if not ok then
		table.insert(suite.tests, { name = "[suite setup error]", passed = false, error = tostring(err) })
	end

	table.insert(allSuites, suite)
	currentSuite = parentSuite
	beforeEachFn = parentBeforeEach
	afterEachFn = parentAfterEach
end

function framework.it(name: string, fn: () -> ())
	if not currentSuite then
		error("it() must be called inside describe()")
	end

	if beforeEachFn then
		local ok, err = pcall(beforeEachFn :: () -> ())
		if not ok then
			table.insert(
				(currentSuite :: SuiteResult).tests,
				{ name = name, passed = false, error = "beforeEach failed: " .. tostring(err) }
			)
			return
		end
	end

	local ok, err = pcall(fn)
	table.insert((currentSuite :: SuiteResult).tests, {
		name = name,
		passed = ok,
		error = if ok then nil else tostring(err),
	})

	if afterEachFn then
		pcall(afterEachFn :: () -> ())
	end
end

function framework.itSKIP(name: string, _fn: () -> ())
	if currentSuite then
		table.insert((currentSuite :: SuiteResult).tests, { name = name .. " [SKIPPED]", passed = true, error = nil })
	end
end

function framework.beforeEach(fn: () -> ())
	beforeEachFn = fn
end

function framework.afterEach(fn: () -> ())
	afterEachFn = fn
end

framework.expect = createExpect

-- Report results and exit
function framework.report()
	local totalPassed = 0
	local totalFailed = 0
	local totalSkipped = 0

	for _, suite in allSuites do
		print(`--- {suite.name} ---`)
		for _, test in suite.tests do
			if test.name:match("%[SKIPPED%]$") then
				totalSkipped += 1
				print(`  SKIP  {test.name}`)
			elseif test.passed then
				totalPassed += 1
				print(`  PASS  {test.name}`)
			else
				totalFailed += 1
				print(`  FAIL  {test.name}`)
				print(`         {test.error}`)
			end
		end
	end

	print(`\n=== Results: {totalPassed} passed, {totalFailed} failed, {totalSkipped} skipped ===\n`)

	if totalFailed > 0 then
		process.exit(1)
	end
	process.exit(0)
end

return framework
