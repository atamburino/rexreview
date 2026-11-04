-- Rex exposes no theme RGB values to Lua. These SGR sequences name ANSI
-- slots, and the active terminal theme supplies the color. Diff rows use
-- the theme's red and green as a background, with bright white text on top.
return {
  add = "\27[32m",
  delete = "\27[31m",
  context = "\27[39m",
  hunk = "\27[36m",
  selected = "\27[1m",
  binary = "\27[33m",
  reset = "\27[0m",
  el = "\27[K",
  add_row = "\27[42m\27[97m",
  delete_row = "\27[41m\27[97m",
  context_row = "\27[39m",
  hunk_row = "\27[36m",
}
