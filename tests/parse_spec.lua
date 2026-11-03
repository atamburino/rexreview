local rexreview = require("rexreview")

local function line(kind, text, old_line, new_line, no_newline)
  local entry = { kind = kind, text = text }
  if old_line ~= nil then entry.old_line = old_line end
  if new_line ~= nil then entry.new_line = new_line end
  if no_newline then entry.no_newline = true end
  return entry
end

local function hunk(old_start, old_count, new_start, new_count, lines, header)
  local h = {
    old_start = old_start,
    old_count = old_count,
    new_start = new_start,
    new_count = new_count,
    lines = lines,
  }
  if header ~= nil then h.header = header end
  return h
end

local function file(old_path, new_path, status, hunks, similarity)
  local f = {
    old_path = old_path,
    new_path = new_path,
    status = status,
    hunks = hunks,
  }
  if similarity ~= nil then f.similarity = similarity end
  return f
end

local function parsed(name)
  local diff, err = rexreview.parse(read_file(name))
  if not diff then
    error(err)
  end
  return diff
end

local fixtures = {
  "added.diff",
  "binary.diff",
  "binary_deleted.diff",
  "binary_new.diff",
  "deleted.diff",
  "empty.diff",
  "escaped_path.diff",
  "function.diff",
  "modified.diff",
  "no_newline.diff",
  "no_newline_both.diff",
  "rename.diff",
  "rename_edit.diff",
  "rename_space.diff",
  "space_ambiguous.diff",
  "space_path.diff",
}

local function assert_well_formed(diff)
  check(type(diff.files) == "table")
  for _, f in ipairs(diff.files) do
    check(
      f.status == "modified" or f.status == "added" or f.status == "deleted"
        or f.status == "renamed" or f.status == "binary",
      "status " .. tostring(f.status))
    check(type(f.hunks) == "table")
    if f.status == "added" then
      check(f.old_path == nil and type(f.new_path) == "string")
    elseif f.status == "deleted" then
      check(f.new_path == nil and type(f.old_path) == "string")
    elseif f.status == "renamed" then
      check(type(f.old_path) == "string" and type(f.new_path) == "string")
      check(f.old_path ~= f.new_path)
      check(type(f.similarity) == "number")
    elseif f.status == "binary" then
      eq(#f.hunks, 0)
      check(f.old_path ~= nil or f.new_path ~= nil)
    end
    for _, h in ipairs(f.hunks) do
      local old_line = h.old_start
      local new_line = h.new_start
      local old_n, new_n = 0, 0
      for _, ln in ipairs(h.lines) do
        check(ln.kind == "context" or ln.kind == "add" or ln.kind == "delete")
        check(type(ln.text) == "string")
        if ln.kind == "add" then
          check(ln.old_line == nil)
        else
          eq(ln.old_line, old_line)
          old_line = old_line + 1
          old_n = old_n + 1
        end
        if ln.kind == "delete" then
          check(ln.new_line == nil)
        else
          eq(ln.new_line, new_line)
          new_line = new_line + 1
          new_n = new_n + 1
        end
      end
      eq(old_n, h.old_count)
      eq(new_n, h.new_count)
    end
  end
end

test("every fixture is well formed", function()
  for i = 1, #fixtures do
    assert_well_formed(parsed(fixtures[i]))
  end
end)

test("empty diff", function()
  same(parsed("empty.diff"), { files = {} })
end)

test("modified file has two hunks", function()
  same(parsed("modified.diff"), {
    files = {
      file("src/app.txt", "src/app.txt", "modified", {
        hunk(1, 4, 1, 4, {
          line("delete", "1 alpha", 1, nil),
          line("add", "1 ALPHA", nil, 1),
          line("context", "2 beta", 2, 2),
          line("context", "3 gamma", 3, 3),
          line("context", "4 delta", 4, 4),
        }),
        hunk(8, 3, 8, 4, {
          line("context", "8 theta", 8, 8),
          line("context", "9 iota", 9, 9),
          line("context", "10 kappa", 10, 10),
          line("add", "11 extra", nil, 11),
        }),
      }),
    },
  })
end)

test("added file", function()
  same(parsed("added.diff"), {
    files = {
      file(nil, "src/fresh.txt", "added", {
        hunk(0, 0, 1, 2, {
          line("add", "fresh", nil, 1),
          line("add", "line", nil, 2),
        }),
      }),
    },
  })
end)

test("deleted file", function()
  same(parsed("deleted.diff"), {
    files = {
      file("src/gone.txt", nil, "deleted", {
        hunk(1, 1, 0, 0, {
          line("delete", "keep", 1, nil),
        }),
      }),
    },
  })
end)

test("pure rename", function()
  same(parsed("rename.diff"), {
    files = {
      file("src/move.txt", "src/moved.txt", "renamed", {}, 100),
    },
  })
end)

test("rename with edits", function()
  same(parsed("rename_edit.diff"), {
    files = {
      file("src/edit_move.txt", "src/relocated.txt", "renamed", {
        hunk(1, 5, 1, 5, {
          line("context", "one", 1, 1),
          line("context", "two", 2, 2),
          line("delete", "three", 3, nil),
          line("add", "THREE", nil, 3),
          line("context", "four", 4, 4),
          line("context", "five", 5, 5),
        }),
      }, 75),
    },
  })
end)

test("rename of a path with spaces", function()
  same(parsed("rename_space.diff"), {
    files = {
      file("old name.txt", "new name.txt", "renamed", {}, 100),
    },
  })
end)

test("modified binary", function()
  same(parsed("binary.diff"), {
    files = {
      file("assets/pic.bin", "assets/pic.bin", "binary", {}),
    },
  })
end)

test("added binary", function()
  same(parsed("binary_new.diff"), {
    files = {
      file(nil, "assets/new.bin", "binary", {}),
    },
  })
end)

test("deleted binary", function()
  same(parsed("binary_deleted.diff"), {
    files = {
      file("assets/pic.bin", nil, "binary", {}),
    },
  })
end)

test("no newline marker attaches to the new line", function()
  same(parsed("no_newline.diff"), {
    files = {
      file("src/nonew.txt", "src/nonew.txt", "modified", {
        hunk(1, 1, 1, 1, {
          line("delete", "plain", 1, nil),
          line("add", "plain", nil, 1, true),
        }),
      }),
    },
  })
end)

test("no newline marker attaches to both sides", function()
  same(parsed("no_newline_both.diff"), {
    files = {
      file("src/nonew.txt", "src/nonew.txt", "modified", {
        hunk(1, 1, 1, 1, {
          line("delete", "plain", 1, nil, true),
          line("add", "plain!", nil, 1, true),
        }),
      }),
    },
  })
end)

test("path with spaces, including a b/ separator", function()
  same(parsed("space_path.diff"), {
    files = {
      file("src/my file.txt", "src/my file.txt", "modified", {
        hunk(1, 1, 1, 2, {
          line("context", "hello", 1, 1),
          line("add", "world", nil, 2),
        }),
      }),
    },
  })
  same(parsed("space_ambiguous.diff"), {
    files = {
      file("foo b/bar.txt", "foo b/bar.txt", "modified", {
        hunk(1, 1, 1, 1, {
          line("delete", "a", 1, nil),
          line("add", "b", nil, 1),
        }),
      }),
    },
  })
end)

test("quoted octal path", function()
  local path = "src/caf\195\169.txt"
  same(parsed("escaped_path.diff"), {
    files = {
      file(path, path, "modified", {
        hunk(1, 1, 1, 1, {
          line("delete", "alpha", 1, nil),
          line("add", "beta", nil, 1),
        }),
      }),
    },
  })
end)

test("hunk header keeps the function context", function()
  same(parsed("function.diff"), {
    files = {
      file("src/widget.lua", "src/widget.lua", "modified", {
        hunk(3, 5, 3, 5, {
          line("context", "\tb", 3, 3),
          line("context", "\tc", 4, 4),
          line("context", "\td", 5, 5),
          line("delete", "\treturn 1", 6, nil),
          line("add", "\treturn 2", nil, 6),
          line("context", "end", 7, 7),
        }, "function hello()"),
      }),
    },
  })
end)

test("several files in one diff stay in order", function()
  local text = read_file("rename.diff") .. read_file("binary.diff") .. read_file("added.diff")
  local diff = rexreview.parse(text)
  eq(#diff.files, 3)
  eq(diff.files[1].status, "renamed")
  eq(diff.files[1].new_path, "src/moved.txt")
  eq(diff.files[2].status, "binary")
  eq(diff.files[2].new_path, "assets/pic.bin")
  eq(diff.files[3].status, "added")
  eq(diff.files[3].new_path, "src/fresh.txt")
  assert_well_formed(diff)
end)

test("a diff whose text has no trailing newline still parses", function()
  local text = read_file("modified.diff")
  check(text:sub(-1) == "\n")
  same(rexreview.parse(text:sub(1, -2)), rexreview.parse(text))
end)

test("a binary patch does not swallow the next file", function()
  local text = table.concat({
    "diff --git a/a.bin b/a.bin",
    "index 111..222 100644",
    "GIT binary patch",
    "literal 4",
    "abcd",
    "diff --git a/b.txt b/b.txt",
    "index 333..444 100644",
    "--- a/b.txt",
    "+++ b/b.txt",
    "@@ -1 +1 @@",
    "-a",
    "+b",
    "",
  }, "\n")
  same(rexreview.parse(text), {
    files = {
      file("a.bin", "a.bin", "binary", {}),
      file("b.txt", "b.txt", "modified", {
        hunk(1, 1, 1, 1, {
          line("delete", "a", 1, nil),
          line("add", "b", nil, 1),
        }),
      }),
    },
  })
end)

test("parse rejects a non-string", function()
  local diff, err = rexreview.parse(nil)
  eq(diff, nil)
  eq(err, "diff text must be a string")
end)
