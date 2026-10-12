#!/usr/bin/env bash
set -euo pipefail

# Static build through luam's shared orchestrator, like brain-ex/daat:
# one self-contained bin/seder, no luam install needed to run it.

cd "$(dirname "$0")/.."

if [ -z "${LUAM_DIR:-}" ]; then
    LUAM_DIR=$(cd ../luam 2>/dev/null && pwd || true)
fi

if [ -z "$LUAM_DIR" ] || [ ! -f "$LUAM_DIR/obj/liblua.a" ]; then
    echo "Error: no built luam checkout found. Set LUAM_DIR to one (obj/liblua.a present)." >&2
    exit 1
fi

exec "$LUAM_DIR/bin/luam" "$LUAM_DIR/lib/static/build.lua" \
    --entry main.lua \
    --bin seder \
    --with lfs \
    --luamdir "$LUAM_DIR" \
    "$@"
