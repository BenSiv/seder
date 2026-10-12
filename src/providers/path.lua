-- Directories that should exist, and files or directories that should
-- not. Removal is rm -rf, so every path must be absolute and at least
-- two levels deep, and never the home directory itself.

shell = require("shell")
lfs = require("lfs")

path = {
    key = "path",
    fields = {path = "string"},
    required = {present = {"path"}, absent = {"path"}},
    states = {"present", "absent"},
}

function path.validate(item, state)
    if string.sub(item.path, 1, 1) != "/" then
        return "path must be absolute (or start with ~/): " .. item.path
    end
    if string.match(item.path, "^/[^/]+/[^/]") == nil then
        return "refusing a path this close to /: " .. item.path
    end
    if string.gsub(item.path, "/+$", "") == shell.home() then
        return "refusing the home directory itself"
    end
    return nil
end

function path.available()
    return true
end

function path.state(entries)
    return {}
end

function path.status(item, current, wanted)
    attributes = lfs.symlinkattributes(item.path)
    if attributes == nil then
        return "absent"
    end
    -- Something that is not a directory is in the way of "present";
    -- for "absent" anything that exists gets removed.
    if wanted == "present" and attributes.mode != "directory" then
        return "conflict", "exists as a " .. attributes.mode .. ", not a directory"
    end
    return "present"
end

function make_dir(item)
    return shell.run(shell.for_path(item.path, "mkdir -p " .. shell.quote(item.path)))
end

function remove_path(item)
    return shell.run(shell.for_path(item.path, "rm -rf -- " .. shell.quote(item.path)))
end

function path.add(items)
    return shell.each(items, make_dir)
end

function path.remove(items)
    return shell.each(items, remove_path)
end

return path
