# Providers

Each bundle maps provider names to `{present = {...}, absent = {...}}`.
An item is a string (the provider's key field) or a table of fields.

| Provider | Key | Fields | present | absent |
|---|---|---|---|---|
| `apt` | `name` | `url`: install a .deb from this URL | install | purge |
| `snap` | `name` | `classic`, `channel` | install | remove |
| `npm` | `name` | | `npm install -g` | `npm uninstall -g` |
| `path` | `path` | | `mkdir -p` | `rm -rf` |
| `link` | `path` | `target` | symlink | remove the symlink |
| `repo` | `path` | `url` | `git clone --recurse-submodules` | not supported |
| `run` | `name` | `cmd`, `dir`, `env`, `sudo`, `creates` or `unless` | run `cmd` | not supported |

## Details

**apt.** Packages wanted but missing from the apt cache are noted in the
plan, so a renamed package shows before apply. `apt-get update` runs once
before the first install.

**snap.** The first change waits for `snap wait system seed.loaded`: on a
fresh install snapd is still seeding after first boot and snap commands
block until it is done.

**npm.** Uses sudo only when the global prefix isn't writable by the user.

**path.** Removal is `rm -rf`, so a path must be absolute, at least two
levels deep, and never `$HOME` itself. `present` means a directory; a
file in the way is a conflict.

**link.** A real file or directory already at `path` (a fresh install's
own `~/.bashrc`) is moved to `<path>.orig`, never deleted. `absent`
removes only symlinks; a real file is left alone.

**repo.** Clones once and never pulls: a working copy may hold work in
progress. An existing non-empty directory that isn't a checkout is a
conflict.

**run.** For steps no other provider covers (builds, luarocks, locale).
Each item must say how to tell it is done: `creates`, a path that exists
afterwards (apply fails if the command ran but didn't create it), or
`unless`, a check command that exits 0 when done. An unguarded command
would run on every apply, so the loader rejects it. `unless` runs without
sudo even for `sudo = true` items.

## Adding a provider

Create `src/providers/<name>.lua` returning a table with:

- `key` -- the field that identifies an item.
- `fields` -- field name -> type (`"string"`, `"boolean"`, `"table"`).
- `required` -- state -> list of required fields.
- `states` -- which of `"present"`/`"absent"` it supports.
- `available()` -> `true`, or `false` and a reason shown in the plan.
- `state(entries)` -> one probe, passed to `status`.
- `status(item, current, wanted)` -> `"present"`, `"absent"` or
  `"conflict"`, plus an optional note.
- `add(items)` / `remove(items)` -> `true` on success. Run commands
  through `shell.run` so they are echoed and can be stubbed in tests.
- optional `validate(item, state)` -> error string or `nil`.

Register it in `engine.providers` and place it in `PROVIDER_ORDER`
(`src/engine.lua`), then add bats coverage in `tst/integration/`.

## Planned

What the Ansible setup did that no provider covers yet:

- `dconf` -- GNOME settings (needs the user's session bus).
- `git_config` -- global git settings.
- `service` -- stop and disable systemd units.
- `user` -- remove system accounts.
