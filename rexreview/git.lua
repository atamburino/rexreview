local parse = require("rexreview.parse")

local M = {}

local function diff_argv(range)
  return {
    "git",
    "-c", "core.quotePath=true",
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--find-renames",
    "--src-prefix=a/",
    "--dst-prefix=b/",
    range,
  }
end

-- Tracked working tree against HEAD, staged and unstaged together.
-- Untracked files are absent from git diff output.
function M.working_tree_argv()
  return diff_argv("HEAD")
end

-- Changes on HEAD since it diverged from ref (git diff ref...HEAD).
function M.against_argv(ref)
  return diff_argv(ref .. "...HEAD")
end

local function failed(result)
  if result.timed_out and (result.stderr == nil or result.stderr == "") then
    return "git timed out"
  end
  local message = result.stderr
  if type(message) == "string" then
    message = message:gsub("%s+$", "")
  end
  if message == nil or message == "" then
    return "git exited with status " .. tostring(result.code)
  end
  return message
end

local function succeeded(result)
  if result.ok ~= nil then
    return result.ok and true or false
  end
  return result.code == 0 and not result.timed_out
end

-- runner(argv, opts) matches rex.exec(argv[, opts]): a result table with
-- ok, code, stdout, stderr, and timed_out, or nil and an error string
-- when the program never ran.
function M.load(runner, opts)
  if type(runner) ~= "function" then
    return nil, "runner must be a function"
  end
  opts = opts or {}
  local argv = opts.argv or M.working_tree_argv()
  local exec_opts = {}
  if opts.cwd ~= nil then
    exec_opts.cwd = opts.cwd
  end
  if opts.env ~= nil then
    exec_opts.env = opts.env
  end
  local result, err = runner(argv, exec_opts)
  if result == nil then
    return nil, err or "git failed to run"
  end
  if type(result) ~= "table" then
    return nil, "runner returned " .. type(result)
  end
  if not succeeded(result) then
    return nil, failed(result)
  end
  return parse.parse(result.stdout or "")
end

return M
