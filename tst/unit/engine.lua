-- tst/unit/engine.lua
-- Unit tests for src/engine.lua's planning and apply order, against fake
-- providers that record calls instead of running commands. The real apt
-- and npm providers are swapped out by name, so PROVIDER_ORDER applies.

engine = require("engine")

FAILURES = 0
CALLS = {}

function check(condition, message)
    if condition != true then
        FAILURES = FAILURES + 1
        print("FAIL: " .. message)
    end
end

-- A provider whose machine state is `installed` (name -> true) and
-- whose tool exists when `available` is true.
function fake_provider(label, installed, available)
    provider = {key = "name"}
    provider.available = function()
        if available then
            return true
        end
        return false, label .. " not installed"
    end
    provider.state = function(entries)
        return installed
    end
    provider.status = function(item, current, wanted)
        if current[item.name] == true then
            return "present"
        end
        return "absent"
    end
    provider.add = function(items)
        for _, item in ipairs(items) do
            table.insert(CALLS, label .. " add " .. item.name)
        end
        return true
    end
    provider.remove = function(items)
        for _, item in ipairs(items) do
            table.insert(CALLS, label .. " remove " .. item.name)
        end
        return true
    end
    return provider
end

function entry(name, state)
    return {item = {name = name}, state = state, bundle = "test", where = "test"}
end

function kinds(groups)
    result = {}
    for _, group in ipairs(groups) do
        for _, action in ipairs(group.actions) do
            result[group.name .. ":" .. action.label] = action.kind
        end
    end
    return result
end

function test_plan_decisions()
    print("Testing plan compares wanted against installed")
    engine.providers.apt = fake_provider("apt", {firefox = true, jq = true}, true)
    groups = engine.plan({apt = {
        entry("firefox", "absent"), entry("thunderbird", "absent"),
        entry("jq", "present"), entry("gimp", "present"),
    }})
    result = kinds(groups)
    check(result["apt:firefox"] == "remove", "installed + absent -> remove")
    check(result["apt:thunderbird"] == "ok", "missing + absent -> ok")
    check(result["apt:jq"] == "ok", "installed + present -> ok")
    check(result["apt:gimp"] == "add", "missing + present -> add")
end

function test_missing_tool()
    print("Testing a provider whose tool is missing")
    engine.providers.npm = fake_provider("npm", {}, false)
    groups = engine.plan({npm = {entry("codex", "absent"), entry("prettier", "present")}})
    result = kinds(groups)
    check(result["npm:codex"] == "ok", "absent is already satisfied")
    check(result["npm:prettier"] == "add", "present is left to apply")
    check(groups[1].actions[1].note == "npm not installed", "reason shown in the plan")
end

function test_apply_order()
    print("Testing removals run in reverse provider order, before additions")
    CALLS = {}
    engine.providers.apt = fake_provider("apt", {npm = true}, true)
    engine.providers.npm = fake_provider("npm", {codex = true}, true)
    groups = engine.plan({
        apt = {entry("npm", "absent"), entry("jq", "present")},
        npm = {entry("codex", "absent"), entry("prettier", "present")},
    })
    check(engine.apply(groups) == true, "apply succeeds")
    expected = {"npm remove codex", "apt remove npm", "apt add jq", "npm add prettier"}
    check(table.concat(CALLS, ", ") == table.concat(expected, ", "),
        "order, got: " .. table.concat(CALLS, ", "))
end

function test_conflicts_block_apply()
    print("Testing apply refuses a plan with conflicts")
    CALLS = {}
    engine.providers.apt = fake_provider("apt", {}, true)
    engine.providers.apt.status = function(item, current, wanted)
        return "conflict", "in the way"
    end
    groups = engine.plan({apt = {entry("x", "present")}})
    check(engine.apply(groups) == false, "apply refused")
    check(#CALLS == 0, "nothing ran")
end

-- Run them
test_plan_decisions()
test_missing_tool()
test_apply_order()
test_conflicts_block_apply()

if FAILURES > 0 then
    print(FAILURES .. " test(s) failed")
    os.exit(1)
end
print("All engine.lua tests passed")
