-- Running commands. Probes capture output and exit status; actions
-- stream to the terminal. Every command the engine runs goes through
-- here, so tests only need stub binaries on PATH.

shell = {}

function shell.quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- Runs `cmd` and returns its combined stdout+stderr and whether it
-- exited 0. io.popen's close gives no exit status in luam, so the
-- status is echoed as a marker on the last line and stripped again.
function shell.capture(cmd)
    handle = io.popen("{ " .. cmd .. "\n} 2>&1; echo \"__rc=$?\"")
    out = io.read(handle, "*a")
    io.close(handle)
    rc = string.match(out, "__rc=(%d+)%s*$")
    out = string.gsub(out, "__rc=%d+%s*$", "")
    return out, rc == "0"
end

function shell.ok(cmd)
    _, ok = shell.capture(cmd)
    return ok
end

function shell.has(bin)
    return shell.ok("command -v " .. shell.quote(bin))
end

function shell.lines(text)
    result = {}
    for line in string.gmatch(text, "[^\n]+") do
        table.insert(result, line)
    end
    return result
end

-- Runs `cmd` with its output going straight to the terminal.
function shell.run(cmd)
    print("    $ " .. cmd)
    status = os.execute(cmd)
    return status == 0 or status == true
end

-- Runs `fn(item)` for each item, stopping at the first failure.
function shell.each(items, fn)
    for _, item in ipairs(items) do
        if fn(item) != true then
            return false
        end
    end
    return true
end

IS_ROOT = nil

function shell.is_root()
    if IS_ROOT == nil then
        out, _ = shell.capture("id -u")
        IS_ROOT = string.match(out, "^%s*0%s*$") != nil
    end
    return IS_ROOT
end

-- Prefixes `cmd` with sudo unless already root. The engine itself runs
-- as the normal user; only system changes go through sudo.
function shell.sudo(cmd)
    if shell.is_root() then
        return cmd
    end
    return "sudo " .. cmd
end

function shell.home()
    return os.getenv("HOME")
end

-- True when `path` is inside the user's home, where no sudo is needed.
function shell.in_home(path)
    home = shell.home()
    return string.sub(path, 1, string.len(home) + 1) == home .. "/"
end

-- sudo for paths outside the home directory, plain for paths inside it.
function shell.for_path(path, cmd)
    if shell.in_home(path) then
        return cmd
    end
    return shell.sudo(cmd)
end

function shell.parent(path)
    parent = string.match(path, "^(.*)/[^/]+/?$")
    if parent == nil then
        return "."
    end
    if parent == "" then
        return "/"
    end
    return parent
end

return shell
