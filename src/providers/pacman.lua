-- Packages through pacman (Arch and derivatives). An item with `url` is a
-- package file pacman installs from that URL (-U); without it, one from
-- the sync repositories (-S --needed). seder doesn't upgrade the system:
-- run pacman -Syu yourself, since Arch doesn't support partial upgrades.
-- Removal also drops dependencies nothing else needs (-Rns).

shell = require("shell")

pacman = {
    key = "name",
    fields = {name = "string", url = "string"},
    required = {present = {"name"}, absent = {"name"}},
    states = {"present", "absent"},
}

function pacman.available()
    if shell.has("pacman") then
        return true
    end
    return false, "pacman not installed"
end

-- One query for every installed package: name -> true.
function pacman.state(entries, context)
    out, ok = shell.capture("pacman -Qq")
    if ok != true then
        error("pacman -Qq failed:\n" .. out, 0)
    end
    installed = {}
    for _, line in ipairs(shell.lines(out)) do
        installed[line] = true
    end
    return installed
end

function pacman.status(item, current, wanted, context)
    if current[item.name] == true then
        return "present"
    end
    return "absent"
end

function quoted(values)
    result = {}
    for _, value in ipairs(values) do
        table.insert(result, shell.quote(value))
    end
    return table.concat(result, " ")
end

function pacman.add(items)
    from_repos = {}
    files = {}
    for _, item in ipairs(items) do
        if item.url != nil then
            table.insert(files, item.url)
        else
            table.insert(from_repos, item.name)
        end
    end
    if #from_repos > 0 then
        if shell.run(shell.sudo("pacman -S --needed --noconfirm " .. quoted(from_repos))) != true then
            return false
        end
    end
    if #files > 0 then
        return shell.run(shell.sudo("pacman -U --noconfirm " .. quoted(files)))
    end
    return true
end

function pacman.remove(items)
    names = {}
    for _, item in ipairs(items) do
        table.insert(names, item.name)
    end
    return shell.run(shell.sudo("pacman -Rns --noconfirm " .. quoted(names)))
end

return pacman
