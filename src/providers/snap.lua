-- Snap packages. On a fresh Ubuntu install snapd is still seeding for a
-- while after first boot and snap commands block until it is done, so
-- the first change waits for seeding explicitly instead of hanging
-- mid-install.

shell = require("shell")

snap = {
    key = "name",
    fields = {name = "string", classic = "boolean", channel = "string"},
    required = {present = {"name"}, absent = {"name"}},
    states = {"present", "absent"},
}

LISTING = nil
SEEDED = false

function snap.available()
    if shell.has("snap") == false then
        return false, "snap not installed"
    end
    out, ok = shell.capture("snap list")
    if ok != true and string.find(out, "No snaps", 1, true) == nil then
        return false, "snapd not responding"
    end
    LISTING = out
    return true
end

-- name -> true for every installed snap (first column, header skipped).
function snap.state(entries)
    installed = {}
    for index, line in ipairs(shell.lines(LISTING)) do
        name = string.match(line, "^(%S+)")
        if index > 1 and name != nil then
            installed[name] = true
        end
    end
    return installed
end

function snap.status(item, current)
    if current[item.name] == true then
        return "present"
    end
    return "absent"
end

function wait_seeded()
    if SEEDED == false then
        if shell.run(shell.sudo("snap wait system seed.loaded")) != true then
            return false
        end
        SEEDED = true
    end
    return true
end

function install(item)
    cmd = "snap install " .. shell.quote(item.name)
    if item.classic == true then
        cmd = cmd .. " --classic"
    end
    if item.channel != nil then
        cmd = cmd .. " --channel=" .. shell.quote(item.channel)
    end
    return shell.run(shell.sudo(cmd))
end

function uninstall(item)
    return shell.run(shell.sudo("snap remove " .. shell.quote(item.name)))
end

function snap.add(items)
    return wait_seeded() and shell.each(items, install)
end

function snap.remove(items)
    return wait_seeded() and shell.each(items, uninstall)
end

return snap
