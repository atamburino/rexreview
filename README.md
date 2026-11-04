# Rex Review

Rex Review is a native Lua plugin for [Rex](https://www.superlogical.com/rex), Mitchell Hashimoto's terminal multiplexer from Superlogical. It renders git diffs as a themed pane inside Rex.

Rex is in closed beta. The diff engine, the pane, and the key to open it are in this repository.

## Layers

### 1. Diff engine

A pure Lua 5.1 parser. Give it the text of a `git diff` and it returns files, then hunks, then lines. Parsing is a pure function of that text. The git invocation is a function the caller passes in: `rex.exec` inside Rex, a fixture in tests.

### 2. Pane rendering

`rexreview.view` turns a file list and the pane state into a layout tree. A narrow pane is one terminal block. An expanded pane is `rex.layout.horizontal` of the file list and that file's diff. Colors come from `rexreview/palette.lua`.

### 3. Interaction

`rexreview.state` tracks the open file and whether the pane is expanded. The Rex adapter opens the pane, selects a file, expands it into a floating layer, and collapses it again. Choosing another file rebuilds that layer so the new diff replaces the old one.

## Features

### 1. Diff pane

A persistent read-only diff pane, along the lines of the JetBrains Git tool window.

The file list starts narrow, beside the focused editor pane. Choosing a file loads that file's diff and expands the list into a floating layer. Escape, or choosing that same file again, collapses it. The binding is `shift+cmd+d` (Shift+Cmd+D).

Rex does not deliver mouse clicks to config Lua. The same transitions are bound to keys, and to the `rexreview_click` action for a caller that knows the file index. See [Diff pane](#diff-pane).

### 2. Branch versus main

The fast follow. Every file the branch has changed relative to main, shown as a file tree that uses the same renderer. `against_argv("main")` builds the git command for that view: `git diff main...HEAD`.

## How this differs

Rex Review shows the repository diff in a Rex pane.

- [rexdiff](https://github.com/rednafi/rexdiff) (rednafi) reviews the coding agent's last turn and pastes line comments into the agent's input.
- [rexdiff](https://github.com/segersniels/dotfiles/blob/master/.agents/skills/rexdiff/SKILL.md) (segersniels) reviews the current branch, uncommitted changes, or a GitHub pull request. Comments go back to the agent, or to GitHub when the pane is used outside Rex.
- [rex-sidecar](https://github.com/geminixiang/rex-sidecar) is a file explorer and preview. Entries show git status markers.
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) is a git diff viewer of the same kind, inside Neovim.

## Diff engine

```lua
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local rexreview = require("rexreview")
local diff, err = rexreview.load(rex.exec, { cwd = repo })
```

The runner has the same shape as [`rex.exec(argv[, opts])`](https://www.superlogical.com/rex/docs/reference/lua). In Rex, `rex.exec` is a callable table (`type(rex.exec)` is `"table"`, and `rex.exec.start` is the function), so `load` accepts a function or a table with a `__call` metamethod. Pass `rex.exec` itself.

It returns a result table (`ok`, `code`, `stdout`, `stderr`, `signal`, `timed_out`), or `nil` and an error string when the program never starts, such as `git: executable file not found in PATH`. On a normal exit, `timed_out` and `signal` are nil. On a timeout they are `timed_out = true` and `signal = "SIGTERM"`, with `ok = false` and `code = -1`. A non-zero exit is still a result table; `load` turns that into `nil` and one line of the stderr text. Git's `--no-index` usage, which is what `git diff` prints outside a repository, becomes `not a git repository`.

With no `argv`, `load` runs `git diff HEAD`, which is the staged and unstaged changes to tracked files. For the branch view:

```lua
rexreview.load(rex.exec, {
  cwd = repo,
  argv = rexreview.against_argv("main"),
})
```

`rexreview.parse(text)` skips git and parses text that is already a diff.

## Diff pane

Add the plugin to the Rex config file. That file is `$XDG_CONFIG_HOME/rex/init.lua`, or `~/.config/rex/init.lua` when `XDG_CONFIG_HOME` is unset.

```lua
package.path = "/path/to/rexreview/?.lua;" .. package.path
require("rexreview.plugin").register()
```

`rex config reload` picks it up. Shift+Cmd+D opens the pane to the right of the focused pane and keeps about a fifth of the width.

Rex's own keyboard example binds that same key to `pane.split` downward, and the Mac client uses it as Split Pane Down. Registering this plugin replaces that shortcut. Pass another key to keep both:

```lua
require("rexreview.plugin").register({ key = "alt+cmd+g" })
```

The pane runs `git diff HEAD` with an explicit `cwd`: the action's `cwd` argument, or the focused terminal's directory from `com.superlogical.terminal.pwd`. Without either, it shows `no working directory` and does not run git in Rex's own directory.

Up and Down move through the file list. Enter loads the highlighted file and expands the pane into a floating layer: the list on the left, the diff on the right. Enter on that same file collapses it. Escape collapses it too, and a second Escape gives the keys back to the terminal. The command palette lists the action as "Git Diff". An optional `cwd` argument is the repository to diff.

```sh
rex do rexreview_diff cwd=/path/to/repo
```

The list shows `M`, `A`, `D`, `R`, or `B`, the path, a rename as `old -> new`, and the word `binary` on a binary file. Added lines, removed lines, context, and hunk headers take their color from `rexreview/palette.lua`. Rex does not hand Lua the theme's hex values, so the palette names ANSI slots and the active terminal theme supplies the color.

`rexreview.view.render(diff, state, rex)` only needs the file list (`status`, paths, `hunks`). A later branch view can pass another list of that shape. This pane loads `git diff HEAD`.

```lua
{
  files = {
    {
      old_path = "src/old.txt", -- nil when that side is /dev/null
      new_path = "src/new.txt",
      status = "modified", -- modified, added, deleted, renamed, binary
      similarity = 75,     -- only when git printed a similarity index
      hunks = {
        {
          old_start = 1,
          old_count = 4,
          new_start = 1,
          new_count = 4,
          header = "function hello()", -- omitted when the hunk header has none
          lines = {
            {
              kind = "context", -- context, add, or delete
              text = "line",
              old_line = 1,     -- omitted on an added line
              new_line = 1,     -- omitted on a deleted line
              no_newline = true, -- set when git marked this line "\ No newline at end of file"
            },
          },
        },
      },
    },
  },
}
```

A binary file has status `binary` and an empty `hunks` list. An added or deleted binary still uses `binary`; the missing side is a nil path. A pure rename has status `renamed`, `similarity` 100, and no hunks. A rename that also changes the file stays `renamed` and carries the hunks.

Counts omitted in a hunk header (`@@ -1 +1 @@`) mean 1, which is git's rule.

## Tests

`scripts/generate_fixtures.sh` builds a temporary git repository and writes real `git diff` output into `tests/fixtures`. The set covers a modification, an add, a delete, a 100% rename, a rename with edits, a rename whose path contains spaces, binary add/modify/delete, `\ No newline at end of file` on one side and on both, a spaced path whose name itself contains ` b/`, a C-quoted path, and a hunk function header. Regenerate with that script. The files under `tests/fixtures` are that script's output.

```sh
./scripts/test.sh
```

That runs `tests/run.lua` under `lua5.1`, or LuaJIT if `lua5.1` is absent. No extra packages.

## Rex API

Checked against the [Lua API reference](https://www.superlogical.com/rex/docs/reference/lua):

- Rex runs Lua 5.1 with the standard library. `io.popen` and `os.execute` raise. Commands go through `rex.exec`.
- `rex.exec(argv[, opts])` waits for the command. On Rex Beta 0.1.0 it is a callable table, not a function. `argv` is a list of strings. The pane always passes `opts.cwd`. A normal result has `timed_out` and `signal` nil. A missing program is `nil` and an error string.
- `rex.layout.horizontal(ratio, a, b)`, `rex.layout.vertical(ratio, a, b)`, and `rex.layout.block{ flavor, options }` build layout tables. The pane uses `horizontal` and `block`.
- `rex.session.new_split` opens the narrow pane beside the focused block (`anchor_id`, `direction = "horizontal"`, `side = "after"`). `rex.session.new_layer` opens the expanded pane as a floating layer. `rex.session.close_layer` collapses it. Both results include `block_ids` in layout order.
- `rex.action` and `rex.bind("shift+cmd+d", ...)` register the command and the key. Modifier order and case do not matter. Escape is bound inside a `rexreview` key mode so it is not taken from every pane. Rex stores that key as `esc`.
- `rex.client.queue("client.mode.enter", { name = "rexreview" })` turns those keys on while the pane is open. With no graphical client connected, that call raises, and the pane still opens.

The events reference has no mouse-click event a config script can subscribe to. `rex.on` is for `rex do` scripts, and the where-each-function-works table marks it as a warning in the config file. File choice goes through `rexreview_click` and the keys above.

Each diff line is `printf` output. A terminal block's `initial_input` and `write` method type keystrokes, and Rex shows those escape sequences as text. `printf` output is styled with the terminal theme: green is palette slot 2, red is slot 1, cyan is slot 6. `set_theme` can replace those colors, and this pane does not call it.

These calls were read from the [Lua API reference](https://www.superlogical.com/rex/docs/reference/lua) and checked on a Linux Rex server, snapshot `0.0.1793741575-g1b6654`, with `rex api describe` and a short script. This machine has no Rex graphical client, so the pane was not screenshotted.
