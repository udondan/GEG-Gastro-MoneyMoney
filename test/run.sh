#!/bin/bash -e
# Run a Lua test script under luajit with the luarocks 5.1 module paths set up.
# Usage: test/run.sh [test/test_geg_gastro.lua]
export PATH="/opt/homebrew/bin:$PATH"
eval "$(luarocks --lua-version=5.1 path)"
cd "$(dirname "$0")/.."
exec luajit "${1:-test/test_geg_gastro.lua}" "${@:2}"
