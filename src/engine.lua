-- Plan and apply. The engine never assumes what is on the machine: each
-- provider probes the current state once, every desired item is compared
-- against it, and only the differences become actions. Removing
-- something that is not there is a no-op by construction, not a guard
-- each task has to remember.
--
-- Provider contract (see providers/*.lua):
--   key       field that identifies an item ("name", "path")
--   fields    field -> lua type, the only fields an item may have
--   required  state -> list of fields that must be set
--   states    which of "present"/"absent" the provider supports
--   available()        -> ok, reason   tool exists and can be probed
--   state(entries, context)  -> current   one probe for all items
--   status(item, current, wanted, context)
--                      -> "present" | "absent" | "conflict", note
--   add(items) / remove(items) -> ok
-- Optional: validate(item, state) -> error string or nil;
--           touches(item) -> path an add/remove of this item changes.
--
-- `context` carries the run's options (context.options.pull) and the
-- paths earlier providers in this plan will change (context.changing),
-- so a build whose sources are about to be pulled counts as stale now
-- rather than on the next run.

shell = require("shell")

engine = {}

-- Additions run in this order and removals in reverse: system packages
-- (whichever manager the data uses) first, then other package sources;
-- packages before
-- the repos, links and builds that need them, and npm packages are
-- removed before npm itself. Settings (dconf) come after the files they
-- may point at; run comes last, so builds see everything else in place.
PROVIDER_ORDER = {
    "apt", "dnf", "pacman", "snap", "flatpak", "npm",
    "path", "repo", "link", "dconf", "run",
}

engine.providers = {
    apt = require("providers.apt"),
    dnf = require("providers.dnf"),
    pacman = require("providers.pacman"),
    snap = require("providers.snap"),
    flatpak = require("providers.flatpak"),
    npm = require("providers.npm"),
    path = require("providers.path"),
    repo = require("providers.repo"),
    link = require("providers.link"),
    dconf = require("providers.dconf"),
    run = require("providers.run"),
}

function decide(provider, entry, available, reason, current, context)
    action = {entry = entry, label = entry.item[provider.key], note = nil}
    if available != true then
        -- Without the tool nothing of its kind can be installed, so
        -- "absent" already holds. "present" is left to apply: an earlier
        -- step (apt installing npm) may provide the tool.
        if entry.state == "absent" then
            action.kind = "ok"
            action.note = reason
        else
            action.kind = "add"
            action.note = reason .. "; not checked"
        end
        return action
    end
    status, note = provider.status(entry.item, current, entry.state, context)
    action.note = note
    if status == "conflict" then
        action.kind = "conflict"
    elseif status == entry.state then
        action.kind = "ok"
    elseif entry.state == "present" then
        action.kind = "add"
    else
        action.kind = "remove"
    end
    return action
end

-- Returns a plan: one group per provider, in PROVIDER_ORDER, each with
-- its actions. Action kinds: "add", "remove", "ok", "conflict".
-- options.pull: let repo items fast-forward to their upstream.
function engine.plan(desired, options)
    if options == nil then
        options = {}
    end
    context = {options = options, changing = {}}
    groups = {}
    for _, name in ipairs(PROVIDER_ORDER) do
        entries = desired[name]
        if entries != nil and #entries > 0 then
            provider = engine.providers[name]
            available, reason = provider.available()
            current = nil
            if available == true then
                current = provider.state(entries, context)
            end
            actions = {}
            for _, entry in ipairs(entries) do
                action = decide(provider, entry, available, reason, current, context)
                table.insert(actions, action)
                if provider.touches != nil and (action.kind == "add" or action.kind == "remove") then
                    table.insert(context.changing, provider.touches(entry.item))
                end
            end
            table.insert(groups, {name = name, provider = provider, actions = actions})
        end
    end
    return groups
end

SYMBOLS = {add = "+", remove = "-", ok = "=", conflict = "!"}

function engine.summary(groups)
    counts = {add = 0, remove = 0, ok = 0, conflict = 0}
    for _, group in ipairs(groups) do
        for _, action in ipairs(group.actions) do
            counts[action.kind] = counts[action.kind] + 1
        end
    end
    return counts
end

-- Prints changes and conflicts; with `verbose`, unchanged items too.
function engine.print_plan(groups, verbose)
    for _, group in ipairs(groups) do
        lines = {}
        for _, action in ipairs(group.actions) do
            if action.kind != "ok" or verbose == true then
                line = "  " .. SYMBOLS[action.kind] .. " " .. action.label
                if action.note != nil then
                    line = line .. "  (" .. action.note .. ")"
                end
                table.insert(lines, line)
            end
        end
        if #lines > 0 then
            print(group.name)
            for _, line in ipairs(lines) do
                print(line)
            end
        end
    end
    counts = engine.summary(groups)
    print(string.format("\n%d to add, %d to remove, %d unchanged, %d conflicts",
        counts.add, counts.remove, counts.ok, counts.conflict))
    return counts
end

function items_of(group, kind)
    items = {}
    for _, action in ipairs(group.actions) do
        if action.kind == kind then
            table.insert(items, action.entry.item)
        end
    end
    return items
end

-- Runs the plan: all removals (reverse order), then all additions.
-- Stops at the first failure; rerunning re-probes, so it picks up
-- where it left off.
function engine.apply(groups)
    counts = engine.summary(groups)
    if counts.conflict > 0 then
        print("Refusing to apply: resolve the conflicts marked ! first.")
        return false
    end
    index = #groups
    while index >= 1 do
        group = groups[index]
        items = items_of(group, "remove")
        if #items > 0 then
            print("== " .. group.name .. ": removing " .. #items)
            if group.provider.remove(items) != true then
                print("FAILED: " .. group.name .. " remove")
                return false
            end
        end
        index = index - 1
    end
    for _, group in ipairs(groups) do
        items = items_of(group, "add")
        if #items > 0 then
            print("== " .. group.name .. ": adding " .. #items)
            if group.provider.add(items) != true then
                print("FAILED: " .. group.name .. " add")
                return false
            end
        end
    end
    return true
end

return engine
