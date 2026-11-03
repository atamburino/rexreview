local M = {}

local function split_lines(text)
  local lines = {}
  local pos = 1
  local n = #text
  while pos <= n do
    local nl = text:find("\n", pos, true)
    if not nl then
      lines[#lines + 1] = text:sub(pos):gsub("\r$", "")
      break
    end
    local line = text:sub(pos, nl - 1)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    lines[#lines + 1] = line
    pos = nl + 1
  end
  return lines
end

local function unquote(token)
  local out = {}
  local i = 2
  local n = #token
  while i <= n do
    local c = token:sub(i, i)
    if c == '"' then
      break
    end
    if c ~= "\\" or i == n then
      out[#out + 1] = c
      i = i + 1
    else
      local e = token:sub(i + 1, i + 1)
      if e == "n" then
        out[#out + 1] = "\n"
        i = i + 2
      elseif e == "t" then
        out[#out + 1] = "\t"
        i = i + 2
      elseif e == "r" then
        out[#out + 1] = "\r"
        i = i + 2
      elseif e == "\\" then
        out[#out + 1] = "\\"
        i = i + 2
      elseif e == '"' then
        out[#out + 1] = '"'
        i = i + 2
      elseif e == "a" then
        out[#out + 1] = "\a"
        i = i + 2
      elseif e == "b" then
        out[#out + 1] = "\b"
        i = i + 2
      elseif e == "v" then
        out[#out + 1] = "\v"
        i = i + 2
      elseif e == "f" then
        out[#out + 1] = "\f"
        i = i + 2
      elseif e:match("[0-7]") then
        local oct = token:match("^([0-7][0-7]?[0-7]?)", i + 1)
        out[#out + 1] = string.char(tonumber(oct, 8))
        i = i + 1 + #oct
      else
        out[#out + 1] = e
        i = i + 2
      end
    end
  end
  return table.concat(out)
end

local function read_quoted(s, i)
  local j = i + 1
  while j <= #s do
    local c = s:sub(j, j)
    if c == "\\" then
      j = j + 2
    elseif c == '"' then
      return s:sub(i, j), j + 1
    else
      j = j + 1
    end
  end
  return s:sub(i), #s + 1
end

local function skip_space(s, i)
  while s:sub(i, i) == " " or s:sub(i, i) == "\t" do
    i = i + 1
  end
  return i
end

local function strip_prefix(path, prefix)
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return nil
end

-- Paths that differ (a rename) are left nil; rename from/to and ---/+++
-- carry those names. Identical paths are recovered by finding the split
-- where a/<path> and b/<path> are the same string, which is how git apply
-- reads an unquoted "diff --git" line.
local function parse_diff_git(line)
  local rest = line:match("^diff %-%-git (.+)$")
  if not rest then
    return nil, nil
  end
  if rest:sub(1, 1) == '"' then
    local a_tok, j = read_quoted(rest, 1)
    j = skip_space(rest, j)
    local b_tok = read_quoted(rest, j)
    return strip_prefix(unquote(a_tok), "a/"), strip_prefix(unquote(b_tok), "b/")
  end

  local n = #rest
  local i = 1
  while i <= n do
    local c = rest:sub(i, i)
    if c == " " or c == "\t" then
      local left = rest:sub(1, i - 1)
      local right = rest:sub(i + 1)
      local a = strip_prefix(left, "a/")
      local b = strip_prefix(right, "b/")
      if a and b and a == b then
        return a, b
      end
    end
    i = i + 1
  end
  return nil, nil
end

local function parse_rename_path(rest)
  if rest:sub(1, 1) == '"' then
    return unquote(rest)
  end
  return rest
end

local function parse_ab_path(spec, prefix)
  if spec:sub(1, 1) == '"' then
    spec = unquote(spec)
  else
    local tab = spec:find("\t", 1, true)
    if tab then
      spec = spec:sub(1, tab - 1)
    end
  end
  if spec == "/dev/null" then
    return nil
  end
  local stripped = strip_prefix(spec, prefix)
  if stripped then
    return stripped
  end
  return spec
end

local function parse_hunk_header(line)
  local old_s, old_c, new_s, new_c, rest =
    line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@(.*)$")
  if not old_s then
    return nil
  end
  local header = rest:gsub("^ +", "")
  if header == "" then
    header = nil
  end
  return {
    old_start = tonumber(old_s),
    old_count = old_c == "" and 1 or tonumber(old_c),
    new_start = tonumber(new_s),
    new_count = new_c == "" and 1 or tonumber(new_c),
    header = header,
    lines = {},
  }
end

local function parse_hunk(lines, i)
  local hunk = parse_hunk_header(lines[i])
  if not hunk then
    return nil, i + 1
  end
  i = i + 1
  local old_line = hunk.old_start
  local new_line = hunk.new_start
  local n = #lines
  while i <= n do
    local line = lines[i]
    if line:match("^diff %-%-git ") or line:match("^@@ ") then
      break
    end
    local prefix = line:sub(1, 1)
    if prefix == "\\" then
      local prev = hunk.lines[#hunk.lines]
      if prev then
        prev.no_newline = true
      end
    elseif prefix == " " or prefix == "+" or prefix == "-" then
      local kind = prefix == " " and "context" or (prefix == "+" and "add" or "delete")
      local entry = {
        kind = kind,
        text = line:sub(2),
      }
      if kind == "context" or kind == "delete" then
        entry.old_line = old_line
        old_line = old_line + 1
      end
      if kind == "context" or kind == "add" then
        entry.new_line = new_line
        new_line = new_line + 1
      end
      hunk.lines[#hunk.lines + 1] = entry
    else
      break
    end
    i = i + 1
  end
  return hunk, i
end

local function finish_file(state)
  local status
  if state.binary then
    status = "binary"
  elseif state.renamed then
    status = "renamed"
  elseif state.old_path == nil and state.new_path ~= nil then
    status = "added"
  elseif state.new_path == nil and state.old_path ~= nil then
    status = "deleted"
  else
    status = "modified"
  end
  local file = {
    old_path = state.old_path,
    new_path = state.new_path,
    status = status,
    hunks = state.hunks,
  }
  if state.similarity ~= nil then
    file.similarity = state.similarity
  end
  return file
end

local function parse_file(lines, i)
  local old_path, new_path = parse_diff_git(lines[i])
  local state = {
    old_path = old_path,
    new_path = new_path,
    hunks = {},
    binary = false,
    renamed = false,
    similarity = nil,
  }
  i = i + 1
  local n = #lines
  while i <= n do
    local line = lines[i]
    if line:match("^diff %-%-git ") then
      break
    end
    if line:match("^@@ ") then
      local hunk, next_i = parse_hunk(lines, i)
      if hunk then
        state.hunks[#state.hunks + 1] = hunk
      end
      i = next_i
    elseif line == "GIT binary patch" or line:match("^Binary files ") then
      state.binary = true
      if line:match("^Binary files /dev/null and ") then
        state.old_path = nil
      elseif line:match(" and /dev/null differ$") then
        state.new_path = nil
      end
      i = i + 1
      if line == "GIT binary patch" then
        while i <= n and not lines[i]:match("^diff %-%-git ") do
          i = i + 1
        end
      end
    else
      local rename_from = line:match("^rename from (.+)$")
      local rename_to = line:match("^rename to (.+)$")
      local similarity = line:match("^similarity index (%d+)%%$")
      local minus = line:match("^%-%-%- (.+)$")
      local plus = line:match("^%+%+%+ (.+)$")
      if line:match("^new file mode %d+$") then
        state.old_path = nil
      elseif line:match("^deleted file mode %d+$") then
        state.new_path = nil
      elseif rename_from then
        state.renamed = true
        state.old_path = parse_rename_path(rename_from)
      elseif rename_to then
        state.renamed = true
        state.new_path = parse_rename_path(rename_to)
      elseif similarity then
        state.similarity = tonumber(similarity)
      elseif minus then
        state.old_path = parse_ab_path(minus, "a/")
      elseif plus then
        state.new_path = parse_ab_path(plus, "b/")
      end
      i = i + 1
    end
  end
  return finish_file(state), i
end

function M.parse(text)
  if type(text) ~= "string" then
    return nil, "diff text must be a string"
  end
  local lines = split_lines(text)
  local files = {}
  local i = 1
  local n = #lines
  while i <= n do
    if lines[i]:match("^diff %-%-git ") then
      local file, next_i = parse_file(lines, i)
      files[#files + 1] = file
      i = next_i
    else
      i = i + 1
    end
  end
  return { files = files }
end

return M
