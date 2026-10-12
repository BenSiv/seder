-- Symlinks. `path` is the link, `target` what it points to. A real file
-- or directory already at `path` (a fresh install's own ~/.bashrc) is
-- moved aside to <path>.orig, never deleted. "absent" removes only
-- symlinks; a real file there is left alone.

shell = require("shell")
lfs = require("lfs")

link = {
    key = "path",
    fields = {path = "string", target = "string"},
    required = {present = {"path", "target"}, absent = {"path"}},
    states = {"present", "absent"},
}

function link.validate(item, state)
    if string.sub(item.path, 1, 1) != "/" then
        return "path must be absolute (or start with ~/): " .. item.path
    end
    return nil
end

function link.available()
    return true
end

function link.state(entries)
    return {}
end

-- <path>.orig, or <path>.orig.N when that is taken too.
function backup_path(path)
    candidate = path .. ".orig"
    n = 1
    while lfs.symlinkattributes(candidate) != nil do
        candidate = path .. ".orig." .. n
        n = n + 1
    end
    return candidate
end

function link.status(item, current, wanted)
    attributes = lfs.symlinkattributes(item.path)
    if attributes == nil then
        return "absent"
    end
    if attributes.mode != "link" then
        if wanted == "present" then
            return "absent", "existing " .. attributes.mode .. " moves to " .. backup_path(item.path)
        end
        return "absent", "a real " .. attributes.mode .. ", not a link; left alone"
    end
    if wanted == "absent" or attributes.target == item.target then
        return "present"
    end
    return "absent", "now points to " .. tostring(attributes.target)
end

function make_link(item)
    path = item.path
    as_needed = function(cmd)
        return shell.for_path(path, cmd)
    end
    if shell.run(as_needed("mkdir -p " .. shell.quote(shell.parent(path)))) != true then
        return false
    end
    attributes = lfs.symlinkattributes(path)
    if attributes != nil and attributes.mode != "link" then
        backup = backup_path(path)
        if shell.run(as_needed("mv -- " .. shell.quote(path) .. " " .. shell.quote(backup))) != true then
            return false
        end
    end
    return shell.run(as_needed("ln -sfnT " .. shell.quote(item.target) .. " " .. shell.quote(path)))
end

function remove_link(item)
    return shell.run(shell.for_path(item.path, "rm -f -- " .. shell.quote(item.path)))
end

function link.add(items)
    return shell.each(items, make_link)
end

function link.remove(items)
    return shell.each(items, remove_link)
end

return link
