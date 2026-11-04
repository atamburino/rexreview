local rexreview = require("rexreview")
local palette = require("rexreview.palette")
local view = require("rexreview.view")

local function layout_rex()
  return {
    layout = {
      block = function(spec)
        return { block = { flavor = spec.flavor, options = spec.options } }
      end,
      horizontal = function(ratio, a, b)
        return {
          split = {
            direction = "horizontal",
            ratio = ratio,
            before = a,
            after = b,
          },
        }
      end,
      vertical = function(ratio, a, b)
        return {
          split = {
            direction = "vertical",
            ratio = ratio,
            before = a,
            after = b,
          },
        }
      end,
    },
  }
end

local function parsed(name)
  local diff, err = rexreview.parse(read_file(name))
  if not diff then
    error(err)
  end
  return diff
end

local function collapsed(diff, selected)
  return { open = true, selected = selected, expanded = false }
end

local function expanded(diff, selected)
  return { open = true, selected = selected, expanded = true }
end

local function input_of(node)
  local options = node.block.options
  local script = options.command[3]
  eq(options.command[1], "/bin/sh")
  eq(options.command[2], "-c")
  eq(options.command[4], "sh")
  eq(options.shell, "none")
  eq(options.exit.on_completion, false)
  check(script:find(view.nowrap, 1, true) ~= nil, "autowrap off")
  check(script:find(view.clear, 1, true) ~= nil, "clear")
  check(script:find("payload=$1", 1, true) ~= nil, "text stays positional")
  check(script:find("trap 'draw' WINCH", 1, true) ~= nil, "WINCH redraw")
  check(script:find("sleep 86400", 1, true) ~= nil)
  check(script:find("kill \"$pid\"", 1, true) ~= nil)
  return options.command[5]
end

test("narrow render lists a rename, a binary file, and a modification", function()
  local rex = layout_rex()
  local rename = view.render(parsed("rename.diff"), collapsed(nil, nil), rex)
  eq(rename.block.flavor, view.flavor)
  eq(rename.split, nil)
  local text = input_of(rename)
  check(text:find("R", 1, true) ~= nil)
  check(text:find("src/move.txt -> src/moved.txt", 1, true) ~= nil)
  check(text:find("@@", 1, true) == nil)

  local binary = view.screens(parsed("binary.diff"), collapsed(nil, nil))
  check(binary.files:find("B", 1, true) ~= nil)
  check(binary.files:find("assets/pic.bin binary", 1, true) ~= nil)
  check(binary.files:find(palette.binary, 1, true) ~= nil)
  eq(binary.diff, nil)

  local modified = view.screens(parsed("modified.diff"), collapsed(nil, 1))
  check(modified.files:find("M", 1, true) ~= nil)
  check(modified.files:find("src/app.txt", 1, true) ~= nil)
  check(modified.files:find(">", 1, true) ~= nil)
  eq(modified.diff, nil)
end)

test("expanded render colors added, removed, context, and hunk lines", function()
  local diff = parsed("modified.diff")
  local screens = view.screens(diff, expanded(nil, 1))
  local text = screens.diff
  local function gut(n)
    local cell = n == nil and "    " or string.format("%4d", n)
    return palette.dim .. cell .. palette.undim
  end
  local delete_row = palette.delete_bg .. palette.fg
    .. gut(1) .. " " .. gut(nil) .. " "
    .. palette.delete_mark .. "-" .. palette.fg
    .. " 1 alpha" .. palette.el .. palette.reset
  local add_row = palette.add_bg .. palette.fg
    .. gut(nil) .. " " .. gut(1) .. " "
    .. palette.add_mark .. "+" .. palette.fg
    .. " 1 ALPHA" .. palette.el .. palette.reset
  local context_row = gut(2) .. " " .. gut(2) .. "   2 beta"
    .. palette.el .. palette.reset
  local hunk_row = palette.hunk_row .. "@@ -1,4 +1,4 @@"
    .. palette.el .. palette.reset
  local later_add = palette.add_bg .. palette.fg
    .. gut(nil) .. " " .. gut(11) .. " "
    .. palette.add_mark .. "+" .. palette.fg
    .. " 11 extra" .. palette.el .. palette.reset
  local later_context = gut(8) .. " " .. gut(8) .. "   8 theta"
    .. palette.el .. palette.reset
  check(text:find(delete_row, 1, true) ~= nil, "delete row")
  check(text:find(add_row, 1, true) ~= nil, "add row")
  check(text:find(context_row, 1, true) ~= nil, "context row")
  check(text:find(hunk_row, 1, true) ~= nil, "hunk row")
  check(text:find(later_add, 1, true) ~= nil, "later add gutter")
  check(text:find(later_context, 1, true) ~= nil, "second hunk gutter")
  eq(palette.delete_bg, "\27[48;5;52m")
  eq(palette.add_bg, "\27[48;5;22m")
  eq(palette.fg, "\27[39m")
  eq(palette.delete_mark, "\27[31m")
  eq(palette.add_mark, "\27[32m")
  eq(palette.dim, "\27[2m")
  eq(palette.hunk_row, "\27[36m")
  eq(palette.el, "\27[K")
  eq(palette.nowrap, "\27[?7l")
  check(text:find("\27[97m", 1, true) == nil, "no bright white")

  local rex = layout_rex()
  local tree = view.render(diff, expanded(nil, 1), rex)
  eq(tree.split.direction, "horizontal")
  eq(tree.split.ratio, view.LIST_RATIO)
  eq(input_of(tree.split.before), screens.files)
  eq(input_of(tree.split.after), screens.diff)
end)

test("no-newline fixture keeps the marker on the colored line", function()
  local text = view.screens(parsed("no_newline.diff"), expanded(nil, 1)).diff
  check(text:find(palette.delete_bg .. palette.fg .. palette.dim .. "   1" .. palette.undim, 1, true) ~= nil)
  check(text:find(palette.delete_mark .. "-" .. palette.fg .. " plain", 1, true) ~= nil)
  check(text:find(palette.add_mark .. "+" .. palette.fg .. " plain", 1, true) ~= nil)
  check(text:find(palette.fg .. "\\ No newline at end of file" .. palette.el, 1, true) ~= nil)
end)

test("a pure rename and a binary file have no hunk body", function()
  local rename = view.screens(parsed("rename.diff"), expanded(nil, 1)).diff
  check(rename:find("src/move.txt -> src/moved.txt", 1, true) ~= nil)
  check(rename:find(palette.hunk_row .. "Renamed" .. palette.el, 1, true) ~= nil)
  check(rename:find("+", 1, true) == nil)

  local binary = view.screens(parsed("binary.diff"), expanded(nil, 1)).diff
  check(binary:find(palette.binary .. "Binary file" .. palette.el, 1, true) ~= nil)
  check(binary:find("@@", 1, true) == nil)
end)

test("the renderer takes a file list and does not care where it came from", function()
  local diff = {
    files = {
      {
        status = "added",
        new_path = "tree/leaf.txt",
        hunks = {
          {
            old_start = 0,
            old_count = 0,
            new_start = 1,
            new_count = 1,
            lines = { { kind = "add", text = "leaf", new_line = 1 } },
          },
        },
      },
    },
  }
  local text = view.screens(diff, expanded(nil, 1)).diff
  check(text:find("tree/leaf.txt", 1, true) ~= nil)
  check(text:find(palette.add_mark .. "+" .. palette.fg .. " leaf" .. palette.el, 1, true) ~= nil)
end)

test("selecting a file shows only that file's diff", function()
  local diff = rexreview.parse(read_file("modified.diff") .. read_file("added.diff"))
  eq(#diff.files, 2)
  local second = view.screens(diff, expanded(nil, 2)).diff
  check(second:find(palette.add_mark .. "+" .. palette.fg .. " fresh" .. palette.el, 1, true) ~= nil)
  check(second:find("1 ALPHA", 1, true) == nil)
  local list = view.screens(diff, collapsed(nil, 2)).files
  check(list:find("src/fresh.txt", 1, true) ~= nil)
  check(list:find("A", 1, true) ~= nil)
end)

test("an empty diff and a load error still render a list", function()
  local empty = view.screens({ files = {} }, collapsed(nil, nil))
  check(empty.files:find("No changes", 1, true) ~= nil)
  local failed = view.screens({ files = {}, error = "fatal: not a git repository" }, collapsed(nil, nil))
  check(failed.files:find(palette.delete .. "fatal: not a git repository", 1, true) ~= nil)
end)
