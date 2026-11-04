local git = require("rexreview.git")
local state_mod = require("rexreview.state")
local view = require("rexreview.view")

local M = {}

local TERMINAL = "com.superlogical.terminal"

local function pwd_path(rex, block_id)
  if not rex.block or not rex.block.call then
    return nil
  end
  local args = {}
  if block_id then
    args.block_id = block_id
  end
  local result = rex.block.call(TERMINAL, "pwd", args)
  if type(result) ~= "table" or type(result.pwd) ~= "string" or result.pwd == "" then
    return nil
  end
  local from_url = result.pwd:match("^file://[^/]*(/.*)$")
  if from_url then
    return from_url
  end
  if result.pwd:sub(1, 1) == "/" then
    return result.pwd
  end
  return nil
end

local function queue(rex, name, args)
  if not rex.client or not rex.client.queue then
    return
  end
  -- No graphical client is connected on a headless server, and queue raises.
  pcall(rex.client.queue, name, args)
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
  }

  local function load_diff(ctx, args)
    if args and type(args.cwd) == "string" and args.cwd ~= "" then
      session.cwd = args.cwd
    elseif session.cwd == nil then
      -- com.superlogical.terminal.pwd on the focused block. The method is
      -- in the Lua reference; the value is a file:// URL or a plain path.
      session.cwd = pwd_path(rex, ctx and ctx.block_id)
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

  local function enter_mode()
    queue(rex, "client.mode.enter", { name = "rexreview" })
  end

  local function exit_mode()
    queue(rex, "client.mode.exit")
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

  local function open(ctx, args)
    ctx = ctx or {}
    args = args or {}
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
    enter_mode()
    focus_pane()
    return result()
  end

  local function count()
    return #(session.diff.files or {})
  end

  local function click(ctx, index)
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
    exit_mode()
    return result()
  end

  local function select_delta(ctx, delta)
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

  return {
    open = open,
    click = click,
    escape = escape,
    select_delta = select_delta,
    state = session.state,
  }
end

return M
