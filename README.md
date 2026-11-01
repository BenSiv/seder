# seder

Puts a Linux machine in order (Hebrew סדר, "order") from a declarative
description. You write down what should be on the machine; seder checks
what is actually there and changes only the difference. Removing
something that is not installed does nothing, on every machine, without
per-step guards.

seder is only the engine. The configuration is yours: write it wherever
you like (its own repo, a dotfiles repo, a USB stick) and point seder at
it when you run it.

## Status

- **Plan / check / apply** with removals before additions -- done.
- **Providers:** apt, dnf, pacman (each with package-file URLs), snap,
  flatpak, npm, path, link, repo, dconf, run. Nothing in the engine assumes a
  distribution; data picks the providers its machines have -- done (see [doc/providers.md](doc/providers.md)).
- **Tested** with unit tests and bats tests against stub tools; not yet
  run end to end on a fresh install (`dev/fresh.sh` runs one in a container
  of any distribution).

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
... --pull                       # also fast-forward clean checkouts; stale builds rerun
seder --version                  # e.g. "seder 0.2.0 (485007a)": version and build commit
```

## Configuration

A configuration is a directory with two folders side by side:

```
machines/laptop.lua    -- one machine: its vars and the bundles it uses
bundles/base.lua       -- what should be present or absent, by provider
bundles/desktop.lua
```

Pass the machine file to any command (`seder plan path/to/machines/laptop.lua`);
its bundles are read from the `bundles/` folder next to `machines/`. With
no argument, seder looks for `machines/<hostname>.lua` in the current
directory, so running it from inside the configuration needs no path.

```lua
-- machines/laptop.lua
return {
    requires_seder = "0.2.0",   -- older seders refuse with "update seder"
    vars = {dotfiles = "~/dotfiles"},
    bundles = {"base", "desktop"},
}

-- bundles/desktop.lua
return {
    apt = {present = {"gnome-tweaks"}, absent = {"thunderbird"}},
    snap = {absent = {"firefox"}},
    link = {present = {{path = "~/.bashrc", target = "${dotfiles}/bashrc"}}},
}
```

## Compared with Ansible

seder covers a small slice of what tools like Ansible do: one local
machine, run as its user, no inventory, no remote hosts, no modules
beyond its providers. The difference in that slice is that every item is
a state, not a task. A removal of something already absent is planned as
"ok" and never runs, so a configuration written against an old machine
also applies cleanly to a fresh install, with no per-task guards.

How planning, ordering and validation work: [doc/architecture.md](doc/architecture.md).
Every provider and its fields: [doc/providers.md](doc/providers.md).
