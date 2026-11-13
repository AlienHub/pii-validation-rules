-- Lua test runner (no external dependencies). Works on Lua 5.1 / 5.3 / 5.4 / LuaJIT.
--
--   lua5.4 tests/lua/run.lua [--report reports/lua-test-report-lua5.4.json]
--                            [--syntax-verdicts reports/lua-syntax-verdicts-lua5.4.json]
--                            [--rules rules] [--fixtures fixtures] [--only suite_name]
--
-- Writes a machine-readable report (suites, cases, assertion counts, failures,
-- runtime) and exits non-zero when any case fails.

local script_dir = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
local root = script_dir .. "/../.."
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  script_dir .. "/?.lua",
  package.path,
}, ";")

local json = require("pii.json")

local opts = {
  report = nil,
  syntax_verdicts = nil,
  rules = root .. "/rules",
  fixtures = root .. "/fixtures",
  only = nil,
}
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    if a == "--report" then opts.report = arg[i + 1]; i = i + 2
    elseif a == "--syntax-verdicts" then opts.syntax_verdicts = arg[i + 1]; i = i + 2
    elseif a == "--rules" then opts.rules = arg[i + 1]; i = i + 2
    elseif a == "--fixtures" then opts.fixtures = arg[i + 1]; i = i + 2
    elseif a == "--only" then opts.only = arg[i + 1]; i = i + 2
    else error("unknown argument " .. a) end
  end
end

-- ------------------------------------------------------------------ tiny framework
local T = { suites = {}, current = nil, opts = opts, root = root }

local function runtime_name()
  if rawget(_G, "jit") and jit.version then return jit.version end
  return _VERSION
end

function T.suite(name)
  local s = { name = name, cases = {}, passed = 0, failed = 0, assertions = 0, ms = 0 }
  T.suites[#T.suites + 1] = s
  T.current = s
  return s
end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then return json.encode(v) end
  return tostring(v)
end

function T.check(cond, msg)
  T.current.assertions = T.current.assertions + 1
  T.current._case.assertions = T.current._case.assertions + 1
  if not cond then
    error({ test_failure = true, message = msg or "assertion failed" }, 2)
  end
end

function T.eq(actual, expected, msg)
  T.check(actual == expected, string.format("%s: expected %s, got %s", msg or "eq", fmt(expected), fmt(actual)))
end

function T.case(name, fn)
  local s = T.current
  local c = { name = name, assertions = 0, status = "pass" }
  s._case = c
  local t0 = os.clock()
  local ok, err = pcall(fn)
  c.ms = math.floor((os.clock() - t0) * 1000 + 0.5)
  if not ok then
    c.status = "fail"
    if type(err) == "table" and err.test_failure then
      c.error = err.message
    else
      c.error = tostring(err)
    end
    s.failed = s.failed + 1
    io.write("  FAIL ", s.name, " :: ", name, "\n       ", c.error, "\n")
  else
    s.passed = s.passed + 1
  end
  s.cases[#s.cases + 1] = c
  s._case = nil
end

function T.load_fixture(name)
  return json.decode_file(opts.fixtures .. "/" .. name)
end

function T.write_json(path, value)
  local f = assert(io.open(path, "wb"))
  f:write(json.encode(value, " "))
  f:write("\n")
  f:close()
end

-- ------------------------------------------------------------------ run suites
local SUITES = {
  "suite_json",
  "suite_checksum_fixtures",
  "suite_reference_vectors",
  "suite_checksum_properties",
  "suite_syntax_subset",
  "suite_normalize",
  "suite_semantic",
  "suite_policies",
  "suite_edge_cases",
  "suite_api",
}

local t_start = os.clock()
local wall_start = os.time()
io.write("pii Lua tests on ", runtime_name(), "\n")
for _, mod in ipairs(SUITES) do
  if not opts.only or opts.only == mod or opts.only == mod:gsub("^suite_", "") then
    local suite_fn = require(mod)
    local s0 = os.clock()
    suite_fn(T)
    local s = T.current
    s.ms = math.floor((os.clock() - s0) * 1000 + 0.5)
    io.write(string.format("  %-28s %4d cases  %3d failed  %7d assertions  %6d ms\n",
      s.name, #s.cases, s.failed, s.assertions, s.ms))
  end
end

local total_cases, total_failed, total_assertions = 0, 0, 0
for _, s in ipairs(T.suites) do
  total_cases = total_cases + #s.cases
  total_failed = total_failed + s.failed
  total_assertions = total_assertions + s.assertions
end
local cpu_seconds = os.clock() - t_start

io.write(string.format("TOTAL %d cases, %d passed, %d failed, %d assertions, %.3fs cpu on %s\n",
  total_cases, total_cases - total_failed, total_failed, total_assertions, cpu_seconds, runtime_name()))

if opts.report then
  local suites_out = {}
  local failures = {}
  for _, s in ipairs(T.suites) do
    local cases = {}
    for _, c in ipairs(s.cases) do
      cases[#cases + 1] = { name = c.name, status = c.status, assertions = c.assertions, ms = c.ms, error = c.error }
      if c.status == "fail" then failures[#failures + 1] = { suite = s.name, case = c.name, error = c.error } end
    end
    suites_out[#suites_out + 1] = { name = s.name, cases = cases, passed = s.passed, failed = s.failed,
      assertions = s.assertions, ms = s.ms }
  end
  T.write_json(opts.report, {
    stage = "implementation_lua_runtime_tests",
    command = "lua tests/lua/run.lua --report <path> --syntax-verdicts <path>",
    runtime = runtime_name(),
    run_at_utc = os.date("!%Y-%m-%dT%H:%M:%SZ", wall_start),
    summary = {
      suites = #T.suites,
      cases = total_cases,
      passed = total_cases - total_failed,
      failed = total_failed,
      assertions = total_assertions,
      cpu_seconds = tonumber(string.format("%.3f", cpu_seconds)),
    },
    failures = failures,
    suites = suites_out,
  })
end

os.exit(total_failed == 0 and 0 or 1)
