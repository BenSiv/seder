# Architecture

## Layers: data, config, code

| Layer | Where | What |
|---|---|---|
| Data | `bundles/*.lua` in the data directory | What should be present or absent, grouped by topic |
| Config | `machines/*.lua` in the data directory | One machine: its variables and which bundles it uses |
| Code | this repo, `src/` | The engine and one provider per kind of resource |

The data directory lives outside this repo (Ben's is `configs/seder`),
like a daat deployment's schemas live in the deployment repo, not in daat.

## Files are data

Machine and bundle files run in luam's data-only sandbox
(`sandbox.data_env()`, the same one daat uses for `platform.lua` and
schemas): no `os`, `io` or `require`. Each must return a table.
`src/loader.lua` then checks every item against the provider that owns
it -- unknown fields, wrong types, missing required fields, states the
provider doesn't support, and provider-specific checks (`validate`) --
before anything touches the machine.

Strings are expanded once at load time: `${name}` from the machine's
`vars` (plus built-in `home`, `user` and `uid`; an unknown name is an error),
then a leading `~/` to `$HOME/`. Vars may refer to each other.

The same resource wanted `present` in one bundle and `absent` in another
is an error naming both files.

## Plan

`src/engine.lua` walks providers in a fixed order (`PROVIDER_ORDER`:
apt, snap, npm, path, repo, link, dconf, run). For each provider with items:

1. `available()` -- is its tool on the machine?
2. `state(entries)` -- one probe for all items (one `dpkg-query`, one
   `snap list`, ...).
3. `status(item, current, wanted)` per item -> present / absent / conflict.

Each item becomes `add`, `remove`, `ok` or `conflict`. When the tool is
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

## Why not Ansible

seder replaced an Ansible playbook whose cleanup tasks ("remove npm
package X", "remove snap Y") each assumed something about the machine and
failed on a fresh install. Ansible could be made to work with a guard on
every such task, but the next task written could forget its guard. Here
the guard is the engine: there is no way to write a removal that runs
when the thing is absent.
