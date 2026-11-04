local rexreview = require("rexreview")

local function argv_with(range)
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

local function argv_has(argv, flag)
  for i = 1, #argv do
    if argv[i] == flag then
      return true
    end
  end
  return false
end

local function working_tree(head_stdout, list_stdout, file_fn)
  local calls = {}
  local diff, err = rexreview.load(function(argv, opts)
    calls[#calls + 1] = { argv = argv, opts = opts }
    if argv_has(argv, "ls-files") then
      return { ok = true, code = 0, stdout = list_stdout, stderr = "" }
    end
    if argv_has(argv, "--no-index") then
      return file_fn(argv, opts)
    end
    return { ok = true, code = 0, stdout = head_stdout, stderr = "" }
  end, { cwd = "/repo" })
  return diff, err, calls
end

test("working tree and branch argv", function()
  same(rexreview.working_tree_argv(), argv_with("HEAD"))
  same(rexreview.against_argv("main"), argv_with("main...HEAD"))
end)

test("load parses stdout from the injected runner", function()
  local seen = {}
  local diff, err = rexreview.load(function(argv, opts)
    seen[#seen + 1] = { argv = argv, opts = opts }
    if argv_has(argv, "ls-files") then
      return { ok = true, code = 0, stdout = "", stderr = "" }
    end
    return { ok = true, code = 0, stdout = read_file("modified.diff"), stderr = "" }
  end, { cwd = "/repo", env = { GIT_DIR = "/repo/.git" } })
  eq(err, nil)
  eq(#seen, 2)
  same(seen[1].argv, rexreview.working_tree_argv())
  same(seen[2].argv, rexreview.untracked_list_argv())
  eq(seen[1].opts.cwd, "/repo")
  eq(seen[2].opts.cwd, "/repo")
  eq(seen[1].opts.env.GIT_DIR, "/repo/.git")
  eq(seen[2].opts.env.GIT_DIR, "/repo/.git")
  same(diff, rexreview.parse(read_file("modified.diff")))
end)

test("load uses a caller argv and an empty options table", function()
  local seen
  local calls = 0
  local custom = argv_with("main...HEAD")
  local diff, err = rexreview.load(function(argv, opts)
    calls = calls + 1
    seen = { argv = argv, opts = opts }
    return { code = 0, stdout = "" }
  end, { argv = custom })
  eq(err, nil)
  eq(calls, 1)
  same(seen.argv, custom)
  same(seen.opts, {})
  same(diff, { files = {} })
end)

test("load returns the runner error when git never starts", function()
  local diff, err = rexreview.load(function()
    return nil, "No such file or directory"
  end)
  eq(diff, nil)
  eq(err, "No such file or directory")
end)

test("load returns git stderr when the command fails", function()
  local diff, err = rexreview.load(function()
    return {
      ok = false,
      code = 128,
      stdout = read_file("added.diff"),
      stderr = "fatal: not a git repository\n",
    }
  end)
  eq(diff, nil)
  eq(err, "fatal: not a git repository")
end)

test("load reports a timeout", function()
  local diff, err = rexreview.load(function()
    return {
      ok = false,
      code = -1,
      stdout = "",
      stderr = "",
      timed_out = true,
      signal = "SIGTERM",
    }
  end)
  eq(diff, nil)
  eq(err, "git timed out")
end)

test("a normal exit may leave timed_out and signal nil", function()
  local diff, err = rexreview.load(function(argv)
    if argv_has(argv, "ls-files") then
      return { ok = true, code = 0, stdout = "", stderr = "", signal = nil, timed_out = nil }
    end
    return {
      ok = true,
      code = 0,
      stdout = read_file("modified.diff"),
      stderr = "",
      signal = nil,
      timed_out = nil,
    }
  end, { cwd = "/repo" })
  eq(err, nil)
  same(diff, rexreview.parse(read_file("modified.diff")))
end)

test("load accepts a callable table like rex.exec", function()
  local seen
  local exec = {
    start = function(argv, opts)
      seen = { argv = argv, opts = opts }
      if argv_has(argv, "ls-files") then
        return { ok = true, code = 0, stdout = "", stderr = "", signal = nil, timed_out = nil }
      end
      return {
        ok = true,
        code = 0,
        stdout = read_file("added.diff"),
        stderr = "",
        signal = nil,
        timed_out = nil,
      }
    end,
  }
  setmetatable(exec, {
    __call = function(self, argv, opts)
      return self.start(argv, opts)
    end,
  })
  eq(type(exec), "table")
  local diff, err = rexreview.load(exec, { cwd = "/repo" })
  eq(err, nil)
  eq(seen.opts.cwd, "/repo")
  same(diff, rexreview.parse(read_file("added.diff")))
end)

test("a missing executable is the runner's error string", function()
  local diff, err = rexreview.load(function()
    return nil, "git: executable file not found in PATH"
  end, { cwd = "/repo" })
  eq(diff, nil)
  eq(err, "git: executable file not found in PATH")
end)

test("git's --no-index usage collapses to one line", function()
  local usage = table.concat({
    "warning: Not a git repository. Use --no-index to compare two paths outside a working tree",
    "usage: git diff --no-index [<options>] <path> <path>",
    "",
    "Diff output format options",
    "    -p, --patch           generate patch",
  }, "\n")
  local diff, err = rexreview.load(function()
    return { ok = false, code = 129, stdout = "", stderr = usage, signal = nil, timed_out = nil }
  end, { cwd = "/tmp" })
  eq(diff, nil)
  eq(err, "not a git repository")
end)

test("an untracked text file is an all-added diff", function()
  local diff, err, calls = working_tree("", "notes.txt\0", function(argv)
    same(argv, rexreview.untracked_diff_argv("notes.txt"))
    return { ok = false, code = 1, stdout = read_file("untracked.diff"), stderr = "" }
  end)
  eq(err, nil)
  eq(#calls, 3)
  eq(calls[1].opts.cwd, "/repo")
  eq(calls[3].opts.cwd, "/repo")
  same(calls[2].argv, rexreview.untracked_list_argv())
  same(diff, rexreview.parse(read_file("untracked.diff")))
  eq(diff.files[1].status, "added")
  eq(diff.files[1].old_path, nil)
  eq(diff.files[1].new_path, "notes.txt")
  local lines = diff.files[1].hunks[1].lines
  eq(#lines, 2)
  eq(lines[1].kind, "add")
  eq(lines[1].text, "fresh")
  eq(lines[2].kind, "add")
  eq(lines[2].text, "line")
end)

test("--no-index exit code 1 is success for an untracked file", function()
  local diff, err = working_tree("", "notes.txt\0", function()
    return {
      ok = false,
      code = 1,
      stdout = read_file("untracked.diff"),
      stderr = "warning: not a failure\n",
      signal = nil,
      timed_out = nil,
    }
  end)
  eq(err, nil)
  eq(#diff.files, 1)
  eq(diff.files[1].status, "added")
  eq(diff.files[1].new_path, "notes.txt")
end)

test("an untracked binary uses the binary file status", function()
  local diff, err = working_tree("", "assets/untracked.bin\0", function(argv)
    same(argv, rexreview.untracked_diff_argv("assets/untracked.bin"))
    return { ok = false, code = 1, stdout = read_file("untracked_binary.diff"), stderr = "" }
  end)
  eq(err, nil)
  same(diff, rexreview.parse(read_file("untracked_binary.diff")))
  eq(diff.files[1].status, "binary")
  eq(diff.files[1].old_path, nil)
  eq(diff.files[1].new_path, "assets/untracked.bin")
  eq(#diff.files[1].hunks, 0)
end)

test("an ignored path left out of ls-files is excluded", function()
  local diff, err, calls = working_tree("", "notes.txt\0", function(argv)
    check(argv[#argv] ~= "build/secret.log")
    return { ok = false, code = 1, stdout = read_file("untracked.diff"), stderr = "" }
  end)
  eq(err, nil)
  same(calls[2].argv, rexreview.untracked_list_argv())
  eq(#calls, 3)
  eq(#diff.files, 1)
  eq(diff.files[1].new_path, "notes.txt")
  for i = 1, #calls do
    for j = 1, #calls[i].argv do
      check(calls[i].argv[j] ~= "build/secret.log")
    end
  end
end)

test("an untracked path with spaces stays one path", function()
  local diff, err, calls = working_tree("", "src/my new file.txt\0", function(argv)
    same(argv, rexreview.untracked_diff_argv("src/my new file.txt"))
    eq(argv[#argv], "src/my new file.txt")
    return { ok = false, code = 1, stdout = read_file("untracked_space.diff"), stderr = "" }
  end)
  eq(err, nil)
  eq(#calls, 3)
  same(diff, rexreview.parse(read_file("untracked_space.diff")))
  eq(diff.files[1].status, "added")
  eq(diff.files[1].new_path, "src/my new file.txt")
end)

test("tracked and untracked files sort by path", function()
  local list = "src/my new file.txt\0notes.txt\0"
  local diff, err, calls = working_tree(read_file("deleted.diff"), list, function(argv)
    local name = argv[#argv]
    if name == "src/my new file.txt" then
      return { ok = false, code = 1, stdout = read_file("untracked_space.diff"), stderr = "" }
    end
    return { ok = false, code = 1, stdout = read_file("untracked.diff"), stderr = "" }
  end)
  eq(err, nil)
  eq(calls[3].argv[#calls[3].argv], "src/my new file.txt")
  eq(calls[4].argv[#calls[4].argv], "notes.txt")
  eq(#diff.files, 3)
  eq(diff.files[1].new_path, "notes.txt")
  eq(diff.files[1].status, "added")
  eq(diff.files[2].old_path, "src/gone.txt")
  eq(diff.files[2].status, "deleted")
  eq(diff.files[3].new_path, "src/my new file.txt")
  eq(diff.files[3].status, "added")
end)

test("a failed untracked diff fails the load", function()
  local diff, err = working_tree("", "notes.txt\0", function()
    return { ok = false, code = 128, stdout = "", stderr = "fatal: boom\n" }
  end)
  eq(diff, nil)
  eq(err, "fatal: boom")
end)

test("load rejects a runner that is not callable", function()
  local diff, err = rexreview.load("rex.exec")
  eq(diff, nil)
  eq(err, "runner must be callable")
  local plain = {}
  diff, err = rexreview.load(plain)
  eq(diff, nil)
  eq(err, "runner must be callable")
end)

test("library code does not print or shell out", function()
  local names = {
    "rexreview/parse.lua",
    "rexreview/git.lua",
    "rexreview/init.lua",
    "rexreview/palette.lua",
    "rexreview/state.lua",
    "rexreview/view.lua",
    "rexreview/pane.lua",
    "rexreview/plugin.lua",
  }
  for i = 1, #names do
    local path = root .. "/" .. names[i]
    local f = assert(io.open(path, "r"))
    local src = f:read("*a")
    f:close()
    check(not src:find("print%s*%("), names[i])
    check(not src:find("io%.write"), names[i])
    check(not src:find("io%.popen"), names[i])
    check(not src:find("os%.execute"), names[i])
  end
end)
