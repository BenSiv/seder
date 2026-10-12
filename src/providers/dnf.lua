-- RPM packages through dnf (Fedora, RHEL and derivatives). An item with
-- `url` is an .rpm dnf installs straight from that URL; without it, a
-- package from the enabled repositories.

shell = require("shell")

dnf = {
    key = "name",
    fields = {name = "string", url = "string"},
    required = {present = {"name"}, absent = {"name"}},
    states = {"present", "absent"},
}

function dnf.available()
    if shell.has("dnf") and shell.has("rpm") then
        return true
    end
    return false, "dnf not installed"
end

-- One rpm query for every installed package: name -> true.
function dnf.state(entries, context)
    out, ok = shell.capture("rpm -qa --qf '%{NAME}\\n'")
    if ok != true then
        error("rpm -qa failed:\n" .. out, 0)
    end
    installed = {}
    for _, line in ipairs(shell.lines(out)) do
        installed[line] = true
    end
    return installed
end

function dnf.status(item, current, wanted, context)
    if current[item.name] == true then
        return "present"
    end
    return "absent"
end

-- A URL item installs from its URL; the rest by name, in one call.
function targets(items)
    names = {}
    for _, item in ipairs(items) do
        if item.url != nil then
            table.insert(names, shell.quote(item.url))
        else
            table.insert(names, shell.quote(item.name))
        end
    end
    return table.concat(names, " ")
end

function dnf.add(items)
    return shell.run(shell.sudo("dnf install -y " .. targets(items)))
end

function dnf.remove(items)
    names = {}
    for _, item in ipairs(items) do
        table.insert(names, shell.quote(item.name))
    end
    return shell.run(shell.sudo("dnf remove -y " .. table.concat(names, " ")))
end

return dnf
