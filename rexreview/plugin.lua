local pane = require("rexreview.pane")

local M = {}

local MODE = "rexreview"
-- Free of the Mac app defaults listed in the keyboard-shortcuts page and
-- the Mac Actions reference. shift+cmd+d is Split Pane Down.
local DEFAULT_KEY = "alt+cmd+g"

function M.register(rex, opts)
  if rex ~= nil and type(rex.action) ~= "function" then
    opts = rex
    rex = nil
  end
  rex = rex or _G.rex
  opts = opts or {}
  local key = opts.key
  if key == nil then
    key = DEFAULT_KEY
  end
  local ctl = pane.controller(rex)

  -- Not exclusive: an exclusive mode swallows every other key, and leaving
  -- it depends on the app accepting client.mode.exit.
  rex.mode(MODE, { exclusive = false })

  rex.action{
    name = "rexreview_diff",
    title = "Git Diff",
    description = "Open the git diff pane beside the focused pane.",
    category = "Git",
    args = { cwd = "string?" },
    run = function(ctx, args)
      return ctl.open(ctx, args)
    end,
  }

  rex.action{
    name = "rexreview_click",
    title = "Git Diff Select File",
    description = "Select a file and expand its diff. The same file again collapses it.",
    category = "Git",
    args = { index = "integer?" },
    run = function(ctx, args)
      return ctl.click(ctx, args and args.index)
    end,
  }

  rex.action{
    name = "rexreview_escape",
    title = "Git Diff Collapse",
    description = "Collapse the diff pane. Escape again closes it.",
    category = "Git",
    run = function(ctx)
      return ctl.escape(ctx)
    end,
  }

  rex.action{
    name = "rexreview_close",
    title = "Git Diff Close",
    description = "Close the git diff pane.",
    category = "Git",
    run = function(ctx)
      return ctl.close(ctx)
    end,
  }

  rex.action{
    name = "rexreview_select",
    title = "Git Diff Move",
    description = "Move the selection in the diff file list.",
    category = "Git",
    args = { delta = "integer?" },
    run = function(ctx, args)
      return ctl.select_delta(ctx, args and args.delta)
    end,
  }

  if key ~= "" then
    rex.bind(key, "rexreview_diff")
    rex.bind(MODE .. "/" .. key, "rexreview_diff")
  end
  rex.bind(MODE .. "/escape", "rexreview_escape")
  rex.bind(MODE .. "/enter", "rexreview_click")
  rex.bind(MODE .. "/up", "rexreview_select", { delta = -1 })
  rex.bind(MODE .. "/down", "rexreview_select", { delta = 1 })

  -- Used when the key mode never starts, which is what happens if Remote
  -- Control is off and client.mode.enter is rejected after run returns.
  local function gate(fn)
    return function(ctx)
      if not ctl.owns(ctx) then
        return false
      end
      if fn(ctx) == nil then
        return false
      end
      return true
    end
  end
  rex.bind("escape", gate(function(ctx) return ctl.escape(ctx) end))
  rex.bind("enter", gate(function(ctx) return ctl.click(ctx) end))
  rex.bind("up", gate(function(ctx) return ctl.select_delta(ctx, -1) end))
  rex.bind("down", gate(function(ctx) return ctl.select_delta(ctx, 1) end))

  return ctl
end

return M
