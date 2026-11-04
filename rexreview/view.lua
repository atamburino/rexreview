local palette = require("rexreview.palette")

local M = {}

M.flavor = "com.superlogical.terminal.shell"
-- Clears the login banner Mac draws before the command starts.
M.clear = "\27[H\27[2J"
-- DECAWM off. Long lines clip at the pane edge instead of wrapping.
M.nowrap = palette.nowrap
-- Share of the split kept by the pane we open beside (the editor).
M.NARROW_RATIO = 0.78
-- Share of the expanded layer given to the file list.
M.LIST_RATIO = 0.32
-- Fractions of the window: x, y, width, height. Must sit inside it.
M.FLOAT_BOUNDS = { 0.08, 0.08, 0.84, 0.84 }

local LETTER = {
  modified = "M",
  added = "A",
  deleted = "D",
  renamed = "R",
  binary = "B",
}

local function paint(color, text)
  return color .. text .. palette.reset
end

local function paint_row(color, text)
  return color .. text .. palette.el .. palette.reset
end

local function gutter(n)
  if n == nil then
    return "    "
  end
  return string.format("%4d", n)
end

local function dim_gutter(n)
  return palette.dim .. gutter(n) .. palette.undim
end

local function diff_row(kind, old_line, new_line, text)
  local guts = dim_gutter(old_line) .. " " .. dim_gutter(new_line) .. " "
  local lead = ""
  local mark = " "
  if kind == "add" then
    lead = palette.add_bg .. palette.fg
    mark = palette.add_mark .. "+" .. palette.fg
  elseif kind == "delete" then
    lead = palette.delete_bg .. palette.fg
    mark = palette.delete_mark .. "-" .. palette.fg
  end
  return lead .. guts .. mark .. " " .. text .. palette.el .. palette.reset
end

local function letter_color(status)
  if status == "added" then
    return palette.add
  end
  if status == "deleted" then
    return palette.delete
  end
  if status == "binary" then
    return palette.binary
  end
  return palette.hunk
end

local function file_path(file)
  if file.status == "renamed" and file.old_path and file.new_path then
    return file.old_path .. " -> " .. file.new_path
  end
  local path = file.new_path or file.old_path or ""
  if file.status == "binary" then
    return path .. " binary"
  end
  return path
end

local function file_row(file, selected)
  local status = file.status or ""
  local letter = LETTER[status] or "?"
  local mark = selected and ">" or " "
  local path_color = selected and palette.selected or palette.context
  return paint(path_color, mark)
    .. " "
    .. paint(letter_color(status), letter)
    .. " "
    .. paint(path_color, file_path(file))
end

local function hunk_header(hunk)
  local text = string.format(
    "@@ -%d,%d +%d,%d @@",
    hunk.old_start or 0,
    hunk.old_count or 0,
    hunk.new_start or 0,
    hunk.new_count or 0)
  if hunk.header and hunk.header ~= "" then
    text = text .. " " .. hunk.header
  end
  return text
end

local function diff_screen(file)
  if not file then
    return paint(palette.context, "No file selected") .. "\n"
  end
  local rows = { paint(palette.selected, file_path(file)) }
  local hunks = file.hunks or {}
  if file.status == "binary" then
    rows[#rows + 1] = paint_row(palette.binary, "Binary file")
  elseif #hunks == 0 then
    if file.status == "renamed" then
      rows[#rows + 1] = paint_row(palette.hunk_row, "Renamed")
    else
      rows[#rows + 1] = paint_row(palette.fg, "No hunks")
    end
  else
    for i = 1, #hunks do
      local hunk = hunks[i]
      rows[#rows + 1] = paint_row(palette.hunk_row, hunk_header(hunk))
      local lines = hunk.lines or {}
      for j = 1, #lines do
        local line = lines[j]
        local kind = line.kind or "context"
        rows[#rows + 1] = diff_row(kind, line.old_line, line.new_line, line.text or "")
        if line.no_newline then
          rows[#rows + 1] = paint_row(palette.fg, "\\ No newline at end of file")
        end
      end
    end
  end
  return table.concat(rows, "\n") .. "\n"
end

function M.screens(diff, state)
  state = state or {}
  local files = (diff and diff.files) or {}
  local rows = {}
  if diff and type(diff.error) == "string" and diff.error ~= "" then
    rows[1] = paint(palette.delete, diff.error)
  elseif #files == 0 then
    rows[1] = paint(palette.context, "No changes")
  else
    for i = 1, #files do
      rows[#rows + 1] = file_row(files[i], state.selected == i)
    end
  end
  local body = nil
  if state.expanded then
    body = diff_screen(files[state.selected])
  end
  return {
    files = table.concat(rows, "\n") .. "\n",
    diff = body,
  }
end

local function block(rex, text)
  -- printf at the pane's real width, redrawn on WINCH. Autowrap stays off
  -- so a long line clips instead of spilling a tinted strip. The sleep is
  -- in this shell's process group; HUP/TERM kills it on the way out.
  local script = table.concat({
    "payload=$1",
    "draw() { printf '" .. M.nowrap .. M.clear .. "%s' \"$payload\"; }",
    "trap 'draw' WINCH",
    "trap 'kill \"$pid\" 2>/dev/null; exit' HUP TERM INT",
    "pid=",
    "draw",
    "while :; do sleep 86400 & pid=$!; wait \"$pid\" || kill \"$pid\" 2>/dev/null; done",
  }, "\n")
  return rex.layout.block{
    flavor = M.flavor,
    options = {
      shell = "none",
      command = {
        "/bin/sh", "-c", script,
        "sh",
        text,
      },
      exit = { on_completion = false },
    },
  }
end

function M.render(diff, state, rex)
  local screens = M.screens(diff, state)
  local list = block(rex, screens.files)
  if not state.expanded then
    return list
  end
  return rex.layout.horizontal(M.LIST_RATIO, list, block(rex, screens.diff))
end

return M
