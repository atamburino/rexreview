local pane = require("rexreview.pane")

local M = {}

local MODE = "rexreview"
local DEFAULT_KEY = "shift+cmd+d"

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

  rex.mode(MODE, { exclusive = true })

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
    description = "Collapse the diff pane. Escape again leaves the diff keys.",
    category = "Git",
    run = function(ctx)
      return ctl.escape(ctx)
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

  return ctl
end

return M
