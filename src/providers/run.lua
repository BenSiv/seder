-- Commands, for steps no other provider covers (builds, luarocks, locale).
-- Every item must say how to tell it is already done: `creates` (a path
-- that exists afterwards) or `unless` (a check command that exits 0 when
-- done). An unguarded command would run on every apply, which is the
-- brittleness this tool exists to remove.

shell = require("shell")
lfs = require("lfs")

run = {
    key = "name",
    fields = {
        name = "string", cmd = "string", dir = "string",
        creates = "string", unless = "string", env = "table", sudo = "boolean",
    },
    required = {present = {"name", "cmd"}},
    states = {"present"},
}

function run.validate(item, state)
    if item.creates == nil and item.unless == nil then
        return "needs 'creates' or 'unless' so it is not rerun every time"
    end
    if item.env != nil then
        for key, value in pairs(item.env) do
            if type(key) != "string" or type(value) != "string" then
                return "env must map names to strings"
            end
        end
    end
    return nil
end

function run.available()
    return true
end

function run.state(entries)
    return {}
end

-- `body` wrapped with the item's dir and env, as one sh -c command
-- (through sudo when the item says so).
function wrap(item, body)
    script = ""
    if item.dir != nil then
        script = "cd " .. shell.quote(item.dir) .. " && "
    end
    if item.env != nil then
        names = {}
        for name, _ in pairs(item.env) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in ipairs(names) do
            script = script .. "export " .. name .. "=" .. shell.quote(item.env[name]) .. "; "
        end
    end
    cmd = "sh -c " .. shell.quote(script .. body)
    if item.sudo == true then
        return shell.sudo(cmd)
    end
    return cmd
end

function done(item)
    if item.creates != nil then
        return lfs.attributes(item.creates) != nil
    end
    -- The check runs unprivileged even for sudo items: it only reads.
    unprivileged = {dir = item.dir, env = item.env}
    if item.dir != nil and lfs.attributes(item.dir) == nil then
        return false
    end
    return shell.ok(wrap(unprivileged, item.unless))
end

function run.status(item, current, wanted)
    if done(item) then
        return "present"
    end
    return "absent"
end

function execute(item)
    if shell.run(wrap(item, item.cmd)) != true then
        return false
    end
    if item.creates != nil and lfs.attributes(item.creates) == nil then
        print("    ran, but " .. item.creates .. " was not created")
        return false
    end
    return true
end

function run.add(items)
    return shell.each(items, execute)
end

return run
