# seder

Puts an Ubuntu machine in order (Hebrew סדר, "order") from a declarative
description. You write down what should be on the machine; seder checks
what is actually there and changes only the difference. Removing
something that is not installed does nothing, on every machine, without
per-step guards.

seder is the engine. The description of a particular set of machines
lives in a separate data directory, the way daat is the engine and lims
is one deployment's data. Ben's machines are described in
[configs/seder](https://github.com/BenSiv/configs/tree/main/seder).

## Status

- **Plan / check / apply** with removals before additions -- done.
- **Providers:** apt (including .deb URLs), snap, npm, path, link, repo,
  dconf, run -- done (see [doc/providers.md](doc/providers.md)).
- **Tested** with unit tests and bats tests against stub tools; not yet
  run end to end on a fresh install (`dev/` holds a container for that).

## Building

Written in [Luam](https://github.com/BenSiv/luam); requires a sibling
`luam` checkout, already built (`obj/liblua.a` present). `bld/build.sh`
looks for it at `../luam`; override with `LUAM_DIR`.

```sh
./bld/build.sh          # -> bin/seder
```

## Testing

Requires `bats` on PATH (`apt install bats`).

```sh
./bld/test.sh
```

Runs the unit tests (`tst/unit/*.lua`) and the integration tests
(`tst/integration/*.bats`), which drive the built binary against a
scratch `$HOME` and stub package tools that log instead of installing.

## CLI

```
seder plan  [machine.lua] [-v]   # what apply would change (-v: unchanged items too)
seder check [machine.lua]        # exit 2 when anything would change
seder apply [machine.lua] [-y]   # show the plan, confirm, apply
seder --version                  # e.g. "seder 0.2.0 (485007a)": version and build commit
```

`machine.lua` defaults to `machines/<hostname>.lua` under the current
directory. A data directory looks like:

```
machines/laptop.lua    -- vars and the bundles this machine uses
bundles/base.lua       -- what should be present or absent, by provider
bundles/gnome.lua
```

```lua
-- machines/laptop.lua
return {
    requires_seder = "0.2.0",   -- older seders refuse with "update seder"
    vars = {projects = "~/Projects", configs = "${projects}/configs"},
    bundles = {"base", "gnome", "dev"},
}

-- bundles/gnome.lua
return {
    apt = {present = {"gnome-tweaks"}, absent = {"thunderbird"}},
    snap = {absent = {"firefox"}},
    link = {present = {{path = "~/.bashrc", target = "${configs}/bash/bashrc.sh"}}},
}
```

How planning, ordering and validation work: [doc/architecture.md](doc/architecture.md).
Every provider and its fields: [doc/providers.md](doc/providers.md).
