load test_helper

setup() { setup_env; }
teardown() { teardown_env; }

@test "a link replaces an existing file, keeps it as .orig, and is idempotent" {
    echo original > "$HOME/.bashrc"
    echo managed > "$WORK/bashrc.sh"
    machine '"m"'
    bundle m <<LUA
return {link = {present = {{path = "~/.bashrc", target = "$WORK/bashrc.sh"}}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/.bashrc")" = managed ]
    [ "$(cat "$HOME/.bashrc.orig")" = original ]
    run "$SEDER" check machines/test.lua
    [ "$status" -eq 0 ]
}

@test "absent links remove symlinks but leave real files" {
    ln -s /etc/hostname "$HOME/link"
    echo keep > "$HOME/real"
    machine '"m"'
    bundle m <<'LUA'
return {link = {absent = {"~/link", "~/real"}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/link" ]
    [ "$(cat "$HOME/real")" = keep ]
}

@test "paths are created and removed, home paths without sudo" {
    mkdir -p "$HOME/.codex/sub"
    machine '"m"'
    bundle m <<'LUA'
return {path = {present = {"~/a/b"}, absent = {"~/.codex"}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [ -d "$HOME/a/b" ]
    [ ! -e "$HOME/.codex" ]
    ! grep -q sudo "$LOG"
}

@test "run items with creates run once" {
    machine '"m"'
    bundle m <<'LUA'
return {run = {present = {{name = "build", cmd = "echo built > out", dir = "~", creates = "~/out"}}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [ "$(cat "$HOME/out")" = built ]
    run "$SEDER" check machines/test.lua
    [ "$status" -eq 0 ]
}

@test "a run that does not produce what it promised fails" {
    machine '"m"'
    bundle m <<'LUA'
return {run = {present = {{name = "noop", cmd = "true", creates = "~/never"}}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"was not created"* ]]
}

@test "repos clone only when missing" {
    stub git 'echo "git $*" >> "$LOG"; mkdir -p "$4/.git"'
    mkdir -p "$HOME/p/have/.git"
    machine '"m"'
    bundle m <<'LUA'
return {repo = {present = {
    {path = "~/p/have", url = "https://example.com/have.git"},
    {path = "~/p/new", url = "https://example.com/new.git"},
}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [ "$(grep -c '^git clone' "$LOG")" -eq 1 ]
    grep -q "new.git" "$LOG"
}
