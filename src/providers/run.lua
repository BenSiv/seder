-- Commands, for steps no other provider covers (builds, luarocks, locale).
-- Every item must say how to tell it is already done: `creates` (a path
-- that exists afterwards) or `unless` (a check command that exits 0 when
-- done). An unguarded command would run on every apply, which is the
-- brittleness this tool exists to remove.
--
-- A build can also list `sources`: paths inside git checkouts. It is
-- stale, and runs again, when a git-tracked file under them is newer
-- than `creates` -- the rule make uses, with build outputs excluded
-- because they are untracked -- or when a source lies in a checkout this
-- plan pulls or clones.

shell = require("shell")
lfs = require("lfs")

run = {
    key = "name",
    fields = {
        name = "string", cmd = "string", dir = "string",
        creates = "string", unless = "string", env = "table", sudo = "boolean",
        sources = "table",
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
    if item.sources != nil then
        if item.creates == nil then
            return "'sources' needs 'creates', the output they are compared with"
        end
        for _, source in ipairs(item.sources) do
            if type(source) != "string" or string.sub(source, 1, 1) != "/" then
                return "sources must be absolute paths (or start with ~/)"
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

-- The newest git-tracked file under `source`: mtime and path, or 0
-- when there is none (not cloned yet, or not in a checkout).
function newest_tracked(source)
    out, ok = shell.capture("cd " .. shell.quote(source)
        .. " && git ls-files -z | xargs -0 -r stat -c '%Y %n' | sort -n | tail -n 1")
    seconds, name = string.match(out, "^(%d+) (.-)%s*$")
    if ok != true or seconds == nil then
        return 0, nil
    end
    return tonumber(seconds), source .. "/" .. name
end

function inside(path, root)
    return path == root or string.sub(path, 1, string.len(root) + 1) == root .. "/"
end

-- Why `item`'s output is older than its sources, or nil when it isn't.
-- `changing` is the list of paths this plan will change (may be nil).
function stale_reason(item, changing)
    built = lfs.attributes(item.creates, "modification")
    for _, source in ipairs(item.sources) do
        if changing != nil then
            for _, root in ipairs(changing) do
                if inside(source, root) then
                    return root .. " is being updated"
                end
            end
        end
        seconds, name = newest_tracked(source)
        if seconds > built then
            return name .. " is newer than the build"
        end
    end
    return nil
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

function run.status(item, current, wanted, context)
    if done(item) == false then
        return "absent"
    end
    if item.sources != nil then
        reason = stale_reason(item, context.changing)
        if reason != nil then
            return "absent", reason
        end
    end
    return "present"
end

function execute(item)
    if shell.run(wrap(item, item.cmd)) != true then
        return false
    end
    if item.creates != nil and lfs.attributes(item.creates) == nil then
        print("    ran, but " .. item.creates .. " was not created")
        return false
    end
    if item.sources != nil then
        reason = stale_reason(item, nil)
        if reason != nil then
            print("    ran, but " .. item.creates .. " is still older than its sources: " .. reason)
            return false
        end
    end
    return true
end

function run.add(items)
    return shell.each(items, execute)
end

return run
