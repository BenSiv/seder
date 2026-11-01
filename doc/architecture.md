# Architecture

## Layers: data, config, code

| Layer | Where | What |
|---|---|---|
| Data | `bundles/*.lua` in the user's configuration | What should be present or absent, grouped by topic |
| Config | `machines/*.lua` in the user's configuration | One machine: its variables and which bundles it uses |
| Code | this repo, `src/` | The engine and one provider per kind of resource |

The configuration is not part of this repo. Users keep it wherever they
like and pass seder the path to a machine file; bundles are read from the
`bundles/` folder next to that file's `machines/` folder.

## Files are data

Machine and bundle files run in luam's data-only sandbox
(`sandbox.data_env()`): no `os`, `io` or `require`. Each must return a table.
`src/loader.lua` then checks every item against the provider that owns
it -- unknown fields, wrong types, missing required fields, states the
provider doesn't support, and provider-specific checks (`validate`) --
before anything touches the machine.

Strings are expanded once at load time: `${name}` from the machine's
`vars` (plus built-in `home`, `user` and `uid`; an unknown name is an error),
then a leading `~/` to `$HOME/`. Vars may refer to each other.

The same resource wanted `present` in one bundle and `absent` in another
is an error naming both files.

## Versions

`src/version.lua` holds seder's version, and `bld/build.sh` records the
commit it builds from, so `seder --version` describes the binary itself
rather than whatever the checkout says. The minor number goes up whenever
data files gain something an older seder can't read (a provider, a field,
a built-in var). A machine file declares the oldest seder that reads it
with `requires_seder = "0.2.0"`, which is checked before anything else, so
data written for a newer seder fails with "needs seder 0.2.0 or newer"
instead of an error about the feature it uses.

## Plan

`src/engine.lua` walks providers in a fixed order (`PROVIDER_ORDER`:
apt, dnf, pacman, snap, flatpak, npm, path, repo, link, dconf, run). For each provider with items:

1. `available()` -- is its tool on the machine?
2. `state(entries)` -- one probe for all items (one `dpkg-query` or
   `rpm -qa`, one `flatpak list`, ...).
3. `status(item, current, wanted)` per item -> present / absent / conflict.

Each item becomes `add`, `remove`, `ok` or `conflict`. Providers that
change a path when they act (`repo`) say so through `touches`; those paths
are passed on to later providers, so a build whose sources are being pulled
in this run is planned as a rebuild now, not discovered on the next run. When the tool is
missing, `absent` items are `ok` (nothing of that kind can be installed)
and `present` items are `add`, left to apply because an earlier step may
install the tool.

## Apply

1. Refuse if any item is a conflict.
2. All removals, providers in reverse order: npm packages go before npm
   itself, links before the packages they point into.
3. All additions, providers in order: packages before the checkouts,
   links and builds that need them.

Apply stops at the first failed command. Rerunning plans again from the
machine's current state, so it continues where it stopped.

seder runs as the user. System changes go through `sudo`; anything under
`$HOME` does not. Every command goes through `src/shell.lua`, which is
also what lets the integration tests replace the real tools with stubs.

## Compared with Ansible

Ansible describes changes as tasks, and a cleanup task ("remove npm
package X", "remove snap Y") assumes the thing is there; on a fresh
install it fails unless it carries its own guard, and each new task can
forget one. seder has no tasks, only states: the engine compares each
item with the machine before planning, so a removal of something absent
cannot run. In exchange seder does far less: one local machine, no
inventory or remote execution, and only the providers listed in
[providers.md](providers.md).
