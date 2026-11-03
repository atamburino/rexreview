#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

if command -v lua5.1 >/dev/null 2>&1; then
  exec lua5.1 tests/run.lua
fi
if command -v luajit >/dev/null 2>&1; then
  exec luajit tests/run.lua
fi

echo "lua5.1 or luajit is required" >&2
exit 1
