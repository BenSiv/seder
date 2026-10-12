load test_helper

# An "upstream" bare repo and a checkout of it at ~/p/proj, with
# src/a.lua committed. The checkout can be pushed past by commit_upstream.
setup() {
    setup_env
    real git
    setup_git init -q --bare -b main "$WORK/upstream.git"
    setup_git clone -q "$WORK/upstream.git" "$WORK/seed" 2>/dev/null
    mkdir -p "$WORK/seed/src"
    echo 'print(1)' > "$WORK/seed/src/a.lua"
    setup_git -C "$WORK/seed" add -A
    setup_git -C "$WORK/seed" commit -qm one
    setup_git -C "$WORK/seed" push -q origin HEAD:main
    mkdir -p "$HOME/p"
    setup_git clone -q "$WORK/upstream.git" "$HOME/p/proj"
}
teardown() { teardown_env; }

commit_upstream() {
    echo "$1" >> "$WORK/seed/src/a.lua"
    setup_git -C "$WORK/seed" commit -qam "$1"
    setup_git -C "$WORK/seed" push -q origin HEAD:main
}

build_bundle() {
    machine '"m"'
    bundle m <<LUA
return {
    repo = {present = {{path = "~/p/proj", url = "$WORK/upstream.git"}}},
    run = {present = {{name = "build proj", dir = "~/p/proj",
        cmd = "mkdir -p bin && cat src/a.lua > bin/out",
        creates = "~/p/proj/bin/out", sources = {"~/p/proj/src"}}}},
}
LUA
}

@test "a build is stale when a tracked source is newer than its output" {
    build_bundle
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    run "$SEDER" check machines/test.lua
    [ "$status" -eq 0 ]
    touch -d '+1 minute' "$HOME/p/proj/src/a.lua"
    run "$SEDER" plan machines/test.lua
    [[ "$output" == *"+ build proj  ($HOME/p/proj/src/a.lua is newer than the build)"* ]]
}

@test "untracked files under sources do not make a build stale" {
    build_bundle
    run "$SEDER" apply machines/test.lua -y
    touch -d '+1 minute' "$HOME/p/proj/src/scratch.tmp"
    run "$SEDER" check machines/test.lua
    [ "$status" -eq 0 ]
}

@test "without --pull, a checkout behind upstream is left as it is" {
    build_bundle
    run "$SEDER" apply machines/test.lua -y
    commit_upstream two
    run "$SEDER" check machines/test.lua
    [ "$status" -eq 0 ]
}

@test "--pull fast-forwards a clean checkout and rebuilds what it feeds" {
    build_bundle
    run "$SEDER" apply machines/test.lua -y
    commit_upstream two
    run "$SEDER" plan machines/test.lua --pull
    [[ "$output" == *"+ $HOME/p/proj  (1 commits behind origin/main; fast-forward)"* ]]
    [[ "$output" == *"+ build proj  ($HOME/p/proj is being updated)"* ]]
    run "$SEDER" apply machines/test.lua -y --pull
    [ "$status" -eq 0 ]
    grep -qx two "$HOME/p/proj/bin/out"
    run "$SEDER" check machines/test.lua --pull
    [ "$status" -eq 0 ]
}

@test "--pull leaves a checkout with local changes alone and says why" {
    build_bundle
    run "$SEDER" apply machines/test.lua -y
    commit_upstream two
    echo local >> "$HOME/p/proj/src/a.lua"
    touch -d '-1 hour' "$HOME/p/proj/src/a.lua"
    run "$SEDER" plan machines/test.lua --pull -v
    [[ "$output" == *"= $HOME/p/proj  (1 behind origin/main, local changes; not updated)"* ]]
    run "$SEDER" check machines/test.lua --pull
    [ "$status" -eq 0 ]
}

@test "sources need creates" {
    machine '"m"'
    bundle m <<'LUA'
return {run = {present = {{name = "x", cmd = "true", unless = "true", sources = {"~/src"}}}}}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"'sources' needs 'creates'"* ]]
}
