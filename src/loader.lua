-- Loads machine and bundle files and turns them into the desired state the
-- engine plans against. Files are data, not code: each is run in the
-- same data-only sandbox daat uses for platform.lua and schemas (no io,
-- os or require) and must return a table. Every field is then checked
-- against the provider that owns it, so a typo fails before anything
-- touches the machine.

sandbox = require("sandbox")
shell = require("shell")

loader = {}

MACHINE_KEYS = {vars = "table", bundles = "table"}

function fail(path, message)
    error(path .. ": " .. message, 0)
end

function read_source(path)
    file = io.open(path, "r")
    if file == nil then
        fail(path, "file not found")
    end
    source = io.read(file, "*a")
    io.close(file)
    return source
end

function loader.load_table(path)
    ok, value = sandbox.run(read_source(path), "@" .. path, sandbox.data_env())
    if ok != true then
        fail(path, tostring(value))
    end
    if type(value) != "table" then
        fail(path, "must return a table, got " .. type(value))
    end
    return value
end

function sorted_keys(tbl)
    keys = {}
    for key, _ in pairs(tbl) do
        table.insert(keys, tostring(key))
    end
    table.sort(keys)
    return keys
end

-- type() with booleans named "boolean" (luam calls them "flag"), so
-- providers and error messages use the familiar name.
function type_name(value)
    name = type(value)
    if name == "flag" then
        return "boolean"
    end
    return name
end

function is_list(tbl)
    count = 0
    for _, _ in pairs(tbl) do
        count = count + 1
    end
    return count == #tbl
end

-- ${name} -> vars[name]; a leading ~/ -> $HOME/. Applied to every
-- string in an item, including the values of nested tables (env).
function expand_string(value, vars, where)
    missing = nil
    value = string.gsub(value, "%${([%w_]+)}", function(name)
        if vars[name] == nil then
            missing = name
            return nil
        end
        return vars[name]
    end)
    if missing != nil then
        error(where .. ": unknown variable ${" .. missing .. "}", 0)
    end
    if value == "~" then
        return shell.home()
    end
    if string.sub(value, 1, 2) == "~/" then
        return shell.home() .. string.sub(value, 2)
    end
    return value
end

function expand_value(value, vars, where)
    if type(value) == "string" then
        return expand_string(value, vars, where)
    end
    if type(value) == "table" then
        result = {}
        for key, inner in pairs(value) do
            result[key] = expand_value(inner, vars, where)
        end
        return result
    end
    return value
end

function supports(provider, state)
    for _, name in ipairs(provider.states) do
        if name == state then
            return true
        end
    end
    return false
end

-- Checks one raw item from a bundle file and returns it normalized
-- (a bare string becomes {<key> = string}) and expanded.
function normalize_item(raw, provider, state, vars, where)
    item = raw
    if type(raw) == "string" then
        item = {}
        item[provider.key] = raw
    end
    if type(item) != "table" then
        error(where .. ": expected a string or table, got " .. type(raw), 0)
    end
    for field, value in pairs(item) do
        expected = provider.fields[field]
        if expected == nil then
            error(where .. ": unknown field '" .. tostring(field) .. "' (allowed: "
                .. table.concat(sorted_keys(provider.fields), ", ") .. ")", 0)
        end
        if type_name(value) != expected then
            error(where .. ": field '" .. field .. "' must be a " .. expected
                .. ", got " .. type_name(value), 0)
        end
    end
    for _, field in ipairs(provider.required[state]) do
        if item[field] == nil then
            error(where .. ": missing required field '" .. field .. "'", 0)
        end
    end
    item = expand_value(item, vars, where)
    if provider.validate != nil then
        err = provider.validate(item, state)
        if err != nil then
            error(where .. ": " .. err, 0)
        end
    end
    return item
end

function loader.load_machine(path)
    machine = loader.load_table(path)
    for key, value in pairs(machine) do
        if MACHINE_KEYS[key] == nil then
            fail(path, "unknown key '" .. tostring(key) .. "' (allowed: vars, bundles)")
        end
        if type(value) != MACHINE_KEYS[key] then
            fail(path, "'" .. key .. "' must be a table")
        end
    end
    if machine.bundles == nil or #machine.bundles == 0 then
        fail(path, "'bundles' must list at least one bundle")
    end
    uid, _ = shell.capture("id -u")
    vars = {home = shell.home(), user = os.getenv("USER"), uid = string.gsub(uid, "%s+$", "")}
    if machine.vars != nil then
        for name, value in pairs(machine.vars) do
            if type(value) != "string" then
                fail(path, "var '" .. tostring(name) .. "' must be a string")
            end
            vars[name] = value
        end
    end
    -- Vars may refer to each other and to ~ (projects = "~/Projects").
    for name, value in pairs(vars) do
        vars[name] = expand_string(value, vars, path .. ": var " .. name)
    end
    machine.vars = vars
    return machine
end

-- Builds the desired state for a machine file:
--   desired[provider_name] = list of {item, state, bundle, where}
-- in the machine's bundle order, then file order. Bundles are read from
-- the bundles/ directory next to the machine file's directory. The same resource wanted both
-- present and absent is an error, naming both places.
function loader.load_desired(machine_path, providers)
    machine = loader.load_machine(machine_path)
    bundle_dir = shell.parent(shell.parent(machine_path)) .. "/bundles"
    desired = {}
    seen = {}
    for _, bundle_name in ipairs(machine.bundles) do
        path = bundle_dir .. "/" .. bundle_name .. ".lua"
        bundle = loader.load_table(path)
        for _, provider_name in ipairs(sorted_keys(bundle)) do
            provider = providers[provider_name]
            if provider == nil then
                fail(path, "unknown provider '" .. provider_name .. "' (known: "
                    .. table.concat(sorted_keys(providers), ", ") .. ")")
            end
            section = bundle[provider_name]
            if type(section) != "table" then
                fail(path, provider_name .. " must be a table of present/absent lists")
            end
            for _, state in ipairs(sorted_keys(section)) do
                if state != "present" and state != "absent" then
                    fail(path, provider_name .. ": unknown key '" .. state
                        .. "' (allowed: present, absent)")
                end
                if supports(provider, state) == false then
                    fail(path, provider_name .. " does not support '" .. state .. "'")
                end
                items = section[state]
                if type(items) != "table" or is_list(items) == false then
                    fail(path, provider_name .. "." .. state .. " must be a list")
                end
                if desired[provider_name] == nil then
                    desired[provider_name] = {}
                end
                for index, raw in ipairs(items) do
                    where = path .. ": " .. provider_name .. "." .. state .. "[" .. index .. "]"
                    item = normalize_item(raw, provider, state, machine.vars, where)
                    id = provider_name .. ":" .. item[provider.key]
                    previous = seen[id]
                    if previous == nil then
                        seen[id] = {state = state, where = where}
                        table.insert(desired[provider_name],
                            {item = item, state = state, bundle = bundle_name, where = where})
                    elseif previous.state != state then
                        error(where .. ": wants " .. item[provider.key] .. " " .. state
                            .. ", but " .. previous.where .. " wants it " .. previous.state, 0)
                    end
                end
            end
        end
    end
    return desired, machine
end

return loader
