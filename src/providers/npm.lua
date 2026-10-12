-- Global npm packages. When npm itself is missing, "absent" already
-- holds and nothing runs -- the failure that started this project.

shell = require("shell")

npm = {
    key = "name",
    fields = {name = "string"},
    required = {present = {"name"}, absent = {"name"}},
    states = {"present", "absent"},
}

function npm.available()
    if shell.has("npm") then
        return true
    end
    return false, "npm not installed"
end

-- name -> true per global package; --parseable prints one install
-- path per line, ending in node_modules/<name> (scoped names keep
-- their @scope/ prefix).
function npm.state(entries)
    out, _ = shell.capture("npm ls -g --depth=0 --parseable")
    installed = {}
    for _, line in ipairs(shell.lines(out)) do
        name = string.match(line, "node_modules/(.+)$")
        if name != nil then
            installed[name] = true
        end
    end
    return installed
end

function npm.status(item, current)
    if current[item.name] == true then
        return "present"
    end
    return "absent"
end

-- A global prefix the user can write to (nvm, ~/.npm-global) needs no sudo.
function npm_cmd(args)
    cmd = "npm " .. args
    if shell.ok("test -w \"$(npm prefix -g)\"") then
        return cmd
    end
    return shell.sudo(cmd)
end

function names_of(items)
    names = {}
    for _, item in ipairs(items) do
        table.insert(names, shell.quote(item.name))
    end
    return table.concat(names, " ")
end

function npm.add(items)
    return shell.run(npm_cmd("install -g " .. names_of(items)))
end

function npm.remove(items)
    return shell.run(npm_cmd("uninstall -g " .. names_of(items)))
end

return npm
