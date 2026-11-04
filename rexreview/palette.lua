-- Rex exposes no theme tokens to Lua. These SGR sequences name ANSI slots,
-- and the active terminal theme supplies the color.
return {
  add = "\27[32m",
  delete = "\27[31m",
  context = "\27[39m",
  hunk = "\27[36m",
  selected = "\27[1m",
  binary = "\27[33m",
  reset = "\27[0m",
}
