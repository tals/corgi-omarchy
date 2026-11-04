# Working on the plugin

This repository is the plugin: Omarchy clones it and runs the `Widget.qml`
its manifest names, in `qml-<hash>/`. Corgi doesn't ship any of it. The QML talks to Corgi only through
the commands in [CONTRACT.md](CONTRACT.md) (`corgi watch --json`,
`corgi usage --json`, `corgi list --json`, `corgi focus`), and has to keep working
with Corgi releases newer than the one `install.sh` pins.

## Try a change in an Omarchy VM

The sandbox tool lives in the Corgi checkout. It serves the plugin to the VM
over your tailnet, with `install.sh` pinned to a sandbox build of Corgi:

1. Edit the QML in `qml-<hash>/`.
2. In the Corgi checkout, run `bun tools/omarchy_sandbox.ts plugin`. It
   publishes this checkout's working tree, uncommitted edits included, with
   the sandbox pin. (Run `bun tools/omarchy_sandbox.ts` once first to build
   Corgi and start serving.)
3. In the VM, run `omarchy plugin update corgi.computer`.

To try a new Corgi, run `bun tools/omarchy_sandbox.ts channel`, which
publishes a release to the sandbox channel, and then `corgi update` in the
VM: Corgi updates itself, as any install does. `bun tools/omarchy_sandbox.ts
build` also moves the pin, which only matters to a fresh install.

Corgi installs to `~/.local/share/corgi`, outside the plugin folder:
Omarchy reloads a plugin on any write under its folder, and its watcher has
no excludes a plugin can set.

The first time, add the plugin in the VM with
`omarchy plugin add https://<this machine>:8443/corgi.computer.git --enable`.
The sandbox tool prints the exact URL.

## The QML folder

The shell keeps compiled QML by path for as long as it runs, and Omarchy's
plugin reload doesn't clear it (it calls `Qt.clearComponentCache()`, which
QML doesn't have). New QML at a path the shell has loaded keeps running the
old code until the shell restarts. So the QML lives in a folder named for its
content: after changing anything in it, run `tools/rehash`, which renames the
folder and points the manifest at it, and commit both. An update then brings
code the shell has never loaded, and takes effect without a restart. The
harness fails while the name is stale. The sandbox tool names the folder
itself, so trying a change in the VM needs no rehash.

## The harness

```sh
test/run.sh <omarchy-checkout> [<screenshot-dir>]
```

Runs `Widget.qml` and its panel through their states in Quickshell on
headless sway, using Omarchy's own `qs.Commons` and `qs.Ui` from the
checkout. A fake `corgi` (`test/fake/`) logs what the widget asks of it. It
needs Docker and builds its image once. It prints PASS/FAIL lines and ends
with `result: ok`. With a screenshot folder, it also writes contact sheets
of the bar and the panel.

## Corgi's animations

`corgi/` holds Corgi's sidebar animations: the activity glyph and the corgi
that walks along an agent's row. It's Corgi's own code, one module per Corgi
source file (each starts with its path there), compiled for Qt's QML engine;
`Card.qml` imports `corgi/motion.mjs`. Don't edit it here. `tools/motion.ts`
is this plugin's entry into it, importing Corgi's modules as `@corgi/NAME`
(`src/NAME.ts`), and `tools/qml_shims.js` fills in the builtins Qt's engine
lacks, which Corgi's code may use only through it. To refresh `corgi/` after
the animations or either file change, run this in a Corgi checkout:

```sh
bun tools/omarchy_motion.ts <this checkout>/tools/motion.ts <this checkout>/qml-<hash>/corgi
```

Then run `tools/rehash` and commit the result here. Only the files whose
source changed differ.
