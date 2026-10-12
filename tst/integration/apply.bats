load test_helper

setup() { setup_env; }
teardown() { teardown_env; }

@test "removing tools that are not installed is a no-op on a fresh machine" {
    machine '"cleanup"'
    bundle cleanup <<'LUA'
return {
    npm = {absent = {"@openai/codex"}},
    snap = {absent = {"code", "firefox"}},
    apt = {absent = {"nodejs", "npm"}},
    path = {absent = {"~/.codex"}},
    link = {absent = {"~/.config/Code/User/settings.json"}},
}
LUA
    run "$SEDER" check machines/test.lua -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"= @openai/codex  (npm not installed)"* ]]
    [[ "$output" == *"= code  (snap not installed)"* ]]
    [[ "$output" == *"0 to add, 0 to remove, 7 unchanged"* ]]
}

@test "apply on a fresh machine runs nothing for absent items" {
    machine '"cleanup"'
    bundle cleanup <<'LUA'
return {npm = {absent = {"@openai/codex"}}, apt = {absent = {"npm"}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to do."* ]]
    [ ! -s "$LOG" ]
}

@test "only installed packages are purged" {
    installed_apt firefox bash
    machine '"m"'
    bundle m <<'LUA'
return {apt = {absent = {"firefox", "thunderbird"}, present = {"bash", "jq"}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "apt-get -y purge firefox" "$LOG"
    ! grep -q thunderbird "$LOG"
    grep -qx "apt-get -y install jq" "$LOG"
    ! grep -q "install.*bash" "$LOG"
}

@test "npm packages are removed before npm itself" {
    installed_apt npm
    stub npm 'case "$1" in ls) echo /usr/lib/node_modules/@openai/codex;; prefix) echo /usr;; *) echo "npm $*" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {apt = {absent = {"npm"}}, npm = {absent = {"@openai/codex"}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    first=$(grep -m1 -E "npm uninstall|purge" "$LOG")
    [[ "$first" == *"npm uninstall -g @openai/codex"* ]]
}

@test "packages missing from the apt cache are flagged in the plan" {
    stub apt-cache 'true'
    machine '"m"'
    bundle m <<'LUA'
return {apt = {present = {"no-such-pkg"}}}
LUA
    run "$SEDER" plan machines/test.lua
    [[ "$output" == *"+ no-such-pkg  (not in the apt cache"* ]]
}

@test "snap waits for seeding before its first change" {
    stub snap 'case "$1" in list) printf "Name Version\nfirefox 1\n";; *) echo "snap $*" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {snap = {absent = {"firefox", "code"}, present = {{name = "zen", channel = "candidate"}}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    [ "$(grep '^snap' "$LOG" | head -1)" = "snap wait system seed.loaded" ]
    grep -qx "snap remove firefox" "$LOG"
    ! grep -q "remove code" "$LOG"
    grep -qx "snap install zen --channel=candidate" "$LOG"
}

@test "check exits 2 when the machine has drifted" {
    machine '"m"'
    bundle m <<'LUA'
return {path = {present = {"~/wanted"}}}
LUA
    run "$SEDER" check machines/test.lua
    [ "$status" -eq 2 ]
}
