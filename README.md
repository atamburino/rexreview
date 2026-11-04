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

The file list starts narrow, beside the focused editor pane. Choosing a file loads that file's diff and expands the list into a floating layer. Escape, or choosing that same file again, collapses it. A second Escape closes the pane. The binding is `alt+cmd+g` (Alt+Cmd+G).

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

`?/init.lua` has to be on `package.path`. The module entry is `rexreview/init.lua`, which that pattern finds. `?.lua` alone does not.

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
package.path = "/path/to/rexreview/?.lua;"
  .. "/path/to/rexreview/?/init.lua;"
  .. package.path
require("rexreview.plugin").register()
```

`?/init.lua` is required next to `?.lua`. `require("rexreview")` loads `rexreview/init.lua`, and `require("rexreview.plugin")` loads `rexreview/plugin.lua`.

`rex config reload` picks it up. Alt+Cmd+G opens the pane to the right of the focused pane. The editor keeps about four fifths of that split. Pressing the key again closes the pane.

Shift+Cmd+D is the Mac app's built-in Split Pane Down (`pane.split` downward). The [keyboard shortcuts](https://www.superlogical.com/rex/docs/customize/keyboard-shortcuts) page uses that key in its example, and `rex keymap` does not list client defaults, so the clash is easy to miss. The default here is Alt+Cmd+G. That combo is not among the shortcuts on the keyboard-shortcuts page, and it is not a default in the [Mac Actions](https://www.superlogical.com/rex/docs/reference/mac-actions) list (`cmd+g` is Find Next, `shift+cmd+g` is Find Previous and Go to Directory). Pass another key if you want one:

```lua
require("rexreview.plugin").register({ key = "ctrl+alt+g" })
```

The pane runs `git diff HEAD` with an explicit `cwd`. It uses the action's `cwd` argument, then `com.superlogical.terminal.pwd` on the focused block, then that block's `process` result at `foreground.cwd`. Both calls pass `block_id`. Without a directory it shows `no working directory` and does not run git in Rex's own directory.

Up and Down move through the file list. Enter loads the highlighted file and expands the pane into a floating layer: the list on the left, the diff on the right. Enter on that same file collapses it. Escape collapses an expanded pane and leaves the diff keys. A second Escape closes the pane. The command palette lists the action as "Git Diff". An optional `cwd` argument is the repository to diff.

Up, Down, Enter, and Escape are bound on their own, and they act only when the focused block is the diff list or the expanded diff. A key in any other pane is left for that pane, including while the diff is open. They also do nothing while the diff is closed. The same keys are bound in a `rexreview` key mode that is not exclusive. The mode is entered on a key or palette press and left only when the pane closes. Turn on Remote Control in Rex Settings, under Rex Server, so the app accepts `client.mode.enter`. If it is off, the plain bindings above still work on the diff blocks.

Mac Autobalance (Settings > Interface > Splits & Focus) evens out panes about two seconds after one is created. There is no per-split opt-out, and config Lua has no call that returns the server binary. `REX_BIN_DIR` is set in terminals Rex opens, not in the server process, whose `PATH` is only `/usr/bin:/bin:/usr/sbin:/sbin`. A detached `rex.exec.start` sleeps three seconds, then runs the server's own executable (`ps` on the shell's parent, then `command -v rex`, then the Mac app path) to call `session.resize_pane`. Closing the pane signals that shell's process group (`h.pid` from `rex.exec.start`). The resize itself checks that both blocks still exist. Turn Autobalance off if the later resize is not enough.

The block label is `git`. The Mac pane title is the terminal title. `com.superlogical.terminal.title` only reads it, and no layout field sets it.

Mac starts the command through `/usr/bin/login`, which prints a login banner. The shell turns autowrap off, clears the screen, and draws the diff. A `WINCH` trap draws it again after the pane is resized, so erase-to-end-of-line fills the real width. Long lines clip at the pane edge instead of wrapping. The shell sleeps in its own process group and kills that sleep on `HUP` or `TERM`, which is how the block closes.

```sh
rex do rexreview_diff cwd=/path/to/repo
```

The list shows `M`, `A`, `D`, `R`, or `B`, the path, a rename as `old -> new`, and the word `binary` on a binary file. A diff row has dim old and new line-number gutters and a `+` or `-` marker in strong ANSI green or red. Removed rows sit on 256-color 52 and added rows on 256-color 22, with the default foreground, erased to the end of the line. Context stays the normal foreground. Hunk headers use the cyan accent. Rex does not hand Lua the theme's RGB values, so those two backgrounds are fixed indexes, not a tint derived from the theme.

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
- `rex.action` and `rex.bind("alt+cmd+g", ...)` register the command and the key. Modifier order and case do not matter. `shift+cmd+d` is left for the Mac app's Split Pane Down.
- `ctx.origin` is `key`, `palette`, `cli`, `api`, or `script`. `rex.client.queue("client.mode.enter", { name = "rexreview" })` runs only for `key` and `palette`. A queued client action is delivered after `run` returns, so a failure there is not visible to the action. Remote Control has to be on for the app to accept it. The mode is not exclusive.
- `rex.exec.start` does not wait. Its handle's `pid` is the command's process id. `detach = true` lets the sleep outlive the action, and closing the pane runs `/bin/kill -TERM` on that process group because `h:kill` does not stop a detached command. The server `PATH` has no `rex`, and Lua has no call for the server binary, so the shell uses its parent executable, then `command -v rex`, then the Mac app path. `resize_pane` runs only if both blocks still exist.

The events reference has no mouse-click event a config script can subscribe to. `rex.on` is for `rex do` scripts, and the where-each-function-works table marks it as a warning in the config file. File choice goes through `rexreview_click` and the keys above.

Each diff line is `printf` output. A terminal block's `initial_input` and `write` method type keystrokes, and Rex shows those escape sequences as text. `printf` output is styled with the terminal theme: green is palette slot 2, red is slot 1, cyan is slot 6. `set_theme` can replace those colors, and this pane does not call it.

These calls were read from the [Lua API reference](https://www.superlogical.com/rex/docs/reference/lua) and checked on a Linux Rex server, snapshot `0.0.1793741575-g1b6654`, with `rex api describe` and a short script. This machine has no Rex graphical client, so the pane was not screenshotted.
