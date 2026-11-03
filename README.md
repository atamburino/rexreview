# Rex Review

Rex Review is a native Lua plugin for [Rex](https://www.superlogical.com/rex), Mitchell Hashimoto's terminal multiplexer from Superlogical. It renders git diffs as a themed pane inside Rex.

Rex is in closed beta. This repository currently contains the diff engine. The pane and the interaction sit on top of it.

## Layers

### 1. Diff engine

A pure Lua 5.1 parser. Give it the text of a `git diff` and it returns files, then hunks, then lines. Parsing is a pure function of that text. The git invocation is a function the caller passes in: `rex.exec` inside Rex, a fixture in tests.

### 2. Pane rendering

The diff is drawn in a Rex pane built with `rex.layout.horizontal`, `rex.layout.vertical`, and `rex.layout.block`, and styled to the Superlogical palette.

### 3. Interaction

Move to the next file or hunk, toggle views, and refresh the pane in place so the update does not flicker.

## Features

### 1. Diff pane

A persistent read-only diff pane, along the lines of the JetBrains Git tool window.

The file list starts narrow, beside the focused editor pane. Clicking a file loads that file's diff and expands the list into a floating pane. Escape, or a second click on the same file, collapses it again. The suggested binding is `shift+cmd+d` (Shift+Cmd+D).

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

The runner has the same shape as [`rex.exec(argv[, opts])`](https://www.superlogical.com/rex/docs/reference/lua). It returns a result table (`ok`, `code`, `stdout`, `stderr`, `signal`, `timed_out`), or `nil` and an error string when the program never starts. A non-zero exit is still a result table from `rex.exec`; `load` turns that into `nil` and the stderr text. Pass `rex.exec` itself.

With no `argv`, `load` runs `git diff HEAD`, which is the staged and unstaged changes to tracked files. For the branch view:

```lua
rexreview.load(rex.exec, {
  cwd = repo,
  argv = rexreview.against_argv("main"),
})
```

`rexreview.parse(text)` skips git and parses text that is already a diff.

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
- `rex.exec(argv[, opts])` waits for the command. `argv` is a list of strings. `opts.cwd` and `opts.env` are the options this engine passes. The result fields used here are `ok`, `code`, `stdout`, `stderr`, and `timed_out`.
- `rex.layout.horizontal(ratio, a, b)`, `rex.layout.vertical(ratio, a, b)`, and `rex.layout.block{ flavor, options }` build layout tables. Layer 2 will use them.
- `rex.bind("shift+cmd+d", ...)` is the documented spelling of Shift+Cmd+D. Modifier order and case do not matter.

Rex itself is not installed in this environment, so these calls were read from the docs and are not executed here.
