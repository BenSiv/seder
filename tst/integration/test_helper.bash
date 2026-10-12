# Each test gets a scratch HOME and a PATH holding only stub package
# tools plus a curated set of real core utilities. A tool is "installed"
# exactly when the test creates its stub, so "npm missing" really means
# missing. Stubs append every invocation to $LOG instead of changing
# anything.

setup_env() {
    export ORIG_PATH="$PATH"
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export SEDER="$PROJECT_ROOT/bin/seder"
    export WORK="$BATS_TEST_DIRNAME/.tmp-$BATS_TEST_NUMBER"
    rm -rf "$WORK"
    mkdir -p "$WORK/home" "$WORK/stubs" "$WORK/sysbin" "$WORK/data/machines" "$WORK/data/bundles"
    export HOME="$WORK/home"
    export LOG="$WORK/log"
    : > "$LOG"
    for tool in sh bash cat grep mkdir rm ln mv test env printf head tail sed tr sort cut xargs stat touch hostname true false; do
        ln -s "$(command -v "$tool")" "$WORK/sysbin/$tool"
    done
    export PATH="$WORK/stubs:$WORK/sysbin"
    # Not root, so system changes go through the sudo stub.
    stub id 'echo 1000'
    stub sudo 'echo "sudo $*" >> "$LOG"; exec "$@"'
    stub dpkg-query 'cat "$WORK/installed" 2>/dev/null; true'
    stub apt-cache 'for n in "$@"; do [ "$n" = policy ] || printf "%s:\n  Installed: (none)\n  Candidate: 1.0\n" "$n"; done'
    stub apt-get 'echo "apt-get $*" >> "$LOG"'
    cd "$WORK/data"
}

teardown_env() {
    export PATH="$ORIG_PATH"
    rm -rf "$WORK"
}

stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$WORK/stubs/$1"
    PATH="$ORIG_PATH" chmod +x "$WORK/stubs/$1"
}

# installed_apt pkg... -> dpkg-query reports these as installed.
installed_apt() {
    for name in "$@"; do printf '%s\tii \n' "$name"; done >> "$WORK/installed"
}

# machine '"a", "b"' -> machines/test.lua using bundles a and b.
machine() {
    printf 'return {bundles = {%s}}\n' "$1" > machines/test.lua
}

# bundle name < lua -> bundles/name.lua
bundle() {
    cat > "bundles/$1.lua"
}

# A real tool in place of a stub, for tests that need its behaviour.
real() {
    ln -s "$(PATH="$ORIG_PATH" command -v "$1")" "$WORK/stubs/$1"
}

# git with a fixed identity, run with the full PATH (test setup only).
setup_git() {
    PATH="$ORIG_PATH" git -c user.name=test -c user.email=test@example.com "$@"
}
