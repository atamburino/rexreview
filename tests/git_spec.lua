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

test("working tree and branch argv", function()
  same(rexreview.working_tree_argv(), argv_with("HEAD"))
  same(rexreview.against_argv("main"), argv_with("main...HEAD"))
end)

test("load parses stdout from the injected runner", function()
  local seen
  local diff, err = rexreview.load(function(argv, opts)
    seen = { argv = argv, opts = opts }
    return { ok = true, code = 0, stdout = read_file("modified.diff"), stderr = "" }
  end, { cwd = "/repo", env = { GIT_DIR = "/repo/.git" } })
  eq(err, nil)
  same(seen.argv, rexreview.working_tree_argv())
  eq(seen.opts.cwd, "/repo")
  eq(seen.opts.env.GIT_DIR, "/repo/.git")
  same(diff, rexreview.parse(read_file("modified.diff")))
end)

test("load uses a caller argv and an empty options table", function()
  local seen
  local custom = argv_with("main...HEAD")
  local diff, err = rexreview.load(function(argv, opts)
    seen = { argv = argv, opts = opts }
    return { code = 0, stdout = "" }
  end, { argv = custom })
  eq(err, nil)
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
  local diff, err = rexreview.load(function()
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
