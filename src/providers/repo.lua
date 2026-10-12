-- Git checkouts. Cloned when missing, never deleted from here: a working
-- copy can hold work in progress. With --pull, an existing checkout is
-- fetched and fast-forwarded to its upstream, but only when that is
-- safe: the branch has an upstream, no local commits, no local changes.
-- Anything else is left alone, with the reason in the plan.

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

function repo.state(entries, context)
    return {}
end

-- Cloning or pulling changes everything under the checkout.
function repo.touches(item)
    return item.path
end

function is_empty_dir(path)
    for name in lfs.dir(path) do
        if name != "." and name != ".." then
            return false
        end
    end
    return true
end

function git(item, args)
    return shell.capture("git -C " .. shell.quote(item.path) .. " " .. args)
end

-- An existing checkout against its upstream, after a fetch: "present"
-- when current or when it must not be touched, "absent" when it can be
-- fast-forwarded.
function upstream_status(item)
    out, ok = git(item, "fetch --quiet")
    if ok != true then
        return "present", "fetch failed; not updated"
    end
    upstream, ok = git(item, "rev-parse --abbrev-ref --symbolic-full-name '@{u}'")
    if ok != true then
        return "present", "branch has no upstream; not updated"
    end
    upstream = string.gsub(upstream, "%s+$", "")
    counts, _ = git(item, "rev-list --left-right --count 'HEAD...@{u}'")
    ahead, behind = string.match(counts, "^(%d+)%s+(%d+)")
    if ahead == nil or behind == "0" then
        return "present"
    end
    if ahead != "0" then
        return "present", behind .. " behind and " .. ahead .. " ahead of " .. upstream .. "; not updated"
    end
    -- Untracked files (build outputs) never block a fast-forward.
    changes, _ = git(item, "status --porcelain --untracked-files=no")
    if changes != "" then
        return "present", behind .. " behind " .. upstream .. ", local changes; not updated"
    end
    return "absent", behind .. " commits behind " .. upstream .. "; fast-forward"
end

function repo.status(item, current, wanted, context)
    attributes = lfs.symlinkattributes(item.path)
    if attributes == nil then
        return "absent"
    end
    if lfs.attributes(item.path .. "/.git") != nil then
        if context.options.pull == true then
            return upstream_status(item)
        end
        return "present"
    end
    if attributes.mode == "directory" and is_empty_dir(item.path) then
        return "absent"
    end
    return "conflict", "exists but is not a git checkout"
end

function clone_or_pull(item)
    if lfs.attributes(item.path .. "/.git") != nil then
        -- Submodules follow, as a --recurse-submodules clone would.
        here = "git -C " .. shell.quote(item.path)
        return shell.run(here .. " merge --ff-only --quiet '@{u}'")
            and shell.run(here .. " submodule update --init --recursive --quiet")
    end
    return shell.run("mkdir -p " .. shell.quote(shell.parent(item.path)))
        and shell.run("git clone --recurse-submodules " .. shell.quote(item.url)
            .. " " .. shell.quote(item.path))
end

function repo.add(items)
    return shell.each(items, clone_or_pull)
end

return repo
