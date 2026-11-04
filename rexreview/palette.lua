-- Rex exposes no palette RGB, so row tints are fixed 256-color indexes
-- (52 dim red, 22 dim green). The -/+ markers use strong ANSI red and green.
-- Gutters are dim. Text on a tinted row stays the default foreground.
return {
  add = "\27[32m",
  delete = "\27[31m",
  context = "\27[39m",
  hunk = "\27[36m",
  selected = "\27[1m",
  binary = "\27[33m",
  reset = "\27[0m",
  el = "\27[K",
  fg = "\27[39m",
  dim = "\27[2m",
  undim = "\27[22m",
  add_bg = "\27[48;5;22m",
  delete_bg = "\27[48;5;52m",
  add_mark = "\27[32m",
  delete_mark = "\27[31m",
  hunk_row = "\27[36m",
  nowrap = "\27[?7l",
}
