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

@test "dconf writes only keys that differ and compares numbers as numbers" {
    stub dconf 'case "$1" in
dump) printf "[org/gnome/desktop/interface]\ncolor-scheme='"'"'default'"'"'\n\n[org/test]\nbrightness=0.59999999999999998\nold=1\n";;
*) echo "dconf $*" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {dconf = {
    present = {
        {key = "/org/gnome/desktop/interface/color-scheme", value = "'prefer-dark'"},
        {key = "/org/test/brightness", value = "0.6"},
        {key = "/org/test/new", value = "@as []"},
    },
    absent = {"/org/test/old", "/org/test/never-set"},
}}
LUA
    run "$SEDER" plan machines/test.lua
    [[ "$output" == *"+ /org/gnome/desktop/interface/color-scheme  (now 'default')"* ]]
    DBUS_SESSION_BUS_ADDRESS=unix:path=/test run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "dconf write /org/gnome/desktop/interface/color-scheme 'prefer-dark'" "$LOG"
    grep -qx "dconf write /org/test/new @as \[\]" "$LOG"
    grep -qx "dconf reset /org/test/old" "$LOG"
    ! grep -q "brightness\|never-set" "$LOG"
}

@test "dconf keys must be full key paths" {
    machine '"m"'
    bundle m <<'LUA'
return {dconf = {absent = {"/org/gnome/"}}}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"key must be a full key path"* ]]
}

@test "dconf finds the session bus when the environment lacks it" {
    stub dconf 'case "$1" in dump) ;; *) echo "dconf $* bus=$DBUS_SESSION_BUS_ADDRESS" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {dconf = {present = {{key = "/org/a", value = "true"}}}}
LUA
    mkdir -p "$WORK/run" && : > "$WORK/run/bus"
    DBUS_SESSION_BUS_ADDRESS= XDG_RUNTIME_DIR="$WORK/run" run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "dconf write /org/a true bus=unix:path=$WORK/run/bus" "$LOG"
}

@test "dconf without a session bus fails with a clear message" {
    stub dconf 'case "$1" in dump) ;; *) echo "dconf $*" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {dconf = {present = {{key = "/org/a", value = "true"}}}}
LUA
    DBUS_SESSION_BUS_ADDRESS= XDG_RUNTIME_DIR="$WORK/nowhere" run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"no desktop session bus at $WORK/nowhere/bus"* ]]
    [ ! -s "$LOG" ]
}

@test "flatpak adds a missing remote, installs missing apps, removes installed ones" {
    stub flatpak 'case "$1" in
list) printf "Application\norg.old.App\norg.have.App\n";;
*) echo "flatpak $*" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {flatpak = {
    present = {
        {name = "org.have.App", remote = "flathub"},
        {name = "org.new.App", remote = "flathub", remote_url = "https://dl.flathub.org/repo/flathub.flatpakrepo"},
    },
    absent = {"org.old.App", "org.never.App"},
}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "flatpak uninstall -y --noninteractive org.old.App" "$LOG"
    grep -qx "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" "$LOG"
    grep -qx "flatpak install -y --noninteractive flathub org.new.App" "$LOG"
    ! grep -q "org.have.App\|org.never.App" "$LOG"
    [ "$(grep -n '^flatpak remote-add' "$LOG" | cut -d: -f1)" -lt "$(grep -n '^flatpak install' "$LOG" | cut -d: -f1)" ]
}

@test "flatpak items need a remote" {
    machine '"m"'
    bundle m <<'LUA'
return {flatpak = {present = {"org.new.App"}}}
LUA
    run "$SEDER" plan machines/test.lua
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required field 'remote'"* ]]
}

@test "dnf installs missing packages and URLs, removes installed ones" {
    stub rpm 'printf "bash\nfirefox\n"'
    stub dnf 'echo "dnf $*" >> "$LOG"'
    machine '"m"'
    bundle m <<'LUA'
return {dnf = {
    present = {"bash", "jq", {name = "quarto", url = "https://example.com/quarto.rpm"}},
    absent = {"firefox", "thunderbird"},
}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "dnf remove -y firefox" "$LOG"
    grep -qx "dnf install -y jq https://example.com/quarto.rpm" "$LOG"
    ! grep -q "bash\|thunderbird" "$LOG"
}

@test "pacman installs from repos and files, removes with dependencies" {
    stub pacman 'case "$1" in -Qq) printf "bash\nfirefox\n";; *) echo "pacman $*" >> "$LOG";; esac'
    machine '"m"'
    bundle m <<'LUA'
return {pacman = {
    present = {"bash", "jq", {name = "quarto", url = "https://example.com/quarto.pkg.tar.zst"}},
    absent = {"firefox", "thunderbird"},
}}
LUA
    run "$SEDER" apply machines/test.lua -y
    [ "$status" -eq 0 ]
    grep -qx "pacman -Rns --noconfirm firefox" "$LOG"
    grep -qx "pacman -S --needed --noconfirm jq" "$LOG"
    grep -qx "pacman -U --noconfirm https://example.com/quarto.pkg.tar.zst" "$LOG"
    ! grep -q "thunderbird" "$LOG"
}
