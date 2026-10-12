-- seder's version. Bump the minor number whenever data files gain
-- something an older seder can't read (a provider, a field, a built-in
-- var), so machine files can require it with `requires_seder`.
--
--   0.1.0  apt, snap, npm, path, repo, link, run
--   0.2.0  dconf provider; built-in ${uid}; requires_seder
--   0.3.0  run `sources` (rebuild when stale); --pull for repos
--   0.4.0  flatpak, dnf and pacman providers

version = {number = "0.4.0"}

-- The commit the binary was built from; bld/build.sh writes
-- src/build_commit.lua (untracked). A run from source has none. The
-- require stays literal so luam's static bundler finds the module.
ok, commit = pcall(function() return require("build_commit") end)
if ok == true and type(commit) == "string" then
    version.commit = commit
end

function version.parse(text)
    major, minor, patch = string.match(text, "^(%d+)%.(%d+)%.(%d+)$")
    if major == nil then
        return nil
    end
    return {tonumber(major), tonumber(minor), tonumber(patch)}
end

-- True when this seder is at least `wanted` ("major.minor.patch").
function version.satisfies(wanted)
    have = version.parse(version.number)
    want = version.parse(wanted)
    for index = 1, 3 do
        if have[index] != want[index] then
            return have[index] > want[index]
        end
    end
    return true
end

function version.describe()
    if version.commit == nil then
        return "seder " .. version.number
    end
    return "seder " .. version.number .. " (" .. version.commit .. ")"
end

return version
