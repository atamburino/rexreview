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

local function first_line(message)
  local line = message:match("^[^\r\n]+") or message
  return (line:gsub("%s+$", ""))
end

local function failed(result)
  -- A timeout is ok=false, code=-1, timed_out=true, signal="SIGTERM".
  -- A normal exit leaves timed_out and signal nil, not false.
  if result.timed_out then
    return "git timed out"
  end
  local message = result.stderr
  if type(message) == "string" then
    message = message:gsub("%s+$", "")
  end
  if message == nil or message == "" then
    return "git exited with status " .. tostring(result.code)
  end
  -- Outside a repository, git diff prints the full --no-index usage.
  if message:find("--no-index", 1, true) then
    return "not a git repository"
  end
  return first_line(message)
end

local function succeeded(result)
  if result.timed_out then
    return false
  end
  if result.ok ~= nil then
    return result.ok and true or false
  end
  return result.code == 0
end

local function callable(runner)
  if type(runner) == "function" then
    return true
  end
  if type(runner) ~= "table" then
    return false
  end
  local mt = getmetatable(runner)
  return type(mt) == "table" and type(mt.__call) == "function"
end

local function runner_error(err)
  if type(err) ~= "string" or err == "" then
    return "git failed to run"
  end
  return first_line(err)
end

-- runner(argv, opts) matches rex.exec(argv[, opts]). In Rex, rex.exec is a
-- callable table: type(rex.exec) is "table" and rex.exec.start is the
-- function. A result has ok, code, stdout, and stderr. timed_out and signal
-- are nil on success. A missing executable is nil and an error string.
function M.load(runner, opts)
  if not callable(runner) then
    return nil, "runner must be callable"
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
    return nil, runner_error(err)
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
