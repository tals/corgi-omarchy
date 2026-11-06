pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "usage.mjs" as Usage

// Corgi in the bar: Corgi's corgi, with two small marks beside it for what
// its agents are doing, and a panel listing every workspace and agent, where a
// click lands you on the agent you picked.
//
// It has three states, all read from disk or from Corgi itself:
//
//   install   ~/.local/share/corgi/current is missing. The installer opens
//             on first enable; the corgi carries a download mark and a click
//             opens it again if it was closed.
//   stopped   Installed, but no daemon answers. The corgi dims, and a click
//             opens Corgi, which starts the daemon.
//   running   ▶ while an agent works, ● while one is ready (mint) or needs
//             input (amber), in Corgi's own colors. A click opens the panel.
//
// Live state comes only from `corgi watch --json`, a long-lived process that
// prints one JSON object per line whenever Corgi's summary changes. Nothing
// here polls: the process is restarted a second after it exits, and the
// release pin is a FileView that watches Corgi's `current`.
//
// Corgi installs where it always does, ~/.local/share/corgi, not in the
// plugin folder: Omarchy reloads the whole plugin whenever a file under its
// folder is written, so neither this nor Corgi ever writes there. Corgi that
// the plugin installed removes itself when `omarchy plugin remove` takes the
// plugin folder; this only notices `current` go.
//
// Agent titles, details and workspace names are whatever an agent or the user
// wrote, so every Text that shows one is `textFormat: Text.PlainText`. Left on
// AutoText, Qt decides for itself that a string looks like markup, and rich
// text loads `<img src="http://...">`.
Panel {
  id: root

  moduleName: "corgi.computer"
  ipcTarget: "corgi.computer"

  // ------------------------------------------------------------- paths

  // The plugin folder, wherever `omarchy plugin add` put it, from the
  // percent-encoded file:// URL the shell loaded this file from. The panel's
  // icons sit beside it, and so does the pinned installer.
  readonly property string qmlDir: decodeURIComponent(
    Qt.resolvedUrl(".").toString().replace(/^[a-z]+:\/\//, "")).replace(/\/+$/, "")
  // The plugin folder. As published, the QML sits in a folder named for its
  // content, qml-<hash>/, so an update is code the shell has never loaded:
  // Qt keeps compiled QML by path for the shell's life, and Omarchy's plugin
  // reload doesn't clear it. Run from a checkout, it sits in the plugin folder.
  readonly property string pluginDir: qmlDir.replace(/\/qml-[0-9a-f]{12}$/, "")
  readonly property string openInstaller: qmlDir + "/open_installer.ts"
  // Where Corgi's installer puts it on every Linux, outside the plugin folder.
  readonly property string corgiRoot: (Quickshell.env("HOME") || "") + "/.local/share/corgi"

  // The release Corgi's `current` names, once it has been read and looks like
  // one. It becomes part of a path, so anything else counts as not installed.
  property string release: ""
  readonly property bool installed: release !== ""
  // The binary itself rather than ~/.local/bin/corgi: the shell's PATH may not
  // include ~/.local/bin.
  readonly property string corgi: installed ? corgiRoot + "/releases/" + release + "/corgi" : ""

  // ------------------------------------------------------------ state

  // Whether the daemon answered, per the watch's last line. False until the
  // watch has said otherwise, and again whenever the watch is not running.
  property bool daemonRunning: false
  // Workspaces from the last line, normalized by applyLine().
  property var workspaces: []

  readonly property string mode: !installed ? "install" : (daemonRunning ? "running" : "stopped")

  // Every agent, workspace by workspace in agent-list order, for the counts.
  readonly property var agents: {
    var out = []
    for (var i = 0; i < workspaces.length; i++)
      for (var j = 0; j < workspaces[i].agents.length; j++)
        out.push(workspaces[i].agents[j])
    return out
  }

  readonly property int needsCount: countWhere(function(a) { return a.status === "needs_input" })
  readonly property int readyCount: countWhere(isReady)
  // Held for a retry is still at work.
  readonly property int workingCount: countWhere(function(a) { return a.status === "working" || a.status === "retrying" })

  // The bar's marks. Needs input and ready share the dot; urgent wins.
  readonly property bool workingMark: mode === "running" && workingCount > 0
  readonly property bool attentionMark: mode === "running" && (needsCount > 0 || readyCount > 0)
  readonly property color attentionColor: needsCount > 0 ? root.warm : root.accent

  // Each workspace's heading, with its link pointer as Corgi's sidebar has
  // it, then the links it lists when opened, then its agents in Corgi's
  // activity sections, each under its own header. The cursor and ListView
  // walk the same flat list; `rowMap` finds a row by its key.
  readonly property var rows: {
    var out = []
    for (var i = 0; i < workspaces.length; i++) {
      var ws = workspaces[i]
      out.push({ kind: "workspace", key: "w:" + ws.id, workspace: ws, agent: null, link: null, section: null })
      if (linksOpen === "w:" + ws.id && ws.links.length > 1)
        for (var j = 0; j < ws.links.length; j++)
          out.push({ kind: "link", key: ws.links[j].key, workspace: ws, agent: null, link: ws.links[j], section: null })
      for (var g = 0; g < ws.groups.length; g++) {
        var group = ws.groups[g]
        var fold = ws.id + ":" + group.kind
        out.push({ kind: "section", key: "s:" + ws.id + ":" + group.kind, workspace: ws, agent: null, link: null,
                   section: group, first: g === 0, fold: fold })
        // A long idle section shows its latest few; the rest wait under a
        // "… N more" row, unless it was opened.
        var spill = group.kind === "idle" && group.agents.length > idleShown + 1
        var open = isFolded("idle", ws.id)
        for (var j = 0; j < group.agents.length; j++)
          out.push({ kind: "agent", key: group.agents[j].key, workspace: ws, agent: group.agents[j], link: null,
                     section: group, fold: fold, folded: spill && !open && j >= idleShown })
        if (spill)
          out.push({ kind: "more", key: "m:" + ws.id, workspace: ws, agent: null, link: null, section: group,
                     fold: fold, count: group.agents.length - idleShown, open: open })
      }
    }
    return out
  }
  readonly property var rowMap: {
    var map = {}
    for (var i = 0; i < rows.length; i++) map[rows[i].key] = rows[i]
    return map
  }

  // ------------------------------------------------ folds and filters

  // Folded workspaces and sections, and idle sections opened past their
  // first few, by key. They're remembered across panels and shell restarts
  // in a small file beside Omarchy's own plugin state, never in the plugin
  // folder, which Omarchy reloads the plugin for.
  readonly property int idleShown: 2
  property var folds: ({ workspaces: [], sections: [], idle: [] })
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state")
    + "/omarchy/corgi.computer"
  function isFolded(list, key) {
    return folds[list].indexOf(String(key)) !== -1
  }
  function toggleFold(list, key) {
    var next = { workspaces: folds.workspaces.slice(), sections: folds.sections.slice(), idle: folds.idle.slice() }
    var at = next[list].indexOf(String(key))
    if (at === -1) next[list].push(String(key))
    else next[list].splice(at, 1)
    folds = next
    if (list === "workspaces" && linksOpen === "w:" + key) linksOpen = ""
    foldsFile.setText(JSON.stringify(next) + "\n")
  }
  FileView {
    id: foldsFile
    path: root.stateDir + "/panel.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var saved = {}
      try { saved = JSON.parse(text()) } catch (e) { saved = {} }
      var list = function(v) {
        return Array.isArray(v) ? v.filter(function(k) { return typeof k === "string" && k.length <= 160 }).slice(0, 500) : []
      }
      root.folds = { workspaces: list(saved && saved.workspaces), sections: list(saved && saved.sections),
                     idle: list(saved && saved.idle) }
    }
  }

  // The header's counts filter the list. Pointing at one previews its kind;
  // a click keeps it, and a click on the kept one drops it, previewing
  // nothing until the pointer comes back. A kind that runs out lets go.
  readonly property var kinds: ["needs", "working", "unread"]
  property string filterPinned: ""
  property string filterPreview: ""
  property string filterDismissed: ""
  readonly property string filterKind: filterPreview !== "" && kindCount(filterPreview) > 0 ? filterPreview
    : (filterPinned !== "" && kindCount(filterPinned) > 0 ? filterPinned : "")
  function kindTest(kind, a) {
    switch (kind) {
    case "needs": return a.status === "needs_input"
    case "working": return a.status === "working" || a.status === "retrying"
    default: return isReady(a)
    }
  }
  function kindCount(kind) {
    return kind === "needs" ? needsCount : (kind === "working" ? workingCount : readyCount)
  }
  function enterKind(kind) {
    if (filterDismissed !== kind) filterPreview = kind
  }
  function leaveKind(kind) {
    if (filterDismissed === kind) filterDismissed = ""
    if (filterPreview === kind) filterPreview = ""
  }
  function clickKind(kind) {
    if (filterPinned === kind) {
      filterPinned = ""
      filterDismissed = kind
    } else {
      filterPinned = kind
      filterDismissed = ""
    }
    filterPreview = ""
  }
  function settleFilter() {
    if (filterPinned !== "" && kindCount(filterPinned) === 0) filterPinned = ""
  }
  onNeedsCountChanged: settleFilter()
  onWorkingCountChanged: settleFilter()
  onReadyCountChanged: settleFilter()

  // Whether a row shows: a count's filter shows its kind wherever it is,
  // folded or not; otherwise folds and the idle spill hide what they hold.
  function rowShown(r) {
    if (!r) return true
    var kind = filterKind
    if (kind === "") {
      if (r.kind === "workspace") return true
      if (isFolded("workspaces", r.workspace.id) || r.folded) return false
      if (r.kind === "section" || r.kind === "link") return true
      return !isFolded("sections", r.fold)
    }
    var test = function(a) { return root.kindTest(kind, a) }
    switch (r.kind) {
    case "agent": return test(r.agent)
    case "section": return r.section.agents.some(test)
    case "workspace": return r.workspace.agents.some(test)
    default: return false
    }
  }

  // Corgi's activity sections, in the order its sidebar lists them, with the
  // glyph and color each header there has.
  readonly property var sectionOrder: ["starred", "working", "ready", "idle", "done"]
  readonly property var sectionGlyphs: ({ starred: "\u2605", working: "\u25b6", ready: "\u25cf", idle: "\u25cb", done: "\u25cb" })
  function sectionColor(kind) {
    switch (kind) {
    case "starred": return root.foreground
    case "working": return root.accent
    case "ready": return root.accent
    case "idle": return root.muted
    default: return root.faint
    }
  }

  // The workspace whose links are listed under its heading, or "".
  property string linksOpen: ""

  // The row under the keyboard cursor, by key rather than by index, so a
  // fresh line from the watch that reorders the list leaves it where it was.
  // Empty is the panel header's button.
  property string cursorKey: ""

  // ----------------------------------------------------------- theme

  // Omarchy's ease-out curve; older builds have no Style.easeOut.
  readonly property var easeOut: Style.easeOut || [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  // Corgi's own state colors, as its sidebar draws them: mint for working and
  // finished, amber for an agent waiting on you. Omarchy themes carry neither,
  // so these are Corgi's; a theme can set `accent` and `warm` under [corgi] in
  // its shell.toml. On a light bar, where mint and amber wash out, both deepen.
  readonly property bool lightBar: foreground.hslLightness < 0.5
  // Whether the shell animates: Omarchy turns its animations off with
  // Hyprland's, as it does in a VM. Without them nothing may jump, so the
  // corgi and its marks keep fixed places and an empty dot holds the dot's.
  readonly property bool motion: Style.duration(100) > 0
  function corgiColor(key, fallback) {
    var value = typeof Commons.Color.pick === "function" ? Commons.Color.pick("corgi." + key, "") : ""
    var color = value && typeof Commons.Color.flatColor === "function"
      ? Commons.Color.flatColor(value, fallback) : fallback
    return value || !lightBar ? color : Qt.darker(color, 2.2)
  }
  readonly property color accent: corgiColor("accent", "#7bf1a8")
  readonly property color warm: corgiColor("warm", "#e5c38b")
  // Usage's own inks (Corgi's palette): its faint gray, the line color that
  // stipples a spark's time left, a fainter one for a slot with no reading,
  // and the hot of an account at its limit. On a light panel the grays are
  // the foreground faded into the panel instead. A spark's own panel is the
  // popup's background raised a little, as Corgi's surface is over its bg.
  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  readonly property color usageSurface: mixColor(Commons.Color.popups.background, foreground, 0.06)
  readonly property color usageFaint: lightBar ? mixColor(Commons.Color.popups.background, foreground, 0.5) : "#83909e"
  readonly property color usageLine: lightBar ? mixColor(Commons.Color.popups.background, foreground, 0.3) : "#505a65"
  readonly property color usageUnread: lightBar ? mixColor(Commons.Color.popups.background, foreground, 0.18) : "#3a414a"
  readonly property color hot: corgiColor("hot", "#eda398")
  // Corgi's sidebar has muted and, quieter still, faint.
  readonly property color muted: Commons.Color.muted
  readonly property color faint: Util.alpha(Commons.Color.muted, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------- sizing

  // The marks, sized off the bar's icon size as the shell's own corner marks
  // are: about five pixels at the default twelve.
  readonly property real markSize: Math.max(4, Math.round(Style.bar.iconSize * 0.42))
  readonly property real markGap: Math.max(1, Math.round(Style.bar.iconSize * 0.16))
  readonly property real markSpacing: Math.max(1, Math.round(Style.bar.iconSize * 0.1))
  // The lane beside the corgi the marks live in. It stays while Corgi runs,
  // marks or not, so the widget doesn't change width and push its neighbours
  // every time an agent starts or stops working.
  readonly property real lane: mode === "running" ? markGap + markSize : 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property int cardWidth: Style.space(360)
  // Taller with usage to show; the screen still caps it.
  readonly property int cardCap: usageAccounts.length > 0 && mode === "running" ? Style.space(760) : Style.space(560)

  // True while any part of the bar icon is moving. Nothing moves at rest.
  readonly property bool animating: attentionIndicator.animating || workingIndicator.animating
    || art.moving

  // ----------------------------------------------------- wire format

  function positiveInt(value) {
    var n = Number(value)
    return Number.isInteger(n) && n > 0 && n <= Number.MAX_SAFE_INTEGER ? n : 0
  }

  // One line of display text: no newlines, no runs of spaces, and a ceiling
  // on length, since a terminal title is whatever a program wrote.
  function oneLine(value, limit) {
    var s = value === null || value === undefined ? "" : String(value)
    s = s.replace(/[\u0000-\u001f\u007f\s]+/g, " ").trim()
    return s.length > limit ? s.slice(0, limit) : s
  }

  // What Corgi's sidebar glyph says. An older Corgi sends no status, so it is
  // worked out from the section and flags the way the sidebar does.
  readonly property var statuses: ["working", "needs_input", "retrying", "ready", "paused", "starting", "idle", "done", "other"]

  function derivedStatus(section, needsInput, unread) {
    if (needsInput) return "needs_input"
    switch (section) {
    case "working": return "working"
    case "ready": return "ready"
    case "done": return "done"
    default: return unread ? "ready" : "idle"
    }
  }

  // What `corgi watch` says plays on a row's second line, as Corgi's sidebar.
  readonly property var activities: ["waiting", "tool", "thinking", "compacting", "napping", "none"]
  readonly property var corgiModes: ["awake", "asleep", "herding", "content"]

  function normalAgent(raw, workspaceId, index) {
    var a = raw && typeof raw === "object" ? raw : {}
    var sections = ["working", "ready", "idle", "done"]
    var section = sections.indexOf(a.section) !== -1 ? a.section : "idle"
    var needsInput = a.needs_input === true
    var unread = a.unread === true
    var status = typeof a.status !== "string" ? derivedStatus(section, needsInput, unread)
      : (statuses.indexOf(a.status) !== -1 ? a.status : "other")
    var pane = positiveInt(a.pane)
    var headless = oneLine(a.headless, 64)
    var provider = oneLine(a.provider, 32)
    var title = oneLine(a.title, 300)
    var starred = a.starred === true
    return {
      key: pane ? "p:" + pane : (headless ? "h:" + headless : "w:" + workspaceId + ":" + index),
      pane: pane,
      headless: headless,
      title: title !== "" ? title : (provider !== "" ? provider : "Agent"),
      provider: provider,
      status: status,
      section: section,
      starred: starred,
      // Its activity section as the sidebar lists it: the starred above the rest.
      group: starred ? "starred" : section,
      detail: oneLine(a.detail, 300),
      unread: unread,
      glyph: activities.indexOf(a.glyph) !== -1 ? a.glyph : "none",
      corgi: corgiModes.indexOf(a.corgi) !== -1 ? a.corgi : "content",
      since: typeof a.compacting_since === "number" && a.compacting_since > 0 ? a.compacting_since : 0
    }
  }

  function normalWorkspace(raw, index) {
    var w = raw && typeof raw === "object" ? raw : {}
    var id = positiveInt(w.id)
    var list = Array.isArray(w.agents) ? w.agents : []
    var out = []
    for (var i = 0; i < list.length; i++) out.push(normalAgent(list[i], id || "i" + index, i))
    // Corgi lists them in its activity order; an older Corgi, in its
    // hand-sorted one, which keeps within each section.
    var order = sectionOrder
    var at = out.map(function(a, i) { return { a: a, i: i } })
    at.sort(function(l, r) { return order.indexOf(l.a.group) - order.indexOf(r.a.group) || l.i - r.i })
    out = at.map(function(x) { return x.a })
    var groups = []
    for (var i = 0; i < out.length; i++) {
      if (groups.length === 0 || groups[groups.length - 1].kind !== out[i].group)
        groups.push({ kind: out[i].group, agents: [] })
      groups[groups.length - 1].agents.push(out[i])
    }
    var links = []
    var seen = new Set()
    var rawLinks = Array.isArray(w.links) ? w.links : []
    for (var i = 0; i < rawLinks.length; i++) {
      var link = rawLinks[i]
      if (!link || typeof link.url !== "string" || !/^https?:\/\/[^\s\u0000-\u001f\u007f]+$/.test(link.url) || seen.has(link.url)) continue
      seen.add(link.url)
      links.push({ key: "l:" + (id || "i" + index) + ":" + link.url,
                   url: link.url, label: oneLine(link.label, 300) })
    }
    var name = oneLine(w.name, 120)
    // Corgi's own label for the links; an older Corgi sends none.
    var pointer = links.length === 0 ? "" : (oneLine(w.pointer, 80)
      || (links.length === 1 && links[0].label !== "" ? links[0].label + " \u2197" : "Open Link \u2197" + (links.length > 1 ? " " + links.length : "")))
    return { id: id || "i" + index, name: name !== "" ? name : "Workspace", links: links, pointer: pointer, agents: out,
             groups: groups }
  }

  // Every line the watch prints goes through here, once. Code past it reads
  // only the normalized shapes above. A line that is not a summary (it does
  // not parse, or says nothing about `running`) is ignored: the last good
  // state stands until the next one.
  function applyLine(line) {
    var text = String(line || "").trim()
    if (text === "") return
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) return
    if (typeof data.running !== "boolean") return
    if (!data.running) {
      resetLive()
      return
    }
    var ws = Array.isArray(data.workspaces) ? data.workspaces : []
    var nextWorkspaces = []
    for (var i = 0; i < ws.length; i++) nextWorkspaces.push(normalWorkspace(ws[i], i))
    workspaces = nextWorkspaces
    daemonRunning = true
  }

  function resetLive() {
    daemonRunning = false
    workspaces = []
  }

  // --------------------------------------------------- agent states

  // Finished work not yet looked at: ready, or paused with something unread.
  function isReady(a) {
    return a.status !== "needs_input" && (a.status === "ready" || a.unread)
  }

  function countWhere(test) {
    var n = 0
    for (var i = 0; i < agents.length; i++) if (test(agents[i])) n++
    return n
  }

  // The colour of an agent's glyph, as Corgi's sidebar draws it.
  function statusColor(a) {
    switch (a ? a.status : "") {
    case "working": return root.accent
    case "needs_input": return root.warm
    case "retrying": return root.warm
    case "ready": return root.accent
    case "paused": return a.unread ? root.accent : root.muted
    case "starting": return root.muted
    case "idle": return root.muted
    default: return root.faint
    }
  }

  // Bold names, as in the sidebar: work that finished and hasn't been seen.
  function emphasized(a) {
    return !!a && (a.status === "ready" || a.unread)
  }

  function rank(a) {
    var order = ["needs_input", "ready", "working", "retrying", "paused", "starting", "idle", "done", "other"]
    var at = order.indexOf(a.status)
    return isReady(a) && at > 1 ? 1 : (at < 0 ? order.length : at)
  }

  function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many)
  }

  function summaryText() {
    if (mode === "install") return "Not installed"
    if (mode === "stopped") return "Not running"
    var parts = [plural(agents.length, "agent", "agents")]
    if (needsCount > 0) parts.push(needsCount + " need" + (needsCount === 1 ? "s" : "") + " input")
    if (readyCount > 0) parts.push(readyCount + " ready")
    if (workingCount > 0) parts.push(workingCount + " working")
    return parts.join(" · ")
  }

  // The bar tooltip is the shell's own Text, so its format is not ours to set;
  // markup characters are dropped instead.
  function tooltipText() {
    var text
    if (mode === "install") text = "Install Corgi"
    else if (mode === "stopped") text = "Corgi isn't running. Click to open it."
    else text = "Corgi: " + summaryText()
    return text.replace(/[<>&]/g, "")
  }

  function workspaceHeading(ws) {
    if (!ws) return ""
    return ws.name + " · " + (ws.agents.length === 0 ? "no agents" : plural(ws.agents.length, "agent", "agents"))
  }

  function escaped(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
  function hex(color) {
    var c = Qt.color(color)
    var h = function(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }
  // A section's glyph in its color, its name and how many it lists, as the
  // sidebar's header reads: "▶ working 3".
  function sectionLabel(kind, count) {
    return "<font color=\"" + hex(sectionColor(kind)) + "\">" + sectionGlyphs[kind] + "</font> "
      + kind + " <font color=\"" + hex(root.muted) + "\">" + count + "</font>"
  }

  // ------------------------------------------------------- actions

  // A dropdown sits in front of the window you just asked for, so every
  // action closes it. Those that reach Corgi run raise.sh, which picks the
  // viewer used last that has a window, hands it `args` and focuses that
  // window, or opens Corgi in a new terminal when no viewer has one.
  // Detached, like the installer, so a reload cannot cut one short.
  readonly property string raiseScript: qmlDir + "/raise.sh"
  function raiseCorgi(args) {
    Util.execArgv(["bash", raiseScript, root.corgi].concat(args))
  }

  // Opens a terminal that installs Corgi with the plugin's pinned installer
  // and then becomes Corgi. The installer records the plugin folder, so Corgi
  // knows to remove itself along with it. Detached, so a reload cannot cut
  // the terminal short.
  function install() {
    if (actionGuard.running) return
    actionGuard.restart()
    Util.execArgv(["bun", root.openInstaller, root.pluginDir])
    close()
  }

  // Raises the window of the viewer used last, or opens Corgi in a new
  // terminal when no viewer has one.
  function openCorgi() {
    if (!installed) {
      install()
      return
    }
    if (actionGuard.running) return
    actionGuard.restart()
    raiseCorgi([])
    close()
  }

  // Selects the agent's pane in the viewer used last and raises its window. A
  // headless agent has no pane to select, so it opens Corgi instead.
  function focusAgent(a) {
    if (!a || !installed) return
    if (!a.pane) {
      openCorgi()
      return
    }
    if (actionGuard.running) return
    actionGuard.restart()
    raiseCorgi(["focus", String(a.pane)])
    close()
  }

  function primaryAction() {
    if (mode === "install") install()
    else openCorgi()
  }

  // A new tab in the workspace: Corgi's new-tab picker, in the viewer used
  // last, which comes forward. With no viewer window, Corgi opens instead.
  function newTab(ws) {
    if (mode !== "running" || !ws || !/^[1-9][0-9]*$/.test(String(ws.id))) {
      primaryAction()
      return
    }
    if (actionGuard.running) return
    actionGuard.restart()
    raiseCorgi(["new-tab", String(ws.id)])
    close()
  }

  function openLink(link) {
    if (!link || actionGuard.running) return
    actionGuard.restart()
    Util.execArgv(["omarchy-launch-browser", link.url])
    close()
  }

  // A workspace's pointer: its one link opens; several list under it.
  function pointerAction(ws) {
    if (!ws || ws.links.length === 0) return
    if (ws.links.length === 1) openLink(ws.links[0])
    else linksOpen = linksOpen === "w:" + ws.id ? "" : "w:" + ws.id
  }

  // A link's name, or where it points when it has none.
  function linkName(link) {
    if (link.label !== "") return link.label
    var m = /^https?:\/\/([^\/?#]+)/.exec(link.url)
    return m ? m[1] : link.url
  }

  // ------------------------------------------------- keyboard cursor

  // Agents, links, and a heading's pointer.
  // Every row that shows is a stop: agents, links, and the headings and
  // rows that fold.
  function actionable(row) {
    return rowShown(row)
  }

  // A row's controls, left to right; "" is the row itself. The panel's
  // header (index -1) opens Corgi, then its counts; a workspace's heading
  // folds it, then its links, then New +.
  function partsOf(index) {
    if (index < 0) {
      var out = [""]
      for (var i = 0; i < kinds.length; i++) if (kindCount(kinds[i]) > 0) out.push(kinds[i])
      return out
    }
    var r = rows[index]
    if (r.kind !== "workspace") return [""]
    return r.workspace.links.length > 0 ? ["", "links", "new"] : ["", "new"]
  }
  // The control the cursor is on within its row.
  property string cursorPart: ""
  function setCursor(key, part) {
    cursorKey = key
    cursorPart = part || ""
  }
  function onCursor(key, part) {
    return cursorKey === key && cursorPart === (part || "")
  }
  function moveCursorX(delta) {
    var parts = partsOf(cursorIndex())
    var at = Math.max(0, parts.indexOf(cursorPart))
    cursorPart = parts[Math.max(0, Math.min(parts.length - 1, at + delta))]
  }

  function actionIndexes() {
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (actionable(rows[i])) out.push(i)
    return out
  }

  function cursorIndex() {
    if (cursorKey === "") return -1
    for (var i = 0; i < rows.length; i++)
      if (actionable(rows[i]) && rows[i].key === cursorKey) return i
    return -1
  }

  // The agent that wants you most, first in list order among equals: the
  // reason you opened the panel is rarely the top row.
  function bestKey() {
    var best = null
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "agent" && rowShown(rows[i]) && (best === null || rank(rows[i].agent) < rank(best)))
        best = rows[i].agent
    var indexes = actionIndexes()
    return best ? best.key : (indexes.length > 0 ? rows[indexes[0]].key : "")
  }

  // Up from the first action reaches the header's button.
  function moveCursor(delta) {
    var indexes = actionIndexes()
    if (indexes.length === 0) return
    var at = indexes.indexOf(cursorIndex())
    if (at < 0 && delta < 0) return
    var next = at < 0 ? 0 : at + delta
    cursorPart = ""
    if (next < 0) {
      cursorKey = ""
      return
    }
    cursorKey = rows[indexes[Math.min(indexes.length - 1, next)]].key
    showCursor()
  }

  function showCursor() {
    var index = cursorIndex()
    if (index >= 0 && panel.loadedContent) panel.loadedContent.showRow(index)
  }

  function activateCursor() {
    var index = cursorIndex()
    if (partsOf(index).indexOf(cursorPart) < 0) cursorPart = ""
    if (index < 0) {
      if (cursorPart !== "") clickKind(cursorPart)
      else primaryAction()
      return
    }
    var r = rows[index]
    switch (r.kind) {
    case "link": openLink(r.link); break
    case "agent": focusAgent(r.agent); break
    case "section": toggleFold("sections", r.fold); break
    case "more": toggleFold("idle", r.workspace.id); break
    default:
      if (cursorPart === "links") pointerAction(r.workspace)
      else if (cursorPart === "new") newTab(r.workspace)
      else toggleFold("workspaces", r.workspace.id)
    }
  }

  onOpenedChanged: {
    linksOpen = ""
    filterPinned = ""
    filterPreview = ""
    filterDismissed = ""
    cursorPart = ""
    cursorKey = opened ? bestKey() : ""
    if (opened) Qt.callLater(showCursor)
    if (opened) refreshUsage()
  }

  // ------------------------------------------------------ the pin

  // A release name is a path segment, so only a plain one is accepted.
  function readRelease(text) {
    var value = String(text || "").trim()
    release = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(value) ? value : ""
  }

  // Watches Corgi's `current`: an update moves it, and uninstalling deletes
  // it. A file that does not exist yet cannot be watched, so until it does,
  // installWatch waits for it, and the pointer coming near the icon re-reads it.
  FileView {
    id: currentFile
    path: root.corgiRoot + "/current"
    watchChanges: true
    printErrors: false
    onLoaded: root.readRelease(text())
    onLoadFailed: function(error) { root.release = "" }
    onFileChanged: reload()
  }

  // ------------------------------------------------------- the watch

  // `setpriv --pdeathsig` has the kernel end the watch when the shell exits,
  // however it exits, as the shell's own clipboard watchers do. A reload
  // destroys this Process, which ends the watch with it.
  Process {
    id: watchProc
    command: root.corgi !== ""
      ? ["setpriv", "--pdeathsig", "TERM", root.corgi, "watch", "--json"] : []
    stdout: SplitParser {
      onRead: function(line) { root.applyLine(line) }
    }
    // runningChanged rather than exited: a binary that fails to start never
    // reports an exit.
    onRunningChanged: {
      if (running) return
      root.resetLive()
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: root.syncWatch()
  }

  function syncWatch() {
    if (root.corgi !== "") {
      if (!watchProc.running) watchProc.running = true
    } else if (watchProc.running) {
      watchProc.running = false
    }
  }

  // A new release means a new binary: stop the old watch and let the restart
  // pick up the new command.
  onCorgiChanged: {
    if (watchProc.running) watchProc.running = false
    else syncWatch()
  }

  Component.onCompleted: {
    syncWatch()
    syncInstallWatch()
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    Util.execArgv(["bun", root.openInstaller, root.pluginDir, "--once"])
  }

  // Until Corgi is installed: waits, with inotify on the nearest folder that
  // exists, for `current` to appear, then re-reads it. inotifywait is what
  // Omarchy's own plugin watcher runs. It looks again only once its watch is
  // up, so nothing made in between is missed, and goes when this does.
  readonly property string installWaiter: [
    'f=$1',
    'command -v inotifywait >/dev/null || exit 1',
    'w=',
    'trap \'[ -z "$w" ] || kill "$w" 2>/dev/null\' EXIT',
    'trap \'exit 143\' TERM',
    'nearest() { d=${f%/*}; while [ -n "$d" ] && [ ! -d "$d" ]; do d=${d%/*}; done; d=${d:-/}; }',
    'until [ -e "$f" ]; do',
    '  nearest; at=$d',
    '  exec 3< <(exec setpriv --pdeathsig TERM inotifywait -m -e create -e moved_to -e close_write --format x "$at" 2>&1)',
    '  w=$!; up=',
    '  while read -r line <&3; do case $line in "Watches established."*|x) up=1; break ;; esac; done',
    '  [ -n "$up" ] || exit 1',
    '  nearest',
    '  [ -e "$f" ] || [ "$d" != "$at" ] || read -r line <&3',
    '  kill "$w" 2>/dev/null; w=; exec 3<&-',
    'done'
  ].join("\n")
  Process {
    id: installWatch
    command: ["setpriv", "--pdeathsig", "TERM", "bash", "-c", root.installWaiter,
              "corgi-install-watch", root.corgiRoot + "/current"]
    // Present: read it. Without inotifywait it gives up, and the pointer's
    // re-read is left.
    onExited: function(code) { if (code === 0) currentFile.reload() }
  }

  function syncInstallWatch() {
    var wanted = !root.installed && !!Quickshell.env("HOME")
    if (wanted && !installWatch.running) installWatch.running = true
    else if (!wanted && installWatch.running) installWatch.running = false
  }
  onInstalledChanged: syncInstallWatch()

  // Two clicks in a row open one terminal, not two.
  Timer {
    id: actionGuard
    interval: 1500
  }

  // ------------------------------------------------------- usage

  // Every account's usage as Manage agents shows it, from the one-shot
  // `corgi usage --json`: deduped (a login shared by folders or harnesses
  // shows once), in the launcher's order. The panel formats the raw readings
  // into limit groups; older Corgi releases send those groups already drawn.
  // Read when the panel opens and once a minute while it stays open, never
  // from the bar and never while the panel is closed.
  property var usageAccounts: []

  readonly property var providerNames: ({ claude: "Claude", codex: "Codex", opencode: "OpenCode", omp: "omp", pi: "Pi" })

  function providerName(provider) {
    if (providerNames[provider]) return providerNames[provider]
    return provider ? provider.charAt(0).toUpperCase() + provider.slice(1) : "Account"
  }

  // A provider becomes part of an icon's path, so only a plain name counts.
  function normalProvider(value) {
    var provider = typeof value === "string" ? value.toLowerCase() : ""
    return /^[a-z0-9][a-z0-9_-]{0,31}$/.test(provider) ? provider : ""
  }

  readonly property var barTones: ["accent", "warm", "hot", "earlier", "stale", "remaining", "unread"]

  // A spark bar: its height in percent, or null with no reading, and its tone.
  function normalBar(raw) {
    var b = raw && typeof raw === "object" ? raw : {}
    var tone = barTones.indexOf(b.tone) !== -1 ? b.tone : "stale"
    var used = typeof b.used === "number" && isFinite(b.used) ? Math.max(0, Math.min(100, b.used)) : null
    return { used: tone === "remaining" || tone === "unread" ? null : used, tone: tone }
  }

  // A limit's group, or null for a slot the account leaves empty. Its spark
  // always has fourteen bars.
  function normalWindow(raw) {
    if (!raw || typeof raw !== "object") return null
    var used = typeof raw.used === "number" && isFinite(raw.used) ? raw.used : null
    var given = Array.isArray(raw.bars) ? raw.bars : []
    // Usage within a window only climbs, so the spark never falls: a lower
    // reading is drawn at the height already reached, and last month's spend,
    // which an older Corgi sends before this month's, is left out.
    var bars = [], top = 0
    for (var i = 0; i < 14; i++) {
      var bar = i < given.length ? normalBar(given[i]) : { used: null, tone: "unread" }
      if (bar.tone === "earlier") bar = { used: null, tone: "unread" }
      if (bar.used !== null) {
        top = Math.max(top, bar.used)
        bar = { used: top, tone: bar.tone }
      }
      bars.push(bar)
    }
    return { label: oneLine(raw.label, 6), bars: bars, used: used, figure: oneLine(raw.figure, 8), reset: oneLine(raw.reset, 16) }
  }

  function normalAccount(raw, index) {
    var a = Usage.display(raw && typeof raw === "object" ? raw : {}, Math.floor(Date.now() / 1000))
    var provider = normalProvider(a.provider)
    var shared = []
    var given = Array.isArray(a.shared) ? a.shared : []
    for (var i = 0; i < given.length && shared.length < 6; i++) {
      var s = given[i] && typeof given[i] === "object" ? given[i] : {}
      var sp = normalProvider(s.provider)
      if (sp !== "") shared.push({ provider: sp, providerName: providerName(sp), name: oneLine(s.name, 60) })
    }
    var windows = Array.isArray(a.windows) ? a.windows : []
    return {
      key: index,
      provider: provider,
      providerName: providerName(provider),
      name: oneLine(a.name, 60),
      email: oneLine(a.email, 120),
      plan: oneLine(a.plan, 32),
      metered: a.metered === true,
      shared: shared,
      windows: [normalWindow(windows[0]), normalWindow(windows[1])],
      amount: oneLine(a.amount, 48)
    }
  }

  // Bad or missing output, or no daemon, is no usage section.
  function applyUsage(text) {
    var data = null
    try {
      data = JSON.parse(String(text || "").trim())
    } catch (e) {
      data = null
    }
    if (!data || typeof data !== "object" || Array.isArray(data) || data.running !== true
        || !Array.isArray(data.accounts)) {
      usageAccounts = []
      return
    }
    var out = []
    for (var i = 0; i < data.accounts.length && out.length < 24; i++) {
      var account = normalAccount(data.accounts[i], i)
      // An account with nothing to draw has no heading either.
      if (account.windows[0] || account.windows[1]) out.push(account)
    }
    usageAccounts = out
  }

  // A spark bar's color, per the contract's table.
  function toneColor(tone) {
    switch (tone) {
    case "accent": return root.accent
    case "warm": return root.warm
    case "hot": return root.hot
    case "earlier": return mixColor(root.accent, root.usageFaint, 0.6)
    case "remaining": return root.usageLine
    case "unread": return root.usageUnread
    default: return root.usageFaint
    }
  }

  // A reading's ink. An accent bar under half height fades toward faint by
  // its height in eighths, as Corgi's card shades its blocks.
  function barColor(bar) {
    if (bar.tone !== "accent" || bar.used === null) return toneColor(bar.tone)
    var eighths = Math.min(8, Math.max(1, Math.floor((bar.used * 8 + 50) / 100)))
    return mixColor(root.accent, root.usageFaint, [0.75, 0.45, 0.15][eighths - 1] || 0)
  }

  function refreshUsage() {
    if (!opened || mode !== "running" || root.corgi === "" || usageProc.running) return
    usageProc.command = [root.corgi, "usage", "--json"]
    usageProc.running = true
  }

  Process {
    id: usageProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyUsage(text)
    }
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.refreshUsage()
  }


  // ------------------------------------------------------ the button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.iconSlot + Math.ceil(root.lane)
    // Stopped is a dim corgi: Corgi is there, it just isn't running.
    dimmed: root.mode === "stopped"
    // The amber dot says an agent waits on you; the corgi keeps the bar's color.
    active: false
    tooltipText: root.tooltipText()
    // The corgi and its marks are drawn below rather than through
    // iconComponent, which would scale the marks into the icon's twelve
    // pixels. The corgi still goes through the shell's BarIconContent, so it
    // is measured, sized and centred like every other bar icon.
    hasVisualContent: true

    // The corgi's canvas, as BarIconButton lays one out, and the marks' lane
    // beside it (below it on a vertical bar).
    Item {
      id: art
      objectName: "corgiArt"

      readonly property bool vertical: button.vertical
      readonly property real canvas: Style.bar.iconCanvas
      readonly property bool anyMark: root.workingMark || root.attentionMark
      readonly property bool stacked: root.workingMark && root.attentionMark
      readonly property bool moving: shiftAnimation.running || attentionOffsetAnimation.running
        || workingOffsetAnimation.running

      width: vertical ? canvas : canvas + root.lane
      height: vertical ? canvas + root.lane : canvas
      // Exact coordinates, as BarIconButton's, keep odd slots centred.
      x: (button.width - width) / 2
      y: (button.height - height) / 2
      // Older Omarchy releases have no press feedback.
      scale: button.pressScale !== undefined ? button.pressScale : 1

      // With no marks the corgi sits centred in its lane-widened slot, and
      // slides aside as the first mark buds out, back as the last one goes.
      // Without animation it stays aside, beside the empty dot.
      property real shift: anyMark || !root.motion ? 0 : root.lane / 2
      Behavior on shift {
        NumberAnimation {
          id: shiftAnimation
          duration: Style.duration(art.anyMark ? 250 : 170)
          easing.type: Easing.Bezier
          easing.bezierCurve: root.easeOut
        }
      }

      // The corgi's edge on the marks' side, and where a mark's centre rests
      // along the bar.
      readonly property real edge: vertical
        ? corgiIcon.y + canvas / 2 + corgiIcon.paintedHeight / 2
        : corgiIcon.x + canvas / 2 + corgiIcon.paintedWidth / 2
      readonly property real restMain: canvas / 2
        + (vertical ? corgiIcon.paintedHeight : corgiIcon.paintedWidth) / 2 + root.markGap + root.markSize / 2
      readonly property real crossMiddle: canvas / 2

      // Two marks stack, the dot first; one sits level with the corgi.
      // Without animation each keeps its stacked place, so none moves.
      readonly property real pitch: (root.markSize + root.markSpacing) / 2
      property real attentionOffset: stacked || !root.motion ? -pitch : 0
      property real workingOffset: stacked || !root.motion ? pitch : 0
      Behavior on attentionOffset {
        NumberAnimation {
          id: attentionOffsetAnimation
          duration: Style.duration(art.stacked ? 250 : 170)
          easing.type: Easing.Bezier
          easing.bezierCurve: root.easeOut
        }
      }
      Behavior on workingOffset {
        NumberAnimation {
          id: workingOffsetAnimation
          duration: Style.duration(art.stacked ? 250 : 170)
          easing.type: Easing.Bezier
          easing.bezierCurve: root.easeOut
        }
      }

      // Corgi's idle glyph, ○, holding the dot's place while nothing needs
      // you, so a corgi that can't slide never sits beside nothing.
      Rectangle {
        objectName: "corgiPlaceholderMark"
        visible: !root.motion && root.mode === "running" && !root.attentionMark
        width: root.markSize
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Math.round(root.markSize * 0.18))
        border.color: Util.alpha(root.foreground, 0.45)
        x: (art.vertical ? art.crossMiddle + art.attentionOffset : art.restMain) - width / 2
        y: (art.vertical ? art.restMain : art.crossMiddle + art.attentionOffset) - height / 2
      }

      Indicator {
        id: attentionIndicator
        objectName: "corgiAttentionMark"
        anchors.fill: parent
        kind: "dot"
        shown: root.attentionMark
        color: root.attentionColor
        size: root.markSize
        vertical: art.vertical
        edge: art.edge
        restX: art.vertical ? art.crossMiddle + art.attentionOffset : art.restMain
        restY: art.vertical ? art.restMain : art.crossMiddle + art.attentionOffset
        sibling: workingIndicator
      }

      Indicator {
        id: workingIndicator
        objectName: "corgiWorkingMark"
        anchors.fill: parent
        kind: "play"
        shown: root.workingMark
        color: root.accent
        size: root.markSize
        vertical: art.vertical
        edge: art.edge
        restX: art.vertical ? art.crossMiddle + art.workingOffset : art.restMain
        restY: art.vertical ? art.restMain : art.crossMiddle + art.workingOffset
        sibling: attentionIndicator
      }

      // Above the marks, which come out from under its edge.
      BarIconContent {
        id: corgiIcon
        z: 2
        x: art.vertical ? 0 : art.shift
        y: art.vertical ? art.shift : 0
        width: art.canvas
        height: art.canvas
        sourceSize: art.canvas
        sourceComponent: Component {
          CorgiIcon {
            iconSize: Math.min(Style.bar.iconSize, Style.bar.iconCanvas)
            // As BarIconButton colours its glyph: the bar's foreground, which
            // follows what is behind a transparent bar, or urgent when active.
            color: button.active && button.useActiveColor ? button.activeColor : button.foreground
            installMark: root.mode === "install"
            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: Style.duration(160) }
            }
          }
        }
      }
    }

    // A file that did not exist when this widget loaded is not watched, so
    // the pin is read again whenever the pointer comes near the icon.
    onTooltipHoveredChanged: if (tooltipHovered && root.mode === "install") currentFile.reload()

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.primaryAction()
        return
      }
      if (root.mode === "running") root.toggle()
      else root.primaryAction()
    }
  }

  // ------------------------------------------------------- the panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(root.cardWidth)
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, root.cardCap)

    content: Card {
      widget: root
      maxHeight: Math.min(root.cardCap, panel.availableCardHeight) - panel.verticalContentInset
    }
  }
}
