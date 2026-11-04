local M = {}

function M.initial()
  return {
    open = false,
    selected = nil,
    expanded = false,
  }
end

function M.open(state)
  state.open = true
  return state
end

function M.select(state, index)
  state.selected = index
  return state
end

function M.expand(state)
  state.open = true
  state.expanded = true
  return state
end

function M.collapse(state)
  state.expanded = false
  return state
end

function M.escape(state)
  if state.expanded then
    state.expanded = false
  end
  return state
end

-- Click selects that file and expands. A second click on the same file
-- collapses. A click on a different file stays expanded and selects it.
function M.click(state, index)
  if state.expanded and state.selected == index then
    state.expanded = false
  else
    state.selected = index
    state.expanded = true
    state.open = true
  end
  return state
end

return M
