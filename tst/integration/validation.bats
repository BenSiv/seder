load test_helper

setup() { setup_env; }
teardown() { teardown_env; }

expect_error() {
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"$1"* ]]
    [ ! -s "$LOG" ]
}

@test "a misspelled field is rejected before anything runs" {
    machine '"m"'
    bundle m <<'LUA'
return {snap = {present = {{name = "x", clasic = true}}}}
LUA
    expect_error "unknown field 'clasic'"
}

@test "a misspelled state is rejected" {
    machine '"m"'
    bundle m <<'LUA'
return {apt = {presnet = {"jq"}}}
LUA
    expect_error "unknown key 'presnet'"
}

@test "the same thing wanted present and absent is an error naming both" {
    machine '"a", "b"'
    bundle a <<'LUA'
return {apt = {present = {"gimp"}}}
LUA
    bundle b <<'LUA'
return {apt = {absent = {"gimp"}}}
LUA
    expect_error "wants gimp absent, but ./bundles/a.lua"
}

@test "run items must say how to tell they are done" {
    machine '"m"'
    bundle m <<'LUA'
return {run = {present = {{name = "x", cmd = "true"}}}}
LUA
    expect_error "needs 'creates' or 'unless'"
}

@test "path removal refuses shallow paths and home" {
    machine '"m"'
    bundle m <<'LUA'
return {path = {absent = {"/usr"}}}
LUA
    expect_error "refusing a path this close to /"
    bundle m <<'LUA'
return {path = {absent = {"~"}}}
LUA
    expect_error "refusing the home directory"
}

@test "unknown variables are rejected" {
    machine '"m"'
    bundle m <<'LUA'
return {path = {present = {"${nope}/x"}}}
LUA
    expect_error 'unknown variable ${nope}'
}

@test "bundle files are data: no os or io" {
    machine '"m"'
    bundle m <<'LUA'
os.execute("touch /tmp/should-not-exist")
return {}
LUA
    expect_error "attempt to index"
}

@test "machine vars expand inside bundles, including ~ and other vars" {
    cat > machines/test.lua <<'LUA'
return {vars = {projects = "~/P", configs = "${projects}/configs"}, bundles = {"m"}}
LUA
    bundle m <<'LUA'
return {path = {present = {"${configs}"}}}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 0 ]
    [[ "$output" == *"+ $HOME/P/configs"* ]]
}

@test "built-in vars: home, user and uid" {
    stub id 'echo 4242'
    machine '"m"'
    bundle m <<'LUA'
return {path = {present = {"~/run/${uid}/${user}"}}}
LUA
    USER=ben run "$SEDER" plan machines/test.lua
    [ "$status" -eq 0 ]
    [[ "$output" == *"+ $HOME/run/4242/ben"* ]]
}
