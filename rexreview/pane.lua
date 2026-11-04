local git = require("rexreview.git")
local state_mod = require("rexreview.state")
local view = require("rexreview.view")

local M = {}

local TERMINAL = "com.superlogical.terminal"

local function path_from(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  local from_url = value:match("^file://[^/]*(/.*)$")
  if from_url then
    return from_url
  end
  if value:sub(1, 1) == "/" then
    return value
  end
  return nil
end

-- pwd is the directory the shell reported. On api 8 a zsh block often
-- returns {}. process.foreground.cwd is the foreground process's directory.
-- Both calls require block_id; omitting it is a 400.
local function block_cwd(rex, block_id)
  if type(block_id) ~= "string" or block_id == "" then
    return nil
  end
  if not rex.block or not rex.block.call then
    return nil
  end
  local pwd = rex.block.call(TERMINAL, "pwd", { block_id = block_id })
  if type(pwd) == "table" then
    local path = path_from(pwd.pwd)
    if path then
      return path
    end
  end
  local proc = rex.block.call(TERMINAL, "process", { block_id = block_id })
  if type(proc) == "table" and type(proc.foreground) == "table" then
    return path_from(proc.foreground.cwd)
  end
  return nil
end

-- ctx.origin is key, palette, cli, api, or script. Client actions queued
-- from cli fail after run returns, which a pcall cannot catch.
local function from_client(ctx)
  local origin = ctx and ctx.origin
  return origin == "key" or origin == "palette"
end

local function queue_mode(rex, name, args)
  if not rex.client or not rex.client.queue then
    return
  end
  rex.client.queue(name, args)
end

function M.controller(rex)
  local session = {
    state = state_mod.initial(),
    diff = { files = {} },
    anchor_id = nil,
    block_id = nil,
    block_ids = nil,
    layer_id = nil,
    floating = false,
    cwd = nil,
    mode = false,
  }

  local function load_diff(ctx, args)
    if args and type(args.cwd) == "string" and args.cwd ~= "" then
      session.cwd = args.cwd
    elseif session.cwd == nil then
      session.cwd = block_cwd(rex, ctx and ctx.block_id)
    end
    if type(session.cwd) ~= "string" or session.cwd == "" then
      session.diff = { files = {}, error = "no working directory" }
      session.state.selected = nil
      return
    end
    local loaded, err = git.load(rex.exec, { cwd = session.cwd })
    if not loaded then
      session.diff = { files = {}, error = err or "git diff failed" }
      session.state.selected = nil
      return
    end
    session.diff = loaded
    local n = #loaded.files
    local selected = session.state.selected
    if selected and (selected < 1 or selected > n) then
      session.state.selected = n > 0 and n or nil
    end
  end

  local function close_block(ctx, block_id)
    if not block_id or not rex.call then
      return
    end
    rex.call("block.close", {
      session_id = ctx and ctx.session_id,
      block_id = block_id,
      keep_last = true,
    })
  end

  local function close_current(ctx)
    if session.layer_id and rex.session.close_layer then
      rex.session.close_layer{ layer_id = session.layer_id }
    elseif session.block_ids then
      for i = 1, #session.block_ids do
        close_block(ctx, session.block_ids[i])
      end
    end
    close_block(ctx, session.block_id)
    session.layer_id = nil
    session.block_ids = nil
    session.block_id = nil
    session.floating = false
  end

  local hold_narrow

  local function label(block_id, text)
    if block_id and rex.session.set_block_label then
      rex.session.set_block_label{ block_id = block_id, label = text }
    end
  end

  local function place_narrow(ctx)
    local layout = view.render(session.diff, session.state, rex)
    local anchor = session.anchor_id
    if anchor == nil and ctx and ctx.block_id then
      anchor = ctx.block_id
    end
    local args = {
      direction = "horizontal",
      side = "after",
      ratio = view.NARROW_RATIO,
      layout = layout,
      focus = true,
    }
    if anchor ~= nil then
      args.anchor_id = anchor
    end
    local created, err = rex.session.new_split(args)
    if not created and args.anchor_id then
      args.anchor_id = nil
      created, err = rex.session.new_split(args)
    end
    if not created then
      return nil, err
    end
    if session.anchor_id == nil then
      session.anchor_id = created.anchor_id or (ctx and ctx.block_id)
    end
    session.block_id = created.block_ids and created.block_ids[1] or nil
    session.block_ids = nil
    session.layer_id = nil
    session.floating = false
    label(session.block_id, "git")
    hold_narrow(ctx)
    return created
  end

  local function place_float()
    local layout = view.render(session.diff, session.state, rex)
    local created, err = rex.session.new_layer{
      bounds = view.FLOAT_BOUNDS,
      layout = layout,
      focus = true,
    }
    if not created then
      return nil, err
    end
    session.layer_id = created.layer_id
    session.block_ids = created.block_ids
    session.block_id = nil
    session.floating = true
    if session.block_ids then
      label(session.block_ids[1], "git")
      label(session.block_ids[2], "git file")
    end
    return created
  end

  -- rex.exec.start returns without waiting. detach keeps the sleep alive
  -- after this action returns, which is when Mac Autobalance equalizes
  -- the new split. The sleep then asks the server to put the border back.
  hold_narrow = function(ctx)
    if not session.anchor_id or not session.block_id then
      return
    end
    local resize = {
      direction = "horizontal",
      before_block_id = session.anchor_id,
      after_block_id = session.block_id,
      ratio = view.NARROW_RATIO,
    }
    if rex.session.resize_pane then
      rex.session.resize_pane(resize)
    end
    local session_id = ctx and ctx.session_id
    local starter = type(rex.exec) == "table" and rex.exec.start or nil
    if not session_id or type(starter) ~= "function" then
      return
    end
    local code = string.format(
      "rex.session.resize_pane{ direction = %q, before_block_id = %q, after_block_id = %q, ratio = %s }",
      resize.direction,
      resize.before_block_id,
      resize.after_block_id,
      resize.ratio)
    starter({
      "/bin/sh", "-c",
      "sleep 3; exec rex do -s \"$1\" -e \"$2\"",
      "rexreview",
      session_id,
      code,
    }, { detach = true })
  end

  local function place(ctx)
    close_current(ctx)
    if session.state.expanded then
      return place_float()
    end
    return place_narrow(ctx)
  end

  local function focus_pane()
    if not rex.session.focus_block then
      return
    end
    local id = session.block_id
    if session.floating and session.block_ids then
      id = session.block_ids[1]
    end
    if id then
      rex.session.focus_block{ block_id = id }
    end
  end

  local function enter_mode(ctx)
    if session.mode or not from_client(ctx) then
      return
    end
    queue_mode(rex, "client.mode.enter", { name = "rexreview" })
    session.mode = true
  end

  local function exit_mode(ctx)
    if not session.mode then
      return
    end
    session.mode = false
    if from_client(ctx) then
      queue_mode(rex, "client.mode.exit")
    end
  end

  local function result()
    return {
      open = session.state.open,
      expanded = session.state.expanded,
      selected = session.state.selected,
      block_id = session.block_id,
      layer_id = session.layer_id,
    }
  end

  local function close(ctx)
    close_current(ctx)
    state_mod.close(session.state)
    exit_mode(ctx)
    return result()
  end

  local function open(ctx, args)
    ctx = ctx or {}
    args = args or {}
    if session.state.open then
      return close(ctx)
    end
    if session.anchor_id == nil and ctx.block_id then
      session.anchor_id = ctx.block_id
    end
    state_mod.open(session.state)
    load_diff(ctx, args)
    local placed, err = place(ctx)
    if not placed then
      session.state.open = false
      return nil, err
    end
    enter_mode(ctx)
    focus_pane()
    return result()
  end

  local function count()
    return #(session.diff.files or {})
  end

  local function click(ctx, index)
    if not session.state.open then
      return nil
    end
    local n = count()
    if index == nil then
      index = session.state.selected or (n > 0 and 1 or nil)
    end
    if index == nil or index < 1 or index > n then
      return nil, "no file"
    end
    state_mod.click(session.state, index)
    local placed, err = place(ctx)
    if not placed then
      return nil, err
    end
    return result()
  end

  local function escape(ctx)
    if session.state.expanded then
      state_mod.escape(session.state)
      local placed, err = place(ctx)
      if not placed then
        return nil, err
      end
      return result()
    end
    if session.state.open then
      return close(ctx)
    end
    return nil
  end

  local function select_delta(ctx, delta)
    if not session.state.open then
      return nil
    end
    local n = count()
    if n == 0 then
      return nil, "no file"
    end
    local index = (session.state.selected or 0) + (delta or 0)
    if index < 1 then
      index = 1
    end
    if index > n then
      index = n
    end
    state_mod.select(session.state, index)
    local placed, err = place(ctx)
    if not placed then
      return nil, err
    end
    return result()
  end

  local function owns(ctx)
    local id = ctx and ctx.block_id
    if type(id) ~= "string" then
      return false
    end
    if id == session.block_id then
      return true
    end
    local ids = session.block_ids
    if not ids then
      return false
    end
    for i = 1, #ids do
      if ids[i] == id then
        return true
      end
    end
    return false
  end

  return {
    open = open,
    close = close,
    click = click,
    escape = escape,
    select_delta = select_delta,
    owns = owns,
    state = session.state,
  }
end

return M
