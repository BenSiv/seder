load test_helper

setup() { setup_env; mkdir -p managers; }
teardown() { teardown_env; }

# manager name < lua -> managers/name.lua
manager() {
    cat > "managers/$1.lua"
}

@test "a described package manager installs missing packages and removes installed ones" {
    stub zypper 'echo "zypper $*" >> "$LOG"'
    stub rpm 'printf "bash\nfirefox\n"'
    manager zypper <<'LUA'
return {
    list = "rpm -qa --qf '%{NAME}\\n'",
    install = "zypper install",
    remove = "zypper remove",
    refresh = "zypper refresh",
}
LUA
    machine '"m"'
    bundle m <<'LUA'
return {zypper = {present = {"bash", "jq", "git"}, absent = {"firefox", "thunderbird"}}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "sudo zypper remove firefox" "$LOG"
    [ "$(grep -m1 -n 'zypper refresh' "$LOG" | cut -d: -f1)" -lt "$(grep -m1 -n 'zypper install' "$LOG" | cut -d: -f1)" ]
    grep -qx "zypper install jq git" "$LOG"
    ! grep -q "bash\|thunderbird" "$LOG"
}

@test "a manager whose tool is missing treats absent packages as done" {
    manager apk <<'LUA'
return {list = "apk info", install = "apk add", remove = "apk del"}
LUA
    machine '"m"'
    bundle m <<'LUA'
return {apk = {absent = {"firefox"}, present = {"jq"}}}
LUA
    run "$SEDER" plan machines/test.lua -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"= firefox  (apk not installed)"* ]]
    [[ "$output" == *"+ jq  (apk not installed; not checked)"* ]]
}

@test "a user-level manager runs without sudo, one package at a time, after its slot" {
    installed_apt pipx
    stub pipx 'case "$1" in list) echo "black 24.1.0";; *) echo "pipx $*" >> "$LOG";; esac'
    manager pipx <<'LUA'
return {
    list = "pipx list --short",
    install = "pipx install",
    remove = "pipx uninstall",
    sudo = false,
    one_at_a_time = true,
    after = "npm",
}
LUA
    machine '"m"'
    bundle m <<'LUA'
return {
    pipx = {present = {"black", "httpie", "ruff"}},
    apt = {present = {"pipx", "jq"}},
}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "pipx install httpie" "$LOG"
    grep -qx "pipx install ruff" "$LOG"
    ! grep -q "sudo pipx" "$LOG"
    ! grep -q "install black" "$LOG"
    [ "$(grep -n 'apt-get' "$LOG" | tail -1 | cut -d: -f1)" -lt "$(grep -m1 -n 'pipx install' "$LOG" | cut -d: -f1)" ]
}

@test "manager descriptions are checked before anything runs" {
    machine '"m"'
    bundle m <<'LUA'
return {zypper = {present = {"jq"}}}
LUA
    manager zypper <<'LUA'
return {list = "rpm -qa", install = "zypper install"}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"managers/zypper.lua: missing required key 'remove'"* ]]
    manager zypper <<'LUA'
return {list = "rpm -qa", install = "zypper install", remove = "zypper remove", after = "zypper"}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"'after' must name a built-in provider"* ]]
    manager zypper <<'LUA'
return {list = "rpm -qa", install = "zypper install", remove = "zypper remove", sudo = "yes"}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"'sudo' must be a boolean"* ]]
    [ ! -s "$LOG" ]
}

@test "an unknown provider points at managers/" {
    machine '"m"'
    bundle m <<'LUA'
return {xbps = {present = {"jq"}}}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown provider 'xbps'"* ]]
    [[ "$output" == *"managers/xbps.lua"* ]]
}

@test "without a machine file, machines/<uname -n>.lua is used" {
    bundle m <<'LUA'
return {path = {present = {"~/made"}}}
LUA
    printf 'return {bundles = {"m"}}\n' > "machines/$(uname -n).lua"
    run "$SEDER" plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"+ $HOME/made"* ]]
}

@test "the example configurations load" {
    for machine_file in "$PROJECT_ROOT"/examples/machines/*.lua; do
        run "$SEDER" plan "$machine_file"
        [ "$status" -eq 0 ]
    done
}
