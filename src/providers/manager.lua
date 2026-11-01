-- Package managers seder has no built-in provider for, described as data.
-- A configuration's managers/<name>.lua gives the shell commands that
-- list, install and remove packages; this module turns that description
-- into a provider, so a bundle can say `zypper = {present = {...}}` like
-- it says `apt = ...`.
--
--   return {
--       command = "zypper",                     -- must be on PATH (default: the file name)
--       list    = "rpm -qa --qf '%{NAME}\\n'",  -- installed packages, one per line
--       install = "zypper --non-interactive install",
--       remove  = "zypper --non-interactive remove",
--       refresh = "zypper --non-interactive refresh",  -- optional, once before installing
--       sudo    = true,                         -- default true; false for user-level tools
--       one_at_a_time = false,                  -- true: one install/remove call per package
--       after   = "pacman",                     -- built-in provider it runs after (default)
--   }
--
-- Package names are appended to install and remove, quoted, all in one
-- call unless `one_at_a_time` is set. Only the
-- first word of each `list` line counts, so "name version" output works.

shell = require("shell")

manager = {}

DEFINITION_FIELDS = {
    command = "string", list = "string", install = "string", remove = "string",
    refresh = "string", sudo = "boolean", after = "string", one_at_a_time = "boolean",
}

REQUIRED = {"list", "install", "remove"}

-- Returns an error string for a malformed definition, or nil.
-- `known` lists the providers `after` may name.
function manager.check(definition, known)
    for field, value in pairs(definition) do
        expected = DEFINITION_FIELDS[field]
        if expected == nil then
            return "unknown key '" .. tostring(field)
                .. "' (allowed: after, command, install, list, one_at_a_time, refresh, remove, sudo)"
        end
        actual = type(value)
        if actual == "flag" then
            actual = "boolean"
        end
        if actual != expected then
            return "'" .. field .. "' must be a " .. expected .. ", got " .. actual
        end
    end
    for _, field in ipairs(REQUIRED) do
        if definition[field] == nil then
            return "missing required key '" .. field .. "'"
        end
    end
    if definition.after != nil and known[definition.after] == nil then
        return "'after' must name a built-in provider, got '" .. definition.after .. "'"
    end
    return nil
end

-- Runs `base` with the items' names appended: once for all of them, or
-- once per item when `one_at_a_time`.
function run_with_names(base, items, one_at_a_time, wrap)
    if one_at_a_time then
        return shell.each(items, function(item)
            return shell.run(wrap(base .. " " .. shell.quote(item.name)))
        end)
    end
    names = {}
    for _, item in ipairs(items) do
        table.insert(names, shell.quote(item.name))
    end
    return shell.run(wrap(base .. " " .. table.concat(names, " ")))
end

-- A provider for the manager called `name`, from a checked definition.
function manager.provider(name, definition)
    command = definition.command
    if command == nil then
        command = name
    end
    after = definition.after
    if after == nil then
        after = "pacman"
    end
    privileged = definition.sudo != false

    function as_needed(cmd)
        if privileged then
            return shell.sudo(cmd)
        end
        return cmd
    end

    provider = {
        key = "name",
        fields = {name = "string"},
        required = {present = {"name"}, absent = {"name"}},
        states = {"present", "absent"},
        after = after,
    }

    function provider.available()
        if shell.has(command) then
            return true
        end
        return false, command .. " not installed"
    end

    -- One `list` call for every installed package: name -> true.
    function provider.state(entries, context)
        out, ok = shell.capture(definition.list)
        if ok != true then
            error(name .. ": '" .. definition.list .. "' failed:\n" .. out, 0)
        end
        installed = {}
        for _, line in ipairs(shell.lines(out)) do
            word = string.match(line, "^%s*(%S+)")
            if word != nil then
                installed[word] = true
            end
        end
        return installed
    end

    function provider.status(item, current, wanted, context)
        if current[item.name] == true then
            return "present"
        end
        return "absent"
    end

    function provider.add(items)
        if definition.refresh != nil and shell.run(as_needed(definition.refresh)) != true then
            return false
        end
        return run_with_names(definition.install, items, definition.one_at_a_time == true, as_needed)
    end

    function provider.remove(items)
        return run_with_names(definition.remove, items, definition.one_at_a_time == true, as_needed)
    end

    return provider
end

return manager
