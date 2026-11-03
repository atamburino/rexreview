local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "."
end

local tests_dir = dirname(arg[0] or "tests/run.lua")
local root = dirname(tests_dir)
if root == "" then
  root = "."
end

package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local tests = {}
local passed = 0
local failed = 0

function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

function check(cond, message)
  if not cond then
    error(message or "assertion failed", 2)
  end
end

function eq(actual, expected, message)
  if actual ~= expected then
    error((message or "not equal") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected), 2)
  end
end

function same(actual, expected, path)
  path = path or "$"
  if type(actual) ~= type(expected) then
    error(path .. " type " .. type(actual) .. " ~= " .. type(expected), 2)
  end
  if type(actual) ~= "table" then
    if actual ~= expected then
      error(path .. " " .. tostring(actual) .. " ~= " .. tostring(expected), 2)
    end
    return
  end
  local seen = {}
  for k, v in pairs(expected) do
    seen[k] = true
    same(actual[k], v, path .. "." .. tostring(k))
  end
  for k, v in pairs(actual) do
    if not seen[k] then
      error(path .. " unexpected " .. tostring(k) .. " = " .. tostring(v), 2)
    end
  end
end

local function read_file(name)
  local path = root .. "/tests/fixtures/" .. name
  local f, err = io.open(path, "rb")
  if not f then
    error("open " .. path .. ": " .. tostring(err))
  end
  local text = f:read("*a")
  f:close()
  return text
end

_G.test = test
_G.check = check
_G.eq = eq
_G.same = same
_G.read_file = read_file
_G.root = root

dofile(tests_dir .. "/parse_spec.lua")
dofile(tests_dir .. "/git_spec.lua")

for i = 1, #tests do
  local t = tests[i]
  local ok, err = pcall(t.fn)
  if ok then
    passed = passed + 1
    io.write("ok   " .. t.name .. "\n")
  else
    failed = failed + 1
    io.write("FAIL " .. t.name .. "\n" .. tostring(err) .. "\n")
  end
end

io.write(string.format("%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
