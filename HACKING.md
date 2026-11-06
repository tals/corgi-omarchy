# Working on the plugin

This repository is the plugin: Omarchy clones it and runs the `Widget.qml`
its manifest names, in `qml-<hash>/`. Corgi doesn't ship any of it. The QML talks to Corgi only through
the commands in [CONTRACT.md](CONTRACT.md) (`corgi watch --json`,
`corgi usage --json`, `corgi list --json`, `corgi focus`), and has to keep working
with Corgi releases newer than the one `install.sh` pins.

## Release the plugin

```sh
./scripts/release-plugin
./scripts/release-plugin --test
```

Both use committed HEAD in a temporary checkout, obtain the matching Corgi source,
refresh animations, rehash the QML directory, and run the plugin tests. The normal
command incorporates remote main in that temporary checkout, then pushes only
when the resulting tree changed. Your working checkout is left alone.

Plugin-only releases keep the existing Corgi pin. When Corgi's publisher supplies
a new release, a newer binary alone does not advance that pin: installer behavior
or runtime assets must change. Corgi itself still follows its update channel.
Test releases use the latest test Corgi, falling back to the current pin
when no test channel exists. Their pins advance to the exact selected test build.

`--test` pushes a separate `test` branch and publishes a Git HTTP repository at
`https://corgi.computer/test/corgi.computer.git`, since Omarchy's add command takes
a repository URL without a branch option. Its output includes installation and
update commands. It uses the same bucket credentials as Corgi's publisher in
`~/.config/corgi/release.json` (or `CORGI_RELEASE_CONFIG`). A failed mirror upload
can be retried by running the command again; it does not rebuild Corgi.
On a sandbox with Corgi already installed, run the test channel's normal installer
once to switch channels; a plugin update preserves an existing Corgi installation.

Publishing needs Bun, Git, jq, and push access to `tals/corgi-omarchy` over SSH.
`CORGI_OMARCHY_REMOTE` overrides that remote; `CORGI_SOURCE_REMOTE` overrides the
read-only Corgi source remote. `--dry-run` prints the workflow without publishing.

Corgi's `./scripts/release` calls this same code automatically. It provides its
exact source checkout and generated installer through `CORGI_RELEASE_SOURCE` and
`CORGI_RELEASE_DIR`, with `CORGI_RELEASE_PHASE=prepare` before Corgi publication
and `publish` afterward. The prepared plugin commit is retained with Corgi's
release artifacts so `VERSION --publish-only` retries the same plugin revision.
The decision to keep a pin or skip a push belongs here.

## Try uncommitted changes in an Omarchy VM

The sandbox tool lives here. It serves the plugin to the VM
over your tailnet, with `install.sh` pinned to a sandbox build of Corgi:

1. Edit the QML in `qml-<hash>/`.
2. Run `CORGI_SOURCE=/path/to/corgi-worktree bun tools/sandbox.ts plugin`. It
   publishes this checkout's working tree, uncommitted edits included, with
   the sandbox pin. (Run `CORGI_SOURCE=/path/to/corgi-worktree bun tools/sandbox.ts` once first to build
   Corgi and start serving.)
3. In the VM, run `omarchy plugin update corgi.computer`.

To try a new Corgi, run `CORGI_SOURCE=/path/to/corgi-worktree bun tools/sandbox.ts channel`, which
publishes a release to the sandbox channel, and then `corgi update` in the
VM: Corgi updates itself, as any install does. `bun tools/sandbox.ts
build` also moves the pin, which only matters to a fresh install.

Corgi installs to `~/.local/share/corgi`, outside the plugin folder:
Omarchy reloads a plugin on any write under its folder, and its watcher has
no excludes a plugin can set.

The first time, add the plugin in the VM with
`omarchy plugin add https://<this machine>:8443/corgi.computer.git --enable`.
The sandbox tool prints the exact URL.

The sandbox's files and signing key remain under the selected Corgi checkout's
common Git directory, so moving this tool does not invalidate existing sandbox
installs. Without `CORGI_SOURCE`, it uses the sibling `corgi` checkout. Public test
releases use Corgi's `./scripts/release --test` instead of this local sandbox tool.

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
bun test test
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
lacks, which Corgi's code may use only through it. Release commands refresh these
automatically. To regenerate them while developing, run this here:

```sh
bun tools/motion-build.ts /path/to/corgi-worktree tools/motion.ts qml-<hash>/corgi
```

Then run `tools/rehash` and commit the result here. Only the files whose
source changed differ.
