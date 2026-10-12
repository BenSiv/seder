-- Debian packages. An item with `url` is a .deb downloaded and installed
-- through apt (Chrome, Quarto); without it, a package from the enabled
-- repositories. Removal purges.

shell = require("shell")

apt = {
    key = "name",
    fields = {name = "string", url = "string"},
    required = {present = {"name"}, absent = {"name"}},
    states = {"present", "absent"},
}

APT = "env DEBIAN_FRONTEND=noninteractive apt-get -y"
UPDATED = false

function apt.available()
    if shell.has("dpkg-query") then
        return true
    end
    return false, "dpkg not installed"
end

-- Which wanted-but-missing repository packages apt knows about, so a
-- misspelled or renamed package shows in the plan rather than failing
-- halfway through apply. apt-cache policy prints a block per known
-- name; unknown names print nothing on stdout.
function known_packages(entries, installed)
    names = {}
    for _, entry in ipairs(entries) do
        item = entry.item
        if entry.state == "present" and item.url == nil and installed[item.name] == nil then
            table.insert(names, shell.quote(item.name))
        end
    end
    known = {}
    if #names == 0 then
        return known
    end
    out, _ = shell.capture("apt-cache policy " .. table.concat(names, " ") .. " 2>/dev/null")
    name = nil
    for _, line in ipairs(shell.lines(out)) do
        header = string.match(line, "^(%S+):$")
        if header != nil then
            name = header
        end
        candidate = string.match(line, "^%s+Candidate: (%S+)")
        if candidate != nil and candidate != "(none)" and name != nil then
            known[name] = true
        end
    end
    return known
end

-- One dpkg-query for every package on the machine: name -> true when
-- installed (second status letter "i": ii, hi, ...).
function apt.state(entries)
    out, ok = shell.capture("dpkg-query -W -f='${Package}\\t${db:Status-Abbrev}\\n'")
    if ok != true then
        error("dpkg-query failed:\n" .. out, 0)
    end
    installed = {}
    for _, line in ipairs(shell.lines(out)) do
        name, status = string.match(line, "^(%S+)\t(%S+)")
        if name != nil and string.sub(status, 2, 2) == "i" then
            installed[name] = true
        end
    end
    return {installed = installed, known = known_packages(entries, installed)}
end

function apt.status(item, current, wanted)
    if current.installed[item.name] == true then
        return "present"
    end
    if wanted == "present" and item.url == nil and current.known[item.name] == nil then
        return "absent", "not in the apt cache; apt update may find it"
    end
    return "absent"
end

function install_deb(item)
    path = os.tmpname() .. ".deb"
    ok = shell.run("curl -fsSL -o " .. shell.quote(path) .. " " .. shell.quote(item.url))
        and shell.run(shell.sudo(APT .. " install " .. shell.quote(path)))
    os.remove(path)
    return ok
end

function apt.add(items)
    from_repos = {}
    debs = {}
    for _, item in ipairs(items) do
        if item.url != nil then
            table.insert(debs, item)
        else
            table.insert(from_repos, shell.quote(item.name))
        end
    end
    if UPDATED == false then
        if shell.run(shell.sudo(APT .. " update")) != true then
            return false
        end
        UPDATED = true
    end
    if #from_repos > 0 then
        if shell.run(shell.sudo(APT .. " install " .. table.concat(from_repos, " "))) != true then
            return false
        end
    end
    return shell.each(debs, install_deb)
end

function apt.remove(items)
    names = {}
    for _, item in ipairs(items) do
        table.insert(names, shell.quote(item.name))
    end
    return shell.run(shell.sudo(APT .. " purge " .. table.concat(names, " ")))
end

return apt
