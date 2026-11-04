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
-- Untracked files are not in this diff; load adds them separately.
function M.working_tree_argv()
  return diff_argv("HEAD")
end

-- Changes on HEAD since it diverged from ref (git diff ref...HEAD).
-- Branch mode does not include untracked files.
function M.against_argv(ref)
  return diff_argv(ref .. "...HEAD")
end

-- Untracked paths, NUL-separated. --exclude-standard applies .gitignore.
-- -z keeps names with spaces and other odd bytes intact.
function M.untracked_list_argv()
  return {
    "git",
    "-c", "core.quotePath=true",
    "ls-files",
    "--others",
    "--exclude-standard",
    "-z",
  }
end

-- One untracked path as an all-added diff against /dev/null.
-- Does not update the index. Exits 1 when the file differs.
function M.untracked_diff_argv(path)
  return {
    "git",
    "-c", "core.quotePath=true",
    "diff",
    "--no-color",
    "--no-ext-diff",
    "--src-prefix=a/",
    "--dst-prefix=b/",
    "--no-index",
    "--",
    "/dev/null",
    path,
  }
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

-- git diff --no-index exits 1 when the two paths differ. That is the
-- successful case for an untracked file. Other statuses still fail.
local function no_index_succeeded(result)
  if result.timed_out then
    return false
  end
  if result.code == 0 or result.code == 1 then
    return true
  end
  if result.code == nil and result.ok ~= nil then
    return result.ok and true or false
  end
  return false
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

local function run(runner, argv, exec_opts)
  local result, err = runner(argv, exec_opts)
  if result == nil then
    return nil, runner_error(err)
  end
  if type(result) ~= "table" then
    return nil, "runner returned " .. type(result)
  end
  return result
end

-- git ls-files -z records are separated by NUL, including the last one.
local function split_nul(text)
  local paths = {}
  local pos = 1
  local n = #text
  while pos <= n do
    local z = text:find("\0", pos, true)
    if not z then
      if pos <= n then
        paths[#paths + 1] = text:sub(pos)
      end
      break
    end
    if z > pos then
      paths[#paths + 1] = text:sub(pos, z - 1)
    end
    pos = z + 1
  end
  return paths
end

local function path_key(file)
  return file.new_path or file.old_path or ""
end

local function merge_untracked(runner, exec_opts, diff)
  local listed, err = run(runner, M.untracked_list_argv(), exec_opts)
  if not listed then
    return nil, err
  end
  if not succeeded(listed) then
    return nil, failed(listed)
  end
  local paths = split_nul(listed.stdout or "")
  if #paths == 0 then
    return diff
  end
  local seen = {}
  for i = 1, #diff.files do
    local file = diff.files[i]
    if file.new_path then
      seen[file.new_path] = true
    end
    if file.old_path then
      seen[file.old_path] = true
    end
  end
  local added = false
  for i = 1, #paths do
    local path = paths[i]
    if not seen[path] then
      local result, rerr = run(runner, M.untracked_diff_argv(path), exec_opts)
      if not result then
        return nil, rerr
      end
      if not no_index_succeeded(result) then
        return nil, failed(result)
      end
      local parsed = parse.parse(result.stdout or "")
      for j = 1, #parsed.files do
        diff.files[#diff.files + 1] = parsed.files[j]
        added = true
      end
      seen[path] = true
    end
  end
  if added then
    table.sort(diff.files, function(a, b)
      return path_key(a) < path_key(b)
    end)
  end
  return diff
end

-- runner(argv, opts) matches rex.exec(argv[, opts]). In Rex, rex.exec is a
-- callable table: type(rex.exec) is "table" and rex.exec.start is the
-- function. A result has ok, code, stdout, and stderr. timed_out and signal
-- are nil on success. A missing executable is nil and an error string.
-- With no opts.argv, this is the working tree: git diff HEAD, then each
-- untracked file as git diff --no-index. A caller argv (branch mode) is
-- only that diff.
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
  local result, err = run(runner, argv, exec_opts)
  if not result then
    return nil, err
  end
  if not succeeded(result) then
    return nil, failed(result)
  end
  local diff = parse.parse(result.stdout or "")
  if opts.argv ~= nil then
    return diff
  end
  return merge_untracked(runner, exec_opts, diff)
end

return M
