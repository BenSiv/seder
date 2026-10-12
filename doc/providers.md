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
| `dconf` | `key` | `value` | `dconf write` | `dconf reset` |
| `repo` | `path` | `url` | clone; with `--pull`, fast-forward | not supported |
| `run` | `name` | `cmd`, `dir`, `env`, `sudo`, `creates` or `unless`, `sources` | run `cmd` | not supported |

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

**dconf.** `value` is GVariant text as `dconf read` prints it: `'prefer-dark'`,
`['a', 'b']`, `@as []`. Only listed keys are managed. Plain numbers compare
numerically, since dconf prints doubles with 17 digits (`0.6` reads back as
`0.59999999999999998`). Writes go through the logged-in desktop session's
D-Bus: when `DBUS_SESSION_BUS_ADDRESS` is unset (ssh, a tmux started
elsewhere), dconf uses `$XDG_RUNTIME_DIR/bus` (`/run/user/<uid>/bus`), and
without a session it fails with a message saying so. Don't declare keys GNOME shares with the
system, like `/org/gnome/shell/enabled-extensions` (Ubuntu's own
extensions are in it); use a guarded `run` item with the tool that edits
it instead.

**repo.** Clones with `--recurse-submodules` when missing; an existing
non-empty directory that isn't a checkout is a conflict. Without `--pull`
an existing checkout is left as it is. With `--pull` the plan fetches it
and, when it is behind its upstream, fast-forwards it (submodules follow)
-- but only if the branch has an upstream, no local commits and no changes
to tracked files. Otherwise it is left alone and `plan -v` says why
(`1 behind origin/main, local changes; not updated`).

**run.** For steps no other provider covers (builds, luarocks, locale).
Each item must say how to tell it is done: `creates`, a path that exists
afterwards (apply fails if the command ran but didn't create it), or
`unless`, a check command that exits 0 when done. An unguarded command
would run on every apply, so the loader rejects it. `unless` runs without
sudo even for `sudo = true` items.

A build can list `sources`, paths inside git checkouts, to be rebuilt when
they change: it is stale when a git-tracked file under them is newer than
`creates` (make's rule; build outputs are untracked so they don't count),
or when a source lies in a checkout this plan clones or pulls. List the
inputs that end up in the output -- for a luam project, its own `src` and
`bld` plus luam's `src` and `lib`.

## Adding a provider

Create `src/providers/<name>.lua` returning a table with:

- `key` -- the field that identifies an item.
- `fields` -- field name -> type (`"string"`, `"boolean"`, `"table"`).
- `required` -- state -> list of required fields.
- `states` -- which of `"present"`/`"absent"` it supports.
- `available()` -> `true`, or `false` and a reason shown in the plan.
- `state(entries, context)` -> one probe, passed to `status`.
- `status(item, current, wanted, context)` -> `"present"`, `"absent"` or
  `"conflict"`, plus an optional note. `context.options.pull` is the
  `--pull` flag; `context.changing` lists paths earlier providers change.
- `touches(item)` (optional) -> the path an add or remove of this item
  changes, so builds with sources under it count as stale in the same plan.
- `add(items)` / `remove(items)` -> `true` on success. Run commands
  through `shell.run` so they are echoed and can be stubbed in tests.
- optional `validate(item, state)` -> error string or `nil`.

Register it in `engine.providers` and place it in `PROVIDER_ORDER`
(`src/engine.lua`), then add bats coverage in `tst/integration/`.

## Not covered

- Stopping systemd units and removing system accounts: one-off cleanup
  rather than a state to keep, so done by hand where needed.
- Global git settings: link a tracked gitconfig to `~/.gitconfig`
  instead of declaring keys one by one.
