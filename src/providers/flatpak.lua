-- Flatpak apps, installed system-wide. An item names its app ID and the
-- remote it comes from; with `remote_url`, that remote is added first
-- when missing (flatpak remote-add --if-not-exists), so a fresh install
-- needs nothing set up by hand. Removal uninstalls the app; remotes stay.

shell = require("shell")

flatpak = {
    key = "name",
    fields = {name = "string", remote = "string", remote_url = "string"},
    required = {present = {"name", "remote"}, absent = {"name"}},
    states = {"present", "absent"},
}

function flatpak.available()
    if shell.has("flatpak") then
        return true
    end
    return false, "flatpak not installed"
end

-- One listing of installed apps: app ID -> true.
function flatpak.state(entries, context)
    out, ok = shell.capture("flatpak list --app --columns=application")
    if ok != true then
        error("flatpak list failed:\n" .. out, 0)
    end
    installed = {}
    for _, line in ipairs(shell.lines(out)) do
        name = string.match(line, "^%s*(%S+)%s*$")
        if name != nil and name != "Application" then
            installed[name] = true
        end
    end
    return installed
end

function flatpak.status(item, current, wanted, context)
    if current[item.name] == true then
        return "present"
    end
    return "absent"
end

function add_remote(item)
    if item.remote_url == nil then
        return true
    end
    return shell.run(shell.sudo("flatpak remote-add --if-not-exists "
        .. shell.quote(item.remote) .. " " .. shell.quote(item.remote_url)))
end

function install(item)
    return add_remote(item) and shell.run(shell.sudo("flatpak install -y --noninteractive "
        .. shell.quote(item.remote) .. " " .. shell.quote(item.name)))
end

function uninstall(item)
    return shell.run(shell.sudo("flatpak uninstall -y --noninteractive " .. shell.quote(item.name)))
end

function flatpak.add(items)
    return shell.each(items, install)
end

function flatpak.remove(items)
    return shell.each(items, uninstall)
end

return flatpak
