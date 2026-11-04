local rexreview = require("rexreview")
local view = require("rexreview.view")
local pane = require("rexreview.pane")
local plugin = require("rexreview.plugin")

local function find_calls(api, name)
  local found = {}
  for i = 1, #api.calls do
    if api.calls[i].name == name then
      found[#found + 1] = api.calls[i]
    end
  end
  return found
end

local function fake_rex(stdout)
  local api = { calls = {} }
  local function record(name, args)
    api.calls[#api.calls + 1] = { name = name, args = args }
  end
  api.exec = function(argv, opts)
    record("exec", { argv = argv, opts = opts })
    return { ok = true, code = 0, stdout = stdout or "", stderr = "" }
  end
  api.layout = {
    block = function(spec)
      return { block = { flavor = spec.flavor, options = spec.options } }
    end,
    horizontal = function(ratio, a, b)
      return {
        split = { direction = "horizontal", ratio = ratio, before = a, after = b },
      }
    end,
    vertical = function(ratio, a, b)
      return {
        split = { direction = "vertical", ratio = ratio, before = a, after = b },
      }
    end,
  }
  api.session = {}
  function api.session.new_split(args)
    record("new_split", args)
    return {
      block_ids = { "block:list" },
      anchor_id = args.anchor_id or "block:editor",
      revision = 1,
    }
  end
  function api.session.new_layer(args)
    record("new_layer", args)
    return {
      layer_id = "layer:float",
      block_ids = { "block:list", "block:diff" },
      revision = 2,
    }
  end
  function api.session.close_layer(args)
    record("close_layer", args)
    return { revision = 3 }
  end
  function api.session.set_block_label(args)
    record("set_block_label", args)
    return { revision = 4 }
  end
  function api.session.focus_block(args)
    record("focus_block", args)
    return { revision = 5 }
  end
  function api.call(method, args)
    record(method, args)
    return {}
  end
  api.block = {}
  function api.block.call(creator, method, args)
    record("block." .. method, { creator = creator, args = args })
    if method == "pwd" then
      return { pwd = "file://host/repo" }
    end
    return {}
  end
  api.client = {}
  function api.client.queue(name, args)
    record("queue", { name = name, args = args })
  end
  return api
end

local function ctx()
  return { session_id = "session:1", block_id = "block:editor" }
end

test("open splits a narrow pane beside the focused block", function()
  local api = fake_rex(read_file("modified.diff"))
  local ctl = pane.controller(api)
  local result, err = ctl.open(ctx(), {})
  eq(err, nil)
  eq(result.open, true)
  eq(result.expanded, false)
  eq(ctl.state.open, true)
  eq(ctl.state.expanded, false)

  local exec = find_calls(api, "exec")[1]
  same(exec.args.argv, rexreview.working_tree_argv())
  eq(exec.args.opts.cwd, "/repo")

  local split = find_calls(api, "new_split")[1]
  eq(split.args.direction, "horizontal")
  eq(split.args.side, "after")
  eq(split.args.ratio, view.NARROW_RATIO)
  eq(split.args.anchor_id, "block:editor")
  eq(split.args.focus, true)
  eq(split.args.layout.block.flavor, view.flavor)
  check(split.args.layout.block.options.command[3]:find("src/app.txt", 1, true) ~= nil)
  eq(split.args.layout.block.options.command[1], "printf")
  check(split.args.layout.split == nil)
  eq(#find_calls(api, "new_layer"), 0)

  local queued = find_calls(api, "queue")[1]
  eq(queued.args.name, "client.mode.enter")
  eq(queued.args.args.name, "rexreview")
end)

test("click expands to a floating layer and escape collapses it", function()
  local api = fake_rex(read_file("modified.diff"))
  local ctl = pane.controller(api)
  ctl.open(ctx(), {})
  local expanded, err = ctl.click(ctx(), 1)
  eq(err, nil)
  eq(expanded.expanded, true)
  eq(ctl.state.selected, 1)

  local closed = find_calls(api, "block.close")[1]
  eq(closed.args.block_id, "block:list")
  eq(closed.args.keep_last, true)
  eq(closed.args.session_id, "session:1")

  local layer = find_calls(api, "new_layer")[1]
  same(layer.args.bounds, view.FLOAT_BOUNDS)
  eq(layer.args.focus, true)
  eq(layer.args.layout.split.direction, "horizontal")
  local diff_text = layer.args.layout.split.after.block.options.command[3]
  check(diff_text:find(rexreview.palette.add .. "+1 ALPHA", 1, true) ~= nil)
  check(diff_text:find(rexreview.palette.delete .. "-1 alpha", 1, true) ~= nil)
  check(diff_text:find(rexreview.palette.hunk .. "@@ -1,4 +1,4 @@", 1, true) ~= nil)

  local back, err2 = ctl.escape(ctx())
  eq(err2, nil)
  eq(back.expanded, false)
  eq(ctl.state.expanded, false)
  eq(ctl.state.selected, 1)
  eq(find_calls(api, "close_layer")[1].args.layer_id, "layer:float")
  eq(#find_calls(api, "new_split"), 2)
  eq(#find_calls(api, "queue"), 1)
end)

test("a second click on the same file collapses the floating pane", function()
  local api = fake_rex(read_file("rename.diff") .. "\n" .. read_file("binary.diff"))
  local ctl = pane.controller(api)
  ctl.open(ctx(), {})
  ctl.click(ctx(), 1)
  eq(ctl.state.expanded, true)
  local collapsed, err = ctl.click(ctx(), 1)
  eq(err, nil)
  eq(collapsed.expanded, false)
  eq(ctl.state.selected, 1)
  eq(#find_calls(api, "close_layer"), 1)
  eq(#find_calls(api, "new_layer"), 1)
end)

test("choosing another file rebuilds the floating diff", function()
  local api = fake_rex(read_file("modified.diff") .. read_file("added.diff"))
  local ctl = pane.controller(api)
  ctl.open(ctx(), {})
  ctl.click(ctx(), 1)
  local moved, err = ctl.select_delta(ctx(), 1)
  eq(err, nil)
  eq(moved.selected, 2)
  eq(moved.expanded, true)
  local layers = find_calls(api, "new_layer")
  eq(#layers, 2)
  eq(#find_calls(api, "close_layer"), 1)
  local diff_text = layers[2].args.layout.split.after.block.options.command[3]
  check(diff_text:find("+fresh", 1, true) ~= nil)
  check(diff_text:find("1 ALPHA", 1, true) == nil)
end)

test("a split with no focused block keeps the anchor the server reports", function()
  local api = fake_rex(read_file("modified.diff"))
  local ctl = pane.controller(api)
  ctl.open({ session_id = "session:1" }, { cwd = "/work" })
  ctl.select_delta({ session_id = "session:1" }, 1)
  local splits = find_calls(api, "new_split")
  eq(splits[1].args.anchor_id, nil)
  eq(splits[2].args.anchor_id, "block:editor")
end)

test("escape while narrow leaves the diff keys", function()
  local api = fake_rex(read_file("modified.diff"))
  local ctl = pane.controller(api)
  ctl.open(ctx(), {})
  local result = ctl.escape(ctx())
  eq(result.expanded, false)
  eq(result.open, true)
  eq(#find_calls(api, "new_split"), 1)
  local queues = find_calls(api, "queue")
  eq(queues[#queues].args.name, "client.mode.exit")
end)

local function screen_of(api)
  return find_calls(api, "new_split")[1].args.layout.block.options.command[3]
end

local function callable_exec(fn)
  local exec = { start = fn }
  setmetatable(exec, {
    __call = function(self, argv, opts)
      return self.start(argv, opts)
    end,
  })
  return exec
end

test("a callable rex.exec loads the diff and receives cwd", function()
  local api = fake_rex(read_file("modified.diff"))
  local seen
  api.exec = callable_exec(function(argv, opts)
    seen = { argv = argv, opts = opts }
    return {
      ok = true,
      code = 0,
      stdout = read_file("modified.diff"),
      stderr = "",
      signal = nil,
      timed_out = nil,
    }
  end)
  eq(type(api.exec), "table")
  local ctl = pane.controller(api)
  api.block.call = function()
    return { pwd = "/repo" }
  end
  local result, err = ctl.open(ctx(), {})
  eq(err, nil)
  eq(result.open, true)
  eq(seen.opts.cwd, "/repo")
  same(seen.argv, rexreview.working_tree_argv())
  check(screen_of(api):find("src/app.txt", 1, true) ~= nil)
end)

test("a timeout and a missing git are one line in the pane", function()
  local api = fake_rex("")
  api.exec = callable_exec(function()
    return {
      ok = false,
      code = -1,
      stdout = "",
      stderr = "",
      timed_out = true,
      signal = "SIGTERM",
    }
  end)
  local ctl = pane.controller(api)
  ctl.open(ctx(), { cwd = "/repo" })
  check(screen_of(api):find("git timed out", 1, true) ~= nil)

  api.calls = {}
  api.exec = callable_exec(function()
    return nil, "git: executable file not found in PATH"
  end)
  ctl = pane.controller(api)
  ctl.open(ctx(), { cwd = "/repo" })
  local text = screen_of(api)
  check(text:find("git: executable file not found in PATH", 1, true) ~= nil)
  check(text:find("usage:", 1, true) == nil)
end)

test("outside a repository the pane shows one line", function()
  local usage = table.concat({
    "warning: Not a git repository. Use --no-index to compare two paths outside a working tree",
    "usage: git diff --no-index [<options>] <path> <path>",
    "Diff output format options",
  }, "\n")
  local api = fake_rex("")
  api.exec = callable_exec(function()
    return { ok = false, code = 129, stdout = "", stderr = usage, signal = nil, timed_out = nil }
  end)
  local ctl = pane.controller(api)
  ctl.open(ctx(), { cwd = "/tmp" })
  local text = screen_of(api)
  check(text:find("not a git repository", 1, true) ~= nil)
  check(text:find("--no-index", 1, true) == nil)
  check(text:find("usage:", 1, true) == nil)
end)

test("open does not run git without a working directory", function()
  local api = fake_rex(read_file("modified.diff"))
  local ran = false
  api.exec = function()
    ran = true
    return { ok = true, code = 0, stdout = "", stderr = "" }
  end
  api.block.call = function()
    return {}
  end
  local ctl = pane.controller(api)
  local result, err = ctl.open({ session_id = "session:1", block_id = "block:editor" }, {})
  eq(err, nil)
  eq(result.open, true)
  eq(ran, false)
  check(screen_of(api):find("no working directory", 1, true) ~= nil)
end)

test("a failed git command is shown in the pane", function()
  local api = fake_rex("")
  api.exec = function()
    api.calls[#api.calls + 1] = { name = "exec", args = {} }
    return { ok = false, code = 128, stdout = "", stderr = "fatal: not a git repository\n" }
  end
  local ctl = pane.controller(api)
  local result, err = ctl.open(ctx(), { cwd = "/work" })
  eq(err, nil)
  eq(result.open, true)
  local split = find_calls(api, "new_split")[1]
  check(split.args.layout.block.options.command[3]:find("fatal: not a git repository", 1, true) ~= nil)
end)

test("register binds shift+cmd+d and the diff actions", function()
  local actions = {}
  local binds = {}
  local modes = {}
  local rex = {
    action = function(spec)
      actions[#actions + 1] = spec
    end,
    bind = function(key, action, args)
      binds[#binds + 1] = { key = key, action = action, args = args }
    end,
    mode = function(name, options)
      modes[#modes + 1] = { name = name, options = options }
    end,
  }
  plugin.register(rex)

  eq(#modes, 1)
  eq(modes[1].name, "rexreview")
  eq(modes[1].options.exclusive, true)

  local names = {}
  for i = 1, #actions do
    names[actions[i].name] = actions[i]
    check(actions[i].name:match("^[a-z0-9_]+$") ~= nil, actions[i].name)
    check(type(actions[i].run) == "function")
    check(type(actions[i].title) == "string")
  end
  check(names.rexreview_diff ~= nil)
  check(names.rexreview_click ~= nil)
  check(names.rexreview_escape ~= nil)
  check(names.rexreview_select ~= nil)
  eq(names.rexreview_diff.args.cwd, "string?")
  eq(names.rexreview_click.args.index, "integer?")

  local by_key = {}
  for i = 1, #binds do
    by_key[binds[i].key] = binds[i]
  end
  eq(by_key["shift+cmd+d"].action, "rexreview_diff")
  eq(by_key["rexreview/shift+cmd+d"].action, "rexreview_diff")
  eq(by_key["rexreview/escape"].action, "rexreview_escape")
  eq(by_key["rexreview/enter"].action, "rexreview_click")
  eq(by_key["rexreview/down"].action, "rexreview_select")
  eq(by_key["rexreview/down"].args.delta, 1)
  eq(by_key["rexreview/up"].args.delta, -1)
end)

test("the suggested key can be replaced", function()
  local binds = {}
  local rex = {
    action = function() end,
    bind = function(key, action, args)
      binds[#binds + 1] = { key = key, action = action, args = args }
    end,
    mode = function() end,
  }
  plugin.register(rex, { key = "alt+cmd+g" })
  local by_key = {}
  for i = 1, #binds do
    by_key[binds[i].key] = binds[i].action
  end
  eq(by_key["alt+cmd+g"], "rexreview_diff")
  eq(by_key["rexreview/alt+cmd+g"], "rexreview_diff")
  eq(by_key["shift+cmd+d"], nil)
end)
