# Working on the plugin

Omarchy clones this repository and loads the QML its manifest names. Corgi
ships none of it.

## Talking to Corgi

The widget runs Corgi's binary at
`~/.local/share/corgi/releases/$(cat ~/.local/share/corgi/current)/corgi`,
since the shell's PATH may not include `~/.local/bin`:

- `corgi watch --json` stays running and prints the agents as one JSON line
  per change. The bar and the agent list draw from it.
- `corgi usage --json` prints each account's usage when the panel opens.
- `raise.sh` finds Corgi's window with `corgi list --json` and
  `hyprctl clients -j`, then drives it with `corgi focus`,
  `corgi workspace switch` and `corgi action new-agent`.

Corgi updates itself, so the widget has to work with releases newer than the
one it shipped with: unknown fields and values are ignored, never errors.
Nothing writes under the plugin folder, because Omarchy reloads the plugin
on any write there.

## Installing Corgi

`install.sh` is Corgi's own installer, built from
[`scripts/install.sh.in`](https://github.com/tals/corgi/blob/main/scripts/install.sh.in)
and pinned to a Corgi release by each plugin release. Don't edit it here.

Enabling the plugin without Corgi opens a terminal that runs it and then
becomes Corgi. Corgi installs to `~/.local/share/corgi`, outside the plugin
folder. When `omarchy plugin remove` deletes the folder, a Corgi the plugin
installed uninstalls itself, keeping sessions and settings. A Corgi you
installed yourself is used as is and stays.

## The QML folder

The shell caches compiled QML by path until it restarts, and Omarchy's
plugin reload doesn't clear that cache. So the QML lives in `qml-<hash>/`,
named for its content: an update brings a path the shell has never loaded,
and takes effect without a restart. After changing anything in it, run
`tools/rehash` and commit the renamed folder with the manifest. The harness
(`test/run.sh`) fails while the name is stale.

`qml-<hash>/corgi/` is Corgi's animation code, compiled for Qt from a Corgi
checkout by `tools/motion-build.ts`. Releases rebuild it; don't edit it here.

## Commands

```sh
bun test test                          # unit tests
test/run.sh <omarchy-checkout>         # the widget in Quickshell on headless sway (Docker)
bun tools/sandbox.ts                   # serve this checkout to an Omarchy VM over your tailnet
./tools/release-plugin [--test]        # release, or publish a test build
```
