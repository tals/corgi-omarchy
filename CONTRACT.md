# Corgi for Omarchy: working contract

Temporary design notes shared by the pieces being built in parallel. Fold
into real docs once it works.

## Plugin repository (what `omarchy plugin add` clones)

```
manifest.json       id "corgi.computer", kinds ["bar-widget"], entryPoints.barWidget "qml-<hash>/Widget.qml"
qml-<hash>/         what the shell loads, in a folder named for its content (tools/rehash):
  *.qml               the widget and its panel
  raise.sh            brings Corgi's window forward (see Open Corgi)
  corgi.png, icons/   Corgi's corgi and the providers' brand marks
  corgi/              Corgi's animation code, one module per source file, built from a Corgi checkout (see HACKING.md)
install.sh          the pinned installer, generated per Corgi release. Never edit by hand.
README.md, LICENSE
tools/rehash        renames qml-<hash>/ after a change to it
test/               the harness (test/run.sh); not used by the shell
```

This repository is the plugin's source: the QML here is what the bar runs.
Corgi itself knows nothing of it beyond the commands below.

The plugin folder is `~/.config/omarchy/plugins/corgi.computer/` once added.
QML finds it with `Qt.resolvedUrl(".")`. Omarchy hot-reloads the plugin
whenever any file under that folder is written (its watcher has no excludes
a plugin can set), so neither the QML nor Corgi writes there.

Qt keeps compiled QML by path, and Omarchy's in-place reload may not clear
that cache, so a plugin update can leave the old code running until the shell
restarts. Unverified whether that's Omarchy's doing or ours; see HACKING.md.

## Paths

- Install root: `~/.local/share/corgi`, where Corgi's installer puts it on
  every Linux; outside the plugin folder.
- Installed when `~/.local/share/corgi/current` exists. It holds the active
  version, a plain name (`[A-Za-z0-9][A-Za-z0-9._+-]{0,127}`). Until it
  does, the widget waits for it with `inotifywait` (which Omarchy's own
  plugin watcher runs) on the nearest folder that exists.
- Corgi binary: `~/.local/share/corgi/releases/$(cat ~/.local/share/corgi/current)/corgi`
  (the shell's PATH may not include `~/.local/bin`, so use this path).

## Install (first enable while not installed)

Enabling a fresh plugin checkout opens a tiled terminal that installs and
then becomes Corgi:

```
omarchy-launch-terminal env CORGI_INSTALL_PLUGIN=<plugin> CORGI_INSTALL_START=1 bash <plugin>/install.sh
```

`CORGI_INSTALL_PLUGIN` makes it a normal install that records the plugin
folder, so Corgi goes when the plugin does. `CORGI_INSTALL_START=1` makes
the installer start Corgi in onboarding as soon as it's installed, with no
button to press. Run it detached
(`Quickshell.execDetached`); `omarchy-launch-terminal` already uses setsid.

`open_installer.sh <plugin> --once` claims a marker in the plugin's state directory,
outside its watched checkout. All monitors and shell reloads share it;
adding a new checkout gets a new marker. An existing installation skips the
automatic launch. Clicking the corgi can reopen the installer after it was
closed, using the same script without `--once`.

## Open Corgi (click while installed)

`raise.sh <corgi-binary>` brings forward the viewer used last that has a
window. It reads the viewers from `<corgi-binary> list --json` (each one's
`id`, `pid` and `active`, a counter that grows with use) and the windows
from `hyprctl clients -j`; a viewer's window is the one whose process is the
viewer's or its nearest ancestor's, the terminal it runs in. It focuses that
window as `omarchy-hyprland-focus-app` does. With no viewer that has a window
(or no Corgi running), it runs `omarchy-launch-terminal <corgi-binary>` to
attach a new viewer. The whole panel header does this, or installs Corgi
when it isn't yet.

## New tab (a workspace's + button)

`raise.sh <corgi-binary> new-tab <id>` picks the viewer as above, then runs

```
<corgi-binary> workspace switch <id> --viewer <viewer> && <corgi-binary> action new-agent --viewer <viewer>
```

and focuses its window: the workspace, with Corgi's new-tab picker open.
Corgi releases before `action` took `--viewer` read it as the action's value,
which `new-agent` ignores, and open the picker in a viewer of their choosing.

## Counts and folds (no Corgi involved)

The header's counts (waiting on you, at work, unread) filter the list to
their kind: pointing at one previews it, a click keeps it, a click on the
kept one drops it. Workspaces and sections fold from their headings, and a
long idle section shows its latest two under a "… N more" row. Folds are kept
in `$XDG_STATE_HOME/omarchy/corgi.computer/panel.json` (by workspace id and
section kind), where Omarchy keeps its own plugins' state: outside the plugin
folder, so writing it doesn't reload the plugin.

## Live state: `corgi watch --json`

Long-lived. Prints one JSON object per line: once at start, then whenever the
summary changes. It never polls the daemon; the daemon pushes changes. It
reconnects by itself when the daemon restarts or hands off to a new release.
The QML runs it as a `Process` with a `SplitParser` and restarts it a second
after it exits.

Not running (no daemon on the socket):

```json
{"running": false}
```

Running:

```json
{
  "running": true,
  "counts": { "agents": 5, "working": 2, "needs_input": 1, "ready": 1, "idle": 1, "done": 1, "unread": 1 },
  "workspaces": [
    {
      "id": 1,
      "name": "api",
      "links": [{ "url": "http://localhost:3000", "label": "API preview" }],
      "pointer": "API preview ↗",
      "agents": [
        {
          "pane": 12,
          "headless": null,
          "title": "Fix the login redirect",
          "provider": "claude",
          "starred": false,
          "section": "working",
          "needs_input": false,
          "unread": false,
          "status": "working",
          "detail": "Reading auth.ts"
        }
      ]
    }
  ]
}
```

- `section` is Corgi's agent-list section: `working`, `ready` (finished,
  waiting for you to look), `idle` or `done`. An agent waiting on the user is
  `working` with `needs_input: true`, as in Corgi's sidebar.
- `starred` agents are listed above the sections, as in Corgi's sidebar;
  `section` still says which one their state puts them in. Older watch
  output omits it; the widget treats that as false.
- `counts.needs_input` and `counts.unread` overlap the section counts.
- Agents are in the order Corgi's sidebar sorted by activity lists them: the
  starred, then `working`, `ready`, `idle` and `done`, each section in the
  order the user dragged it into, the agent that entered it last on top. The
  panel draws those sections, each under a header unless it is the
  workspace's only one, which the heading names. Older watch output uses the
  hand-sorted order instead; the widget sorts it by section, keeping that
  order within each.
- `links` contains the workspace's detected browser URLs and their labels,
  using the same URL selection and deduplication as Corgi's sidebar. A label
  is empty until one is available. Older watch output omits `links`; the
  widget treats that as an empty list. Links and label changes arrive on
  the existing watch stream.
- `pointer` is the link button Corgi's sidebar draws on the workspace's row:
  the links' shared name or "Open Link", then `↗`, then their count when
  there are several ("API preview ↗", "Open Link ↗ 2"). Empty with no links.
- `status` is what the agent's glyph says in Corgi's sidebar, and `detail` is
  its row's second line (empty when the sidebar shows none):

  | status        | glyph | color                               |
  |---------------|-------|-------------------------------------|
  | `working`     | ▶     | accent, bold                        |
  | `needs_input` | ●     | urgent (Corgi's warm), bold         |
  | `retrying`    | ‖     | warm, bold: held until Corgi retries its failed turn; counts as working |
  | `ready`       | ●     | accent, bold; the title is bold too |
  | `paused`      | ‖     | accent if `unread`, else muted      |
  | `starting`    | ◌     | muted                               |
  | `idle`        | ○     | muted                               |
  | `done`        | ○     | faint                               |
  | `other`       | ·     | faint                               |

## Open a link

A workspace's heading carries its `pointer` on the right. With one link it
opens that link; with several it lists them, one line each, under the
heading: a link's label, or its host when it has none. Opening a link runs
`omarchy-launch-browser <url>` and closes the panel. The URL is passed as a
separate argument. Labels and workspace names render as plain text.

## Focus an agent (click on an agent row)

`raise.sh <corgi-binary> focus <pane>` picks the viewer as above, runs
`<corgi-binary> focus <pane> --viewer <viewer>` and focuses its window. A
headless agent has no pane, so its row opens Corgi.

These run detached (a plugin reload mustn't cut them short), at the click,
never polled, each Corgi command under a 10-second `timeout`.

## Removal and updates

Handled by Corgi, not the QML; Omarchy runs nothing of a plugin's on
removal. A Corgi the plugin installed watches the plugin folder with
inotify. When `omarchy plugin remove` takes it (deleted, or moved to a
backup), the daemon tells viewers (the corgi walks off), saves, and
uninstalls itself as `install.sh uninstall` does, keeping sessions and
settings. A Corgi you installed yourself stays. The widget only notices
`current` go, and is back to install.

The plugin and Corgi update separately. `omarchy plugin update` pulls this
repository: new QML, and maybe a new pin in `install.sh`, which only picks
the Corgi a fresh install starts with. Corgi updates itself from its release
channel, like any install. Nothing it writes is under the plugin folder, so
an update no longer reloads the plugin. The QML must cope with a Corgi newer
than the pin it shipped with: treat unknown fields and values as absent,
never as errors.

## Usage: `corgi usage --json`

One-shot. The panel runs it when it opens (and may again while it stays
open, no more than once a minute); the bar never runs it. It prints one JSON
object and exits. It reads the daemon's cached account readings and never
makes the daemon read a provider. Accounts arrive in Manage agents' order,
with one entry per subscription. `shared` lists other folders or harnesses
using that subscription (for example, Pi signed in through ChatGPT).

Current Corgi sends raw readings and history:

```json
{
  "running": true,
  "accounts": [{
    "provider": "codex",
    "name": "",
    "email": "you@example.com",
    "plan": "Pro",
    "shared": [{ "provider": "pi", "name": "" }],
    "limits": { "windows": [
      { "minutes": 300, "used": 42, "reset_at": 1793880000 },
      { "minutes": 10080, "used": 31, "reset_at": 1794312000 }
    ] },
    "history": [[10, 20, null], [20, 31, null]],
    "spend": null,
    "spend_history": [],
    "usage_fetched_at": 1793872800,
    "usage_error": ""
  }]
}
```

`limits` can also be `"none"`, `"metered"` or `"rate_limited"`. Its windows
and their histories remain in provider order. Percentages can exceed 100;
null history cells are gaps. The panel puts the longer window first and
clips spark heights to 100 without changing the percentage figure.

`spend` contains `used_minor`, nullable `limit_minor`, nullable `currency`
(null means credits), `exponent`, `period_start` and `reset_at`.
`spend_history` contains `{day, period_start, used_minor}` daily readings;
`day` is UTC midnight in Unix seconds, as are the other timestamps. The
panel uses the current billing period's readings and formats amounts itself.
Readings at least 20 minutes old draw gray; an expired billing period has
no monthly group. `{"running": false, "accounts": []}` means no daemon.

`usage.mjs` converts this data to the display groups below. Account names,
provider, email, plan and shared subscriptions come from the raw report.

- `windows` are two slots, as in Manage agents: the longer limit first and
  the 5h second, a lone 5h keeping the second slot, so every account's
  columns line up. An account with limits shows them; a `metered` one (an
  API key, or a workspace on credits: the enterprise case) shows its month
  instead, `mo` in the first slot, with `amount` in the second. Never both.
- Each window draws as a group: `label`, its spark, `figure`, then `reset`,
  the time until it resets. The figure keeps the text color, regular
  weight, until 80%, then turns warm (`#e5c38b`), and hot (`#eda398`) at
  100%. A rule stands between two groups. Columns are shared by every
  account, resets sized for "23h 59m" so they hold still as they tick.
- `bars` is the usage card's spark, exactly 14 bars: a window's from its
  start to its reset, and a month's spend from the billing period's start
  to its reset. `used` is a bar's height as a percent (0 to 100) of the full
  height: of the window, of the spend's limit, or of the tallest bar when
  the spend has no limit; null for `remaining` and `unread`. Draw it as the
  usage card does: on a panel as tall as a full bar, a reading at least an
  eighth tall, and a bar with no reading stippled in its tone's color, so
  low usage reads as low rather than as progress. `tone`:

  | tone        | meaning                                  | color                   |
  |-------------|------------------------------------------|-------------------------|
  | `accent`    | a reading under 80%                      | accent `#7bf1a8`; one, two or three eighths tall fade 75%, 45%, 15% toward faint |
  | `warm`      | 80% or more                              | warm `#e5c38b`          |
  | `hot`       | at the limit                             | hot `#eda398`           |
  | `earlier`   | spend before this month began            | accent 60% toward faint |
  | `stale`     | a reading too old to trust               | faint `#83909e`         |
  | `remaining` | time not yet elapsed in the window       | Corgi's line `#505a65`  |
  | `unread`    | elapsed, but Corgi has no reading for it | `#3a414a`               |

  Theme overrides from `[corgi]` in `shell.toml` (accent, warm, hot) apply.
- `amount` is the month's spend: "$12.34 / $50", spend alone when the
  provider reports no limit, or workspace credits as "⛁388 / ⛁250k", never
  dollars.

Brand icons: the panel ships `icons/<provider>.svg` for claude, codex,
opencode, omp and pi (from the site's icons), beside its QML. Use them for
each account's heading, for `shared`, and in place of a provider's name in
agent rows.
