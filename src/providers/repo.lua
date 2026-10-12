-- Git checkouts. Cloned once (with submodules) and never updated or
-- deleted from here: a working copy can hold work in progress.

shell = require("shell")
lfs = require("lfs")

repo = {
    key = "path",
    fields = {path = "string", url = "string"},
    required = {present = {"path", "url"}},
    states = {"present"},
}

function repo.validate(item, state)
    if string.sub(item.path, 1, 1) != "/" then
        return "path must be absolute (or start with ~/): " .. item.path
    end
    return nil
end

function repo.available()
    if shell.has("git") then
        return true
    end
    return false, "git not installed"
end

function repo.state(entries)
    return {}
end

function is_empty_dir(path)
    for name in lfs.dir(path) do
        if name != "." and name != ".." then
            return false
        end
    end
    return true
end

function repo.status(item, current, wanted)
    attributes = lfs.symlinkattributes(item.path)
    if attributes == nil then
        return "absent"
    end
    if lfs.attributes(item.path .. "/.git") != nil then
        return "present"
    end
    if attributes.mode == "directory" and is_empty_dir(item.path) then
        return "absent"
    end
    return "conflict", "exists but is not a git checkout"
end

function clone(item)
    return shell.run("mkdir -p " .. shell.quote(shell.parent(item.path)))
        and shell.run("git clone --recurse-submodules " .. shell.quote(item.url)
            .. " " .. shell.quote(item.path))
end

function repo.add(items)
    return shell.each(items, clone)
end

return repo
