-- dconf keys (GNOME settings). `value` is GVariant text, written as
-- `dconf read` prints it: strings quoted ('prefer-dark'), lists as
-- ['a', 'b'], an empty typed list as @as []. Only the listed keys are
-- managed; everything else in the database is left alone. Writes go to
-- the user's session, so apply from a terminal inside the desktop.

shell = require("shell")
lfs = require("lfs")

dconf = {
    key = "key",
    fields = {key = "string", value = "string"},
    required = {present = {"key", "value"}, absent = {"key"}},
    states = {"present", "absent"},
}

function dconf.validate(item, state)
    if string.sub(item.key, 1, 1) != "/" or string.sub(item.key, -1) == "/" then
        return "key must be a full key path like /org/gnome/desktop/interface/color-scheme"
    end
    return nil
end

function dconf.available()
    if shell.has("dconf") then
        return true
    end
    return false, "dconf not installed"
end

-- Writes go through the desktop session's D-Bus. A terminal outside the
-- session (ssh, a tmux started elsewhere) has no DBUS_SESSION_BUS_ADDRESS,
-- and GLib then tries dbus-launch, which Ubuntu doesn't ship. The logged-in
-- session's bus is at $XDG_RUNTIME_DIR/bus (/run/user/<uid>/bus), so use
-- that when the variable is missing. Returns the env prefix, or nil and
-- why there is no bus.
function session_bus()
    address = os.getenv("DBUS_SESSION_BUS_ADDRESS")
    if address != nil and address != "" then
        return ""
    end
    runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime == nil or runtime == "" then
        uid, _ = shell.capture("id -u")
        runtime = "/run/user/" .. string.gsub(uid, "%s+$", "")
    end
    bus = runtime .. "/bus"
    if lfs.attributes(bus) == nil then
        return nil, "no desktop session bus at " .. bus .. "; log in to the desktop and apply from there"
    end
    return "env DBUS_SESSION_BUS_ADDRESS=" .. shell.quote("unix:path=" .. bus) .. " "
end

-- One `dconf dump /` for the whole database: full key path -> value.
-- The dump is keyfile-shaped: [org/gnome/desktop/interface] then
-- key=value lines, the value in the same text form `dconf read` uses.
function dconf.state(entries)
    out, ok = shell.capture("dconf dump /")
    if ok != true then
        error("dconf dump failed:\n" .. out, 0)
    end
    values = {}
    dir = "/"
    for _, line in ipairs(shell.lines(out)) do
        section = string.match(line, "^%[(.*)%]$")
        if section != nil then
            if section == "/" then
                dir = "/"
            else
                dir = "/" .. section .. "/"
            end
        else
            name, value = string.match(line, "^([^=]+)=(.*)$")
            if name != nil then
                values[dir .. name] = value
            end
        end
    end
    return values
end

-- dconf prints doubles with 17 significant digits (0.6 reads back as
-- 0.59999999999999998), so plain numbers compare as numbers.
function same_value(current, wanted)
    if current == wanted then
        return true
    end
    a = tonumber(current)
    b = tonumber(wanted)
    return a != nil and b != nil and a == b
end

function dconf.status(item, current, wanted)
    value = current[item.key]
    if value == nil then
        return "absent"
    end
    if wanted == "absent" or same_value(value, item.value) then
        return "present"
    end
    if string.len(value) > 60 then
        value = string.sub(value, 1, 57) .. "..."
    end
    return "absent", "now " .. value
end

-- Runs `dconf <args>` for each item on the session bus.
function each_on_bus(items, args_for)
    prefix, reason = session_bus()
    if prefix == nil then
        print("    " .. reason)
        return false
    end
    return shell.each(items, function(item)
        return shell.run(prefix .. "dconf " .. args_for(item))
    end)
end

function dconf.add(items)
    return each_on_bus(items, function(item)
        return "write " .. shell.quote(item.key) .. " " .. shell.quote(item.value)
    end)
end

function dconf.remove(items)
    return each_on_bus(items, function(item)
        return "reset " .. shell.quote(item.key)
    end)
end

return dconf
