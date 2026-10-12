#!/usr/bin/env bash
set -euo pipefail

# Plans (or applies) a data directory against a fresh container of any
# distribution.
#
#   dev/fresh.sh <image> <data-dir> <machine.lua> [plan -v | apply -y ...]
#
# The data directory is mounted read-only at /data; apply changes only
# the throwaway container.

cd "$(dirname "$0")/.."

IMAGE=$1
DATA_DIR=$(cd "$2" && pwd)
MACHINE=$3
shift 3
COMMAND=("$@")
if [ "${#COMMAND[@]}" -eq 0 ]; then
    COMMAND=(plan -v)
fi

TAG="seder-fresh-$(printf '%s' "$IMAGE" | tr -c 'a-z0-9' '-')"
podman build --build-arg "BASE=$IMAGE" -f dev/Containerfile -t "$TAG" .
podman run --rm -it -v "$DATA_DIR:/data:ro" "$TAG" "${COMMAND[0]}" "$MACHINE" "${COMMAND[@]:1}"
