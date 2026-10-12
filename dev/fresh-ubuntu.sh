#!/usr/bin/env bash
set -euo pipefail

# Plans (or applies) a data directory against a fresh Ubuntu container.
#
#   dev/fresh-ubuntu.sh <data-dir> <machine.lua> [plan|apply -y]
#
# The data directory is mounted read-only at /data; apply changes only
# the throwaway container.

cd "$(dirname "$0")/.."

DATA_DIR=$(cd "$1" && pwd)
MACHINE=$2
shift 2
COMMAND=("$@")
if [ "${#COMMAND[@]}" -eq 0 ]; then
    COMMAND=(plan -v)
fi

podman build -f dev/Containerfile -t seder-fresh-ubuntu .
podman run --rm -it -v "$DATA_DIR:/data:ro" seder-fresh-ubuntu "${COMMAND[0]}" "$MACHINE" "${COMMAND[@]:1}"
