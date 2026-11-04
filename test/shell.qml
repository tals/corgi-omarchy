import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Drives corgi.computer's Widget.qml through its states against a fake corgi
// (see inside.sh), printing PASS/FAIL lines and saving screenshots and
// transition frames to /tmp/out.
ShellRoot {
  id: shell

  readonly property string plugin: "/tmp/plugins/corgi.computer"
  // Where the manifest says the QML is: its qml-<hash>/ folder.
  readonly property string qml: plugin + "/" + (Quickshell.env("PLUGIN_QML") || ".")
  // Where Corgi installs, outside the plugin folder (inside.sh sets HOME).
  readonly property string corgiRoot: "/tmp/home/.local/share/corgi"
  readonly property string scale: Quickshell.env("HARNESS_SCALE") || "1"
  property int failures: 0
  readonly property var w: widgetLoader.item
  readonly property var wv: verticalLoader.item

  function check(label, cond) {
    if (!cond) failures++
    console.log((cond ? "PASS " : "FAIL ") + label)
  }

  function sh(script) {
    Quickshell.execDetached(["bash", "-c", script])
  }

  function feed(obj) {
    var line = typeof obj === "string" ? obj : JSON.stringify(obj)
    Quickshell.execDetached(["bash", "-c", 'printf "%s\\n" "$1" >> /tmp/scenario/feed.jsonl', "feed", line])
  }

  function shot(item, name) {
    if (!item) { console.log("FAIL shot " + name + ": no item"); failures++; return }
    item.grabToImage(function(result) {
      var ok = result.saveToFile("/tmp/out/" + name + ".png")
      if (!ok) { console.log("FAIL save " + name); shell.failures++ }
    })
  }

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = find(kids[i], name)
      if (found) return found
    }
    return null
  }

  // The text an item shows, its own and its children's.
  function shownTexts(item) {
    var out = [], seen = []
    var walk = function(it) {
      if (!it || !it.visible || seen.indexOf(it) !== -1) return
      seen.push(it)
      if (typeof it.text === "string" && "font" in it && "horizontalAlignment" in it) out.push(it.text)
      if (it.contentItem && it.contentItem !== it) walk(it.contentItem)
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(item)
    return out
  }

  function countNamed(item, name) {
    if (!item) return 0
    var n = item.objectName === name ? 1 : 0
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) n += countNamed(kids[i], name)
    return n
  }

  // The full world with agent 13 compacting since `ago` ms.
  function compactingState(ago) {
    var d = liveState("needs_input", "working", "ready", true)
    var a = d.workspaces[0].agents[1]
    a.glyph = "compacting"
    a.corgi = "herding"
    a.compacting_since = Date.now() - ago
    return d
  }

  function keyboardPanel() {
    if (!w) return null
    for (var i = 0; i < w.data.length; i++)
      if (w.data[i] && "loadedContent" in w.data[i]) return w.data[i]
    return null
  }

  function marks(widget) {
    return { dot: find(widget, "corgiAttentionMark"), play: find(widget, "corgiWorkingMark") }
  }

  // ------------------------------------------------------------ fixtures

  function agent(pane, title, provider, section, status, detail, extra) {
    var a = { pane: pane, headless: null, title: title, provider: provider, section: section,
              needs_input: status === "needs_input", unread: status === "ready",
              status: status, detail: detail,
              // As Corgi's sidebar would: working spins, a new agent's corgi is
              // awake, an idle one sleeps.
              glyph: status === "working" || status === "starting" ? "thinking" : "none",
              corgi: status === "starting" ? "awake"
                : (status === "idle" || status === "ready" || status === "paused" ? "asleep" : "content") }
    if (extra) for (var k in extra) a[k] = extra[k]
    return a
  }

  // The api workspace's three agents take the statuses given; the second
  // workspace's paused agent has unread work only in the full world.
  function liveState(s12, s13, s14, full) {
    var section = function(st) { return st === "needs_input" || st === "working" ? "working" : (st === "ready" ? "ready" : "idle") }
    return {
      running: true,
      counts: { agents: 6 },
      workspaces: [
        { id: 1, name: "api", links: full ? [
          { url: "http://localhost:3000/?q=a&b=two", label: "API preview" },
          { url: "http://localhost:3000/?q=a&b=two", label: "Duplicate" },
          { url: "javascript:alert(1)", label: "Invalid" },
          { url: "http://localhost:3001/admin", label: "" }
        ] : [], pointer: full ? "Open Link \u2197 2" : "", agents: [
          agent(12, "Fix the login redirect", "claude", section(s12), s12,
                s12 === "needs_input" ? "Needs input" : (s12 === "working" ? "Reading auth.ts" : "")),
          agent(13, "Write integration tests for the session store", "codex", section(s13), s13,
                s13 === "working" ? "Running bun test src/session" : ""),
          agent(14, "Bump dependencies", "claude", section(s14), s14, s14 === "ready" ? "Finished, 4 files changed" : "")
        ]},
        { id: 2, name: "<b>site</b> & docs", links: full ? [
          { url: "http://localhost:4000", label: "" }
        ] : [], pointer: full ? "Open Link \u2197" : "", agents: [
          agent(21, "<img src='http://127.0.0.1:9/x.png'> <b>markup</b> stays text", "claude", "idle", "paused",
                "Paused · <i>waiting</i>", { unread: full === true }),
          { pane: null, headless: "h-7", title: "Summarize the changelog", provider: "codex",
            section: "done", needs_input: false, unread: false, status: "done", detail: "Session ended" },
          agent(22, "Start the preview server", "opencode", "working", "starting", ""),
          agent(23, "Unknown future state", "claude", "idle", "hibernating", "")
        ]},
        { id: 3, name: "empty", agents: [] }
      ]
    }
  }

  // The same world as an older Corgi reports it: no status, no detail.
  function oldState() {
    var d = liveState("needs_input", "working", "ready")
    d.workspaces[1].agents[0].unread = false
    d.workspaces[1].agents[0].section = "idle"
    for (var i = 0; i < d.workspaces.length; i++)
      delete d.workspaces[i].links
    for (var i = 0; i < d.workspaces.length; i++)
      for (var j = 0; j < d.workspaces[i].agents.length; j++) {
        delete d.workspaces[i].agents[j].status
        delete d.workspaces[i].agents[j].detail
      }
    d.workspaces[1].agents.push({ pane: 24, title: "Finished while away", provider: "codex", section: "idle", needs_input: false, unread: true })
    return d
  }

  property var moving: null
  property real openedHeight: -1
  // The list's delegate for the row `key`, and the keys its model holds.
  function rowItem(key) {
    var list = cardLoader.item ? find(cardLoader.item, "agentList") : null
    if (!list) return null
    var kids = list.contentItem.children
    for (var i = 0; i < kids.length; i++) if (kids[i].key === key) return kids[i]
    return null
  }
  function listKeys() {
    var list = cardLoader.item ? find(cardLoader.item, "agentList") : null
    var out = []
    if (!list) return out
    for (var i = 0; i < list.model.count; i++) out.push(list.model.get(i).key)
    return out
  }

  // DIAG: the real panel's drawn height, sampled as it opens.
  Timer {
    id: heightProbe
    property var samples: []
    property real began: 0
    interval: 20
    repeat: true
    onRunningChanged: if (running) began = Date.now()
    onTriggered: {
      var kp = shell.keyboardPanel()
      var t = Date.now() - began
      samples.push(Math.round(t) + ":" + (kp ? Math.round(kp.drawnHeight) + "/" + Math.round(kp.loadedContentHeight) : "-"))
      if (t > 1400) stop()
    }
  }

  // The folds the widget saves, where it saves them.
  FileView {
    id: foldsFile
    path: "/tmp/home/.local/state/omarchy/corgi.computer/panel.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  function rowFor(pane) {
    for (var i = 0; i < w.rows.length; i++)
      if (w.rows[i].kind === "agent" && w.rows[i].agent.pane === pane) return w.rows[i].agent
    return null
  }

  // ------------------------------------------------------------ frames

  // Transition frames, scrubbed rather than recorded: with animations off the
  // widget jumps to each end state, and every moving value is then set to
  // where Style.easeOut puts it at evenly spaced moments. All the parts of a
  // transition share one duration and curve, so this is what the animation
  // draws at each instant, independent of the compositor's frame timing.
  readonly property var scrubTimes: [0, 0.06, 0.12, 0.2, 0.3, 0.42, 0.56, 0.72, 1]

  // cubic-bezier(0.23, 1, 0.32, 1), Style.easeOut
  function ease(t) {
    var x1 = 0.23, y1 = 1, x2 = 0.32, y2 = 1
    function bx(s) { return 3 * x1 * s * (1 - s) * (1 - s) + 3 * x2 * s * s * (1 - s) + s * s * s }
    function by(s) { return 3 * y1 * s * (1 - s) * (1 - s) + 3 * y2 * s * s * (1 - s) + s * s * s }
    var lo = 0, hi = 1
    for (var i = 0; i < 40; i++) {
      var mid = (lo + hi) / 2
      if (bx(mid) < t) lo = mid
      else hi = mid
    }
    return by((lo + hi) / 2)
  }

  // { name, ms, dot: [from, to], play: [from, to], via: { dot, play },
  //   attention: [from, to], working: [from, to], shift: [from, to] }
  property var scrub: null
  property int scrubIndex: 0

  function scrubFrame() {
    var m = marks(w)
    var art = find(w, "corgiArt")
    var e = ease(scrubTimes[scrubIndex])
    var lerp = function(pair) { return pair[0] + (pair[1] - pair[0]) * e }
    if (scrub.dot) m.dot.progress = lerp(scrub.dot)
    if (scrub.play) m.play.progress = lerp(scrub.play)
    if (scrub.attention) art.attentionOffset = lerp(scrub.attention)
    if (scrub.working) art.workingOffset = lerp(scrub.working)
    if (scrub.shift) art.shift = lerp(scrub.shift)
  }

  // Set after the progress has landed: the zero-length animation that lands
  // it drops the latch when it ends, as a real transition does only at its
  // end.
  function scrubLatch() {
    var m = marks(w)
    if (scrub.dot) m.dot.viaSibling = !!scrub.via.dot
    if (scrub.play) m.play.viaSibling = !!scrub.via.play
  }

  function scrubShot() {
    var ms = Math.round(scrubTimes[scrubIndex] * scrub.ms)
    shot(barStrip, "frames/" + scrub.name + "-" + (scrubIndex < 10 ? "0" : "") + scrubIndex + "-" + ms + "ms")
  }

  function scrubSequence(spec, setup, end, endTest) {
    var list = []
    list.push(function() { feed(setup); return 1300 })
    list.push(function() { return settled("scrub setup " + spec.name) })
    list.push(function() {
      Style.reduceMotion = true
      feed(end)
      return whenWidget(endTest, "scrub end " + spec.name)
    })
    list.push(function() { return 200 })
    for (var i = 0; i < scrubTimes.length; i++) {
      (function(index) {
        list.push(function() { shell.scrub = spec; shell.scrubIndex = index; shell.scrubFrame(); return 100 })
        list.push(function() { shell.scrubLatch(); return 100 })
        list.push(function() { shell.scrubShot(); return 100 })
      })(i)
    }
    // Scrubbing broke the widget's bindings: load it afresh.
    list.push(function() { Style.reduceMotion = false; cardLoader.source = ""; widgetLoader.active = false })
    list.push(function() {
      widgetLoader.active = true
      return whenWidget(function() { return !!shell.w && shell.w.mode === "running" }, "reload after " + spec.name)
    })
    list.push(function() { return settled("after " + spec.name) })
    return list
  }

  function scrubs() {
    var pitch = (w.markSize + w.markSpacing) / 2
    var lane = w.lane
    var idle = liveState("idle", "idle", "idle")
    var working = liveState("idle", "working", "idle")
    return [].concat(
      scrubSequence({ name: "1-bud-working", ms: 250, play: [0, 1], via: {}, shift: [lane / 2, 0] },
                    idle, working, function() { return w.workingMark }),
      scrubSequence({ name: "2-split-dot", ms: 250, dot: [0, 1], via: { dot: true },
                      attention: [0, -pitch], working: [0, pitch] },
                    working, liveState("needs_input", "working", "idle"), function() { return w.attentionMark }),
      scrubSequence({ name: "3-merge-dot", ms: 170, dot: [1, 0], via: { dot: true },
                      attention: [-pitch, 0], working: [pitch, 0] },
                    liveState("ready", "working", "idle"), working, function() { return !w.attentionMark }),
      scrubSequence({ name: "4-unbud-working", ms: 170, play: [1, 0], via: {}, shift: [0, lane / 2] },
                    working, idle, function() { return !w.workingMark }),
      scrubSequence({ name: "5-bud-both", ms: 250, dot: [0, 1], play: [0, 1], via: {},
                      attention: [0, -pitch], working: [0, pitch], shift: [lane / 2, 0] },
                    idle, liveState("ready", "working", "idle"), function() { return w.workingMark && w.attentionMark }))
  }

  property bool reduceWatch: false

  Connections {
    target: shell.w
    ignoreUnknownSignals: true
    function onWorkingMarkChanged() {
      if (shell.reduceWatch) Qt.callLater(function() { reduceProbe.restart() })
    }
  }

  // 50 ms after a mark flips: with animations off it has already arrived.
  property bool expectInstant: false
  Timer {
    id: reduceProbe
    interval: 50
    onTriggered: {
      var m = shell.marks(shell.w)
      var target = shell.w.workingMark ? 1 : 0
      if (shell.expectInstant) shell.check("animations off: the mark is there at once", m.play.progress === target)
      else shell.check("animations on: the mark is still on its way 50 ms in", m.play.progress !== target)
    }
  }

  // ------------------------------------------------------------ windows

  PluginBarApi {
    id: barApi
    pluginId: "corgi.computer"
    moduleName: "corgi.computer"
    foreground: Commons.Color.foreground
    barForeground: Commons.Color.foreground
    background: Commons.Color.background
    urgent: Commons.Color.urgent
    fontFamily: "JetBrainsMono Nerd Font"
    position: "top"
    vertical: false
    barSize: Style.bar.sizeHorizontal
  }

  PluginBarApi {
    id: verticalBarApi
    pluginId: "corgi.computer"
    moduleName: "corgi.computer"
    foreground: Commons.Color.foreground
    barForeground: Commons.Color.foreground
    background: Commons.Color.background
    urgent: Commons.Color.urgent
    fontFamily: "JetBrainsMono Nerd Font"
    position: "left"
    vertical: true
    barSize: Style.bar.sizeVertical
  }

  // A stretch of bar: first-party glyph icons either side of the corgi, so
  // its size and weight can be judged against theirs.
  FloatingWindow {
    title: "harness-bar"
    implicitWidth: 140
    implicitHeight: Style.bar.sizeHorizontal
    color: Commons.Color.bar.background

    Rectangle {
      id: barStrip
      anchors.fill: parent
      color: Commons.Color.bar.background

      Row {
        anchors.centerIn: parent
        BarIconButton { bar: barApi; text: "\uF1EB" }
        BarIconButton { bar: barApi; text: "\uDB86\uDEA3" }
        Loader {
          id: widgetLoader
          width: item ? item.implicitWidth : 0
          height: item ? item.implicitHeight : 0
          source: "file://" + shell.qml + "/Widget.qml"
          onLoaded: {
            item.bar = barApi
            item.moduleName = "corgi.computer"
            item.settings = { id: "corgi.computer" }
          }
        }
        BarIconButton { bar: barApi; text: "\uF028" }
      }
    }
  }

  FloatingWindow {
    title: "harness-vbar"
    implicitWidth: Style.bar.sizeVertical
    implicitHeight: 96
    color: Commons.Color.bar.background

    Rectangle {
      id: verticalStrip
      anchors.fill: parent
      color: Commons.Color.bar.background

      Column {
        anchors.centerIn: parent
        BarIconButton { bar: verticalBarApi; text: "\uF1EB" }
        Loader {
          id: verticalLoader
          width: item ? item.implicitWidth : 0
          height: item ? item.implicitHeight : 0
          source: "file://" + shell.qml + "/Widget.qml"
          onLoaded: {
            item.bar = verticalBarApi
            item.moduleName = "corgi.computer"
            item.settings = { id: "corgi.computer" }
          }
        }
        BarIconButton { bar: verticalBarApi; text: "\uF028" }
      }
    }
  }

  FloatingWindow {
    title: "harness-card"
    implicitWidth: 392
    implicitHeight: 800
    color: Commons.Color.popups.background

    Rectangle {
      id: cardFrame
      anchors.fill: parent
      color: Commons.Color.popups.background
      border.color: Commons.Color.popups.border
      border.width: 2

      Loader {
        id: cardLoader
        x: 16; y: 16
        width: 360
        height: item ? item.implicitHeight : 0
      }
    }
  }

  function showCard() {
    cardLoader.setSource("file://" + shell.qml + "/Card.qml", { widget: w, maxHeight: 760 })
  }

  // Every panel open runs `corgi usage --json` once; nothing else may.
  property int opens: 0
  function openPanel() {
    opens++
    w.open()
  }

  FileView {
    id: usageFixture
    path: "/plugin/test/usage.json"
    blockLoading: true
  }

  FileView {
    id: usageReal
    path: "/tmp/scenario/usage-real.json"
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: corgiLog
    path: "/tmp/log/corgi.log"
    blockLoading: true
  }

  function usageReady() {
    return { until: function() { return shell.w.usageAccounts.length === 4 }, timeout: 4000, label: "usage read" }
  }

  // ------------------------------------------------------------ the run

  property var steps: []
  property int stepIndex: 0
  property var waiting: null
  property real waitStarted: 0

  Timer {
    id: runner
    onTriggered: shell.advance()
  }

  // A step returns nothing (wait 400 ms), a number of ms, or
  // { until: fn, timeout: ms, label: text }.
  function advance() {
    if (waiting) {
      if (waiting.until()) {
        waiting = null
      } else if (Date.now() - waitStarted > waiting.timeout) {
        check("in time: " + waiting.label, false)
        waiting = null
      } else {
        runner.interval = 50
        runner.start()
        return
      }
    }
    if (stepIndex >= steps.length) {
      console.log("failures: " + failures)
      Qt.quit()
      return
    }
    var result = steps[stepIndex++]()
    if (result && typeof result === "object") {
      waiting = result
      waitStarted = Date.now()
      runner.interval = 50
    } else {
      runner.interval = typeof result === "number" ? result : 400
    }
    runner.start()
  }

  function settled(label) {
    return { until: function() { return !shell.w.animating && !(shell.wv && shell.wv.animating) }, timeout: 3000, label: label }
  }

  function whenWidget(test, label) {
    return { until: test, timeout: 4000, label: label }
  }

  function setLight(light) {
    Commons.Color.foreground = light ? "#2a2a2a" : "#cacccc"
    Commons.Color.background = light ? "#f4f1ea" : "#101315"
    Commons.Color.accent = light ? "#2f6f9f" : "#7aa2f7"
    Commons.Color.urgent = light ? "#b23b3b" : "#e06c75"
    Commons.Color.muted = light ? "#8a8781" : "#707880"
  }

  Component.onCompleted: {
    setLight(false)
    steps = [
      function() {
        check("widget loaded", !!w && !!wv)
        check("not installed -> install", w.mode === "install")
        check("no marks while not installed", !w.workingMark && !w.attentionMark)
        check("tooltip says Install Corgi", w.tooltipText() === "Install Corgi")
        check("no lane while not installed", w.lane === 0 && w.implicitWidth === Style.bar.iconSlot)
        return 600
      },
      function() {
        shot(barStrip, "bar-install-dark")
        shot(verticalStrip, "vbar-install-dark")
        w.primaryAction()
        w.primaryAction() // a double click opens one terminal
      },
      function() {
        check("the widget points at Corgi's own folder, not the plugin's", w.corgiRoot === shell.corgiRoot)
        // The installer writes ~/.local/share/corgi, which Omarchy doesn't
        // watch: the widget sees `current` appear by itself, with no reload.
        sh("mkdir -p " + shell.corgiRoot + "/releases/R1 && cp /plugin/test/fake/corgi " + shell.corgiRoot
           + "/releases/R1/corgi && echo R1 > " + shell.corgiRoot + "/current")
        return whenWidget(function() { return w.installed && wv.installed }, "install seen without a reload")
      },
      function() {
        check("installed without a reload", w.installed && w.release === "R1")
        check("no line yet -> stopped", w.mode === "stopped")
        feed({ running: false })
        return whenWidget(function() { return true }, "")
      },
      function() { return 1300 },
      function() {
        check("running:false -> stopped, dimmed", w.mode === "stopped")
        shot(barStrip, "bar-stopped-dark")
        w.primaryAction() // no viewer window: opens Corgi in a terminal
        // An older Corgi, everything idle but one finished while away.
        var d = oldState()
        d.workspaces.forEach(function(ws) { ws.agents.forEach(function(a) { a.section = "idle"; a.needs_input = false; a.unread = false }) })
        feed(d)
        return whenWidget(function() { return w.mode === "running" }, "first running line")
      },
      function() { return settled("idle settles") },
      function() {
        check("running, all idle: no marks", !w.workingMark && !w.attentionMark)
        check("lane reserved while running", w.lane > 0 && w.implicitWidth === Style.bar.iconSlot + Math.ceil(w.lane))
        var m = marks(w)
        check("marks hidden at rest", m.dot && m.play && !m.dot.visible && !m.play.visible)
        check("old Corgi: status derived as idle", rowFor(12).status === "idle")
        shot(barStrip, "bar-idle-dark")
        shot(verticalStrip, "vbar-idle-dark")
        feed(liveState("idle", "working", "idle"))
        return whenWidget(function() { return w.workingMark }, "working mark")
      },
      function() { return settled("working settles") },
      function() {
        var m = marks(w)
        check("working: ▶ shown, ● not", m.play.visible && m.play.progress === 1 && !m.dot.visible)
        check("▶ is Corgi's mint", Qt.colorEqual(m.play.color, w.accent))
        check("nothing animates at rest", !w.animating && !wv.animating)
        shot(barStrip, "bar-working-dark")
        feed(liveState("needs_input", "working", "idle"))
        return whenWidget(function() { return w.attentionMark }, "needs mark")
      },
      function() { return settled("split settles") },
      function() {
        var m = marks(w)
        check("needs input: ● shown in Corgi's amber", m.dot.visible && Qt.colorEqual(m.dot.color, w.warm))
        check("two marks stack", m.dot.restY < m.play.restY && m.dot.restX === m.play.restX)
        check("corgi turns urgent (active)", w.needsCount === 1)
        shot(barStrip, "bar-needs-working-dark")
        shot(verticalStrip, "vbar-needs-working-dark")
        // Idle: nothing moves. Sample the geometry twice, half a second apart.
        shell.idleSample = [m.dot.centerX, m.dot.centerY, m.play.centerX, m.play.centerY].join(",")
        return 500
      },
      function() {
        var m = marks(w)
        check("idle: geometry unchanged and nothing animating",
              shell.idleSample === [m.dot.centerX, m.dot.centerY, m.play.centerX, m.play.centerY].join(",") && !w.animating)
        feed(liveState("ready", "working", "idle"))
        return whenWidget(function() { return w.needsCount === 0 && w.readyCount > 0 }, "ready instead of needs")
      },
      function() { return settled("ready settles") },
      function() {
        var m = marks(w)
        check("ready: ● Corgi's mint", m.dot.visible && Qt.colorEqual(m.dot.color, w.accent))
        shot(barStrip, "bar-ready-working-dark")
        feed(liveState("idle", "working", "idle"))
        return whenWidget(function() { return !w.attentionMark }, "ready mark gone")
      },
      function() { return settled("merge settles") },
      function() {
        var m = marks(w)
        check("● gone, ▶ back level with the corgi", !m.dot.visible && m.play.restY === m.dot.restY)
        feed(liveState("idle", "idle", "idle"))
        return whenWidget(function() { return !w.workingMark }, "working mark gone")
      },
      function() { return settled("out settles") },
      function() {
        var m = marks(w)
        check("all idle again: no marks visible", !m.dot.visible && !m.play.visible)
        check("nothing animates when idle", !w.animating)
        var keys = w.rows.map(function(r) { return r.key })
        check("one section still has its header", keys.indexOf("s:1:idle") === keys.indexOf("w:1") + 1)
        check("a workspace with no agents has no sections", keys.filter(function(k) { return k.indexOf("s:3:") === 0 }).length === 0)
        feed(liveState("ready", "working", "idle"))
        return whenWidget(function() { return w.workingMark && w.attentionMark }, "both at once")
      },
      function() { return settled("both settle") },
      function() {
        shot(barStrip, "bar-ready-working-dark")
        feed(liveState("ready", "idle", "idle"))
        return whenWidget(function() { return !w.workingMark }, "ready only")
      },
      function() { return settled("ready only settles") },
      function() {
        shot(barStrip, "bar-ready-dark")
        feed(liveState("needs_input", "idle", "ready"))
        return whenWidget(function() { return w.needsCount === 1 && !w.workingMark }, "needs only")
      },
      function() { return settled("needs only settles") },
      function() {
        shot(barStrip, "bar-needs-dark")
        // Animations off, as `omarchy toggle animations` sets.
        Style.reduceMotion = true
        shell.reduceWatch = true
        shell.expectInstant = true
        feed(liveState("needs_input", "working", "ready"))
        return whenWidget(function() { return w.workingMark }, "working with animations off")
      },
      function() { return 300 },
      function() {
        // Nothing needs you: without animation the corgi stays aside and an
        // empty dot holds the dot's place.
        feed(liveState("idle", "working", "idle"))
        return whenWidget(function() { return !w.attentionMark }, "no attention with animations off")
      },
      function() { return 300 },
      function() {
        var art = find(w, "corgiArt"), placeholder = find(w, "corgiPlaceholderMark")
        shell.check("animations off: the corgi stays aside", art.shift === 0)
        shell.check("animations off: an empty dot holds the dot's place", placeholder.visible)
        shell.check("animations off: ▶ keeps its stacked place", art.workingOffset > 0)
        return 0
      },
      function() {
        Style.reduceMotion = false
        shell.expectInstant = false
        feed(liveState("needs_input", "idle", "ready"))
        return whenWidget(function() { return !w.workingMark }, "working off with animations on")
      },
      function() { return settled("animations on settles") },
      function() {
        shell.reduceWatch = false
        // The full world, for the panel.
        feed(liveState("needs_input", "working", "ready", true))
        return whenWidget(function() { return w.readyCount === 2 && w.agents.length === 7 }, "full world")
      },
      function() { return settled("full world settles") },
      function() {
        check("needs/ready/working counts", w.needsCount === 1 && w.readyCount === 2 && w.workingCount === 1)
        check("status passes through", rowFor(22).status === "starting" && rowFor(21).status === "paused")
        check("unknown status -> other", rowFor(23).status === "other")
        check("detail kept as text", rowFor(21).detail === "Paused · <i>waiting</i>")
        check("headless key", w.rows.some(function(r) { return r.key === "h:h-7" }))
        check("markup kept as text", w.workspaces[1].name === "<b>site</b> & docs")
        check("links sit on their workspace's heading", w.rows[0].kind === "workspace"
              && w.rows[0].workspace.pointer === "Open Link \u2197 2" && w.rows[1].kind === "section")
        check("duplicate and invalid links are omitted", w.workspaces[0].links.length === 2)
        check("unlabeled links go by where they point", w.workspaces[1].links[0].label === ""
              && w.workspaces[1].links[0].url === "http://localhost:4000" && w.linkName(w.workspaces[1].links[0]) === "localhost:4000")
        check("tooltip strips markup", w.tooltipText().indexOf("<") === -1)
        check("paused unread is Corgi's mint", Qt.colorEqual(w.statusColor(rowFor(21)), w.accent))
        shot(barStrip, "bar-needs-working-dark")
        // From here a viewer has a window to raise.
        sh("touch /tmp/scenario/viewer")
        shell.openPanel()
        showCard()
        return 700
      },
      function() { return usageReady() },
      function() {
        var u = w.usageAccounts
        check("usage: four accounts in Corgi's order", u.length === 4 && u[0].provider === "codex" && u[1].provider === "claude")
        var climbs = function(win) {
          var used = win.bars.map(function(b) { return b.used }).filter(function(v) { return v !== null })
          return used.every(function(v, i) { return i === 0 || v >= used[i - 1] })
        }
        check("usage: every spark only climbs", u.every(function(a) { return a.windows.every(function(win) { return !win || climbs(win) }) }))
        // An older Corgi's month: last month's spend first, then a reading that dips.
        var old = w.normalWindow({ label: "mo", bars: [{ used: 80, tone: "earlier" }, { used: 10, tone: "accent" },
                                                       { used: 5, tone: "accent" }, { used: 20, tone: "accent" }] })
        check("usage: last month's spend drops out and a dip holds its height",
              JSON.stringify(old.bars.slice(0, 4).map(function(b) { return b.used })) === "[null,10,10,20]")
        check("usage: Pi on the same login folds into Codex", u[0].shared.length === 1 && u[0].shared[0].provider === "pi")
        check("usage: the weekly limit leads, then 5h", u[0].windows[0].label === "7d" && u[0].windows[1].label === "5h")
        check("usage: a metered workspace shows its month in credits", u[2].metered && u[2].windows[0].label === "mo"
              && u[2].windows[1] === null && u[2].amount.indexOf("\u26c1") === 0)
        check("usage: spend without a limit has no bar or figure", u[3].windows[0].used === null
              && u[3].windows[0].figure === "" && u[3].amount === "$8.20")
        check("usage: every group has a fourteen-bar spark, time left without height", u.every(function(a) {
          return a.windows.every(function(w) { return w === null || (w.bars.length === 14 && w.bars.every(function(b) {
            return b.tone !== "remaining" || b.used === null })) }) }))
        check("usage: spark tones map to the contract's colors",
              Qt.colorEqual(w.toneColor("remaining"), "#505a65") && Qt.colorEqual(w.toneColor("hot"), w.hot)
              && Qt.colorEqual(w.toneColor("accent"), w.accent) && Qt.colorEqual(w.toneColor("warm"), w.warm))
        var grid = cardLoader.item.usageGrid
        check("usage: columns, a name column and one spark width shared by every account", !!grid.first && !!grid.second
              && grid.bar > 0 && grid.name > 0 && grid.secondX > grid.firstWidth)
        check("usage: provider names", u[0].providerName === "Codex" && u[1].providerName === "Claude")
        var said = shownTexts(find(cardLoader.item, "usage"))
        check("usage: a metered month gives its credits for the percent, under the plan's name alone",
              said.indexOf("\u26c1155k / \u26c1250k") !== -1 && said.indexOf("62%") === -1 && said.indexOf("Enterprise") !== -1
              && said.indexOf("$8.20") !== -1 && said.every(function(t) { return t.indexOf("metered") === -1 }))
        check("usage: with both windows everywhere, nothing is missing", said.indexOf("\u2014") === -1)
        // Every brand mark the card asks for loads from icons/.
        var marks = []
        var walk = function(item) {
          if (!item) return
          if ("candidates" in item && item.known) marks.push(item)
          if (item.contentItem && item.contentItem !== item) walk(item.contentItem)
          for (var i = 0; i < item.children.length; i++) walk(item.children[i])
        }
        walk(cardLoader.item)
        var broken = marks.filter(function(m) { return !m.ready })
        if (broken.length) console.log("icon not loaded:", broken[0].provider, JSON.stringify(broken[0].candidates))
        check("brand icons load (" + marks.length + ")", marks.length >= 8 && broken.length === 0)
      },
      function() {
        var kp = keyboardPanel()
        check("keyboard panel open with content", !!kp && kp.open && !!kp.loadedContent && kp.loadedContentHeight > 0)
        shot(cardFrame, "panel-usage-dark")
        check("cursor starts on the agent that needs input", w.cursorKey === "p:12")
        var keys = w.rows.map(function(r) { return r.key })
        check("api by activity: working, then ready, each under its header",
              keys.slice(0, 6).join(" ") === "w:1 s:1:working p:12 p:13 s:1:ready p:14")
        check("site by activity: working, idle, done; no empty sections",
              keys.indexOf("s:2:working") < keys.indexOf("p:22") && keys.indexOf("p:22") < keys.indexOf("s:2:idle")
              && keys.indexOf("s:2:idle") < keys.indexOf("p:21") && keys.indexOf("s:2:done") < keys.indexOf("h:h-7")
              && keys.indexOf("s:2:ready") === -1)
        check("the list's model follows the rows", cardLoader.item && listKeys().join(" ") === keys.join(" "))
        check("rows just made appear at their size, not sliding open", !!rowItem("p:12") && rowItem("p:12").height > 0
              && rowItem("p:12").height === rowItem("p:12").fullHeight)
        shot(cardFrame, "panel-dark")
        // KeyboardPanel's own window, card and all.
        var top = kp ? kp.loadedContent : null
        while (top && top.parent) top = top.parent
        shot(top, "panel-real-dark")
      },
      function() {
        var real = usageReal.text()
        if (real === "") return 0
        w.applyUsage(real)
        check("usage: the real file reads", w.usageAccounts.length > 0)
        return 600
      },
      function() {
        if (usageReal.text() === "") return 0
        shot(cardFrame, "panel-usage-real-dark")
        return 400
      },
      function() {
        var lone = JSON.parse(usageFixture.text())
        lone.accounts[0].windows[1] = null
        w.applyUsage(JSON.stringify(lone))
        return 400
      },
      function() {
        var said = shownTexts(find(cardLoader.item, "usage"))
        var count = function(text) { return said.filter(function(t) { return t === text }).length }
        check("usage: an account with one window names the other faintly", count("\u2014") === 1 && count("5h") === 2
              && count("\u2502") === 2)
        shot(cardFrame, "panel-usage-lone-dark")
        w.applyUsage(usageFixture.text())
        feed(compactingState(1500))
        return whenWidget(function() { return !!find(cardLoader.item, "herd") }, "herding")
      },
      function() {
        var herd = find(cardLoader.item, "herd"), pile = find(cardLoader.item, "pile")
        check("compacting: only the compacting row has a herd and a pile", herd.visible && pile.visible
              && shell.countNamed(cardLoader.item, "herd") === 1 && shell.countNamed(cardLoader.item, "pile") === 1)
        check("compacting: the corgi herds the letters, some still scattered", !herd.narrow && !herd.finished
              && herd.lit[0] && herd.lit.some(function(l) { return !l }) && herd.dogText.indexOf("o[") === 1)
        check("compacting: the letters move every frame", herd.letterX.length === 10 && herd.letterX[9] > herd.letterX[0])
        check("compacting: dots fall green and cool to gray in 400 ms", pile.visible
              && Qt.colorEqual(pile.colorAt(0), w.accent) && Qt.colorEqual(pile.colorAt(400), w.muted)
              && !Qt.colorEqual(pile.colorAt(150), w.accent) && !Qt.colorEqual(pile.colorAt(150), w.muted))
        var g = herd.geo, home = herd.word.length * herd.cell + herd.cell / 2
        var sit = herd.melt(0, "~"), late = herd.melt(15, "~"), done = herd.melt(16, "~"), xs = []
        for (var q = 10; q <= 16; q += 0.25) xs.push(herd.melt(q, "~").noseDot.x)
        check("compacting: the ellipsis and bullet measure up", g.dw > 0 && g.dw <= g.dh && g.ew > g.dw
              && g.eyeY - g.eh / 2 > g.dotY + g.dh / 2 && g.dots[0] < g.dots[1] && g.dots[1] < g.dots[2])
        check("compacting: the corgi sits with its tail, ears and bullet eyes", sit.tail.opacity === 1 && sit.earL.opacity === 1
              && sit.eyeL.w === g.ew && sit.noseDot.opacity === 0 && sit.ellipsis.opacity === 0)
        check("compacting: its face only ever moves left, toward the word",
              xs.every(function(x, i) { return i === 0 || x <= xs[i - 1] }) && xs[0] > xs[xs.length - 1])
        check("compacting: the dots close up evenly",
              Math.abs((late.noseDot.x - late.eyeL.x) - (late.eyeR.x - late.noseDot.x)) < 0.01)
        check("compacting: curled up, the dots lie on the font's own ellipsis and give way to it", done.ellipsis.opacity === 1
              && done.ellipsis.x === home && done.eyeL.opacity === 0 && Math.abs(done.eyeL.x - (home + g.dots[0])) < 0.01
              && Math.abs(done.eyeR.x - (home + g.dots[2])) < 0.01 && Math.abs(done.eyeL.h - g.dh) < 0.01)
        shot(cardFrame, "panel-compacting-dark")
        feed(compactingState(65000))
        return whenWidget(function() {
          var herd = find(cardLoader.item, "herd")
          return !!herd && herd.since < Date.now() - 60000 && herd.finished
        }, "compacting for a minute")
      },
      function() {
        var herd = find(cardLoader.item, "herd")
        check("compacting: curled up into the ellipsis, the time so far at the right", herd.finished
              && herd.dogText === "\u2026" && herd.took.indexOf("1m ") === 0 && herd.lit.every(function(l) { return l }))
        shot(cardFrame, "panel-compacted-dark")
        return 400
      },
      function() {
        // Back to the middle of the curl, for a picture of it.
        var herd = find(cardLoader.item, "herd")
        herd.since = Date.now() - (herd.cells - herd.word.length + 1 + 14) * 110
        return 0
      },
      function() {
        var herd = find(cardLoader.item, "herd")
        check("compacting: mid-curl, the corgi is drawn part by part", herd.melting && !herd.finished)
        shot(cardFrame, "panel-curling-dark")
        feed(liveState("needs_input", "working", "ready", true))
        return whenWidget(function() { return !find(cardLoader.item, "herd") }, "compaction over")
      },
      function() {
        check("compaction over: the activity line is back, the herd and pile gone",
              !find(cardLoader.item, "herd") && !find(cardLoader.item, "pile"))
        return 0
      },
      function() {
        w.applyUsage('{"running":false,"accounts":[]}')
        check("usage: no daemon, no section", w.usageAccounts.length === 0)
        w.applyUsage("not json")
        check("usage: bad output, no section", w.usageAccounts.length === 0)
        w.applyUsage('{"running":true,"accounts":[{"provider":"../../etc","windows":[{"label":"5h","used":"lots"},7]}]}')
        var odd = w.usageAccounts[0]
        check("usage: odd input normalized", odd.provider === "" && odd.windows[0].used === null && odd.windows[1] === null
              && odd.windows[0].bars.length === 14 && odd.windows[0].bars[0].tone === "unread")
        w.applyUsage('{"running":true,"accounts":[{"provider":"opencode","windows":[]},'
                     + '{"provider":"claude","windows":[null,{"label":"5h","used":5,"figure":"5%","reset":"1h"}]}]}')
        check("usage: an account with no limits never shows", w.usageAccounts.length === 1
              && w.usageAccounts[0].provider === "claude")
        w.applyUsage(usageFixture.text())
        check("usage: fixture again", w.usageAccounts.length === 4)
      },
      function() {
        w.moveCursor(1)
        check("cursor moves to the next agent", w.cursorKey === "p:13")
        w.moveCursor(-1)
        w.moveCursor(-1)
        check("up from the first agent reaches its section's header", w.cursorKey === "s:1:working")
        w.moveCursor(-1)
        check("then its workspace's heading, on its fold", w.cursorKey === "w:1" && w.cursorPart === "")
        w.moveCursorX(1)
        check("right moves to the heading's links", w.cursorPart === "links")
        w.moveCursorX(1)
        check("then to New +", w.cursorPart === "new")
        w.moveCursorX(1)
        check("and stops there", w.cursorPart === "new")
        w.moveCursorX(-1)
        w.activateCursor()
        check("several links list under the heading", w.opened && w.linksOpen === "w:1"
              && w.rows[1].kind === "link" && w.rows[2].kind === "link" && w.rows[3].kind === "section"
              && w.rows[4].kind === "agent")
        return 400
      },
      function() {
        // grabToImage renders on the next frame, so opening a link waits for it.
        shot(cardFrame, "panel-links-dark")
        return 300
      },
      function() {
        w.moveCursor(1)
        check("down reaches the first link", w.cursorKey === w.rows[1].key && w.rows[1].link.label === "API preview")
        w.activateCursor()
        check("opening a link closes the panel", !w.opened)
        return 1700
      },
      function() {
        shell.openPanel()
        check("the list closes with the panel", w.linksOpen === "" && w.rows[1].kind === "section")
        w.cursorKey = "w:1"
        w.moveCursor(-1)
        check("up from the first heading's links reaches the header", w.cursorKey === "")
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        w.moveCursor(1)
        check("cursor walks every heading, section and agent to the next workspace's first agent", w.cursorKey === "p:22")
        w.moveCursor(-1)
        w.moveCursor(-1)
        w.activateCursor()
        check("Enter on a heading folds its workspace", w.isFolded("workspaces", 2))
        w.activateCursor()
        w.moveCursor(1)
        w.activateCursor()
        check("Enter on a section folds it", w.isFolded("sections", "2:working"))
        w.activateCursor()
        w.moveCursor(1)
        w.cursorKey = ""
        w.cursorPart = ""
        w.moveCursorX(1)
        check("right from the header reaches its counts", w.cursorPart === "needs")
        w.activateCursor()
        check("Enter on a count keeps its filter", w.filterPinned === "needs")
        w.activateCursor()
        check("and again drops it", w.filterPinned === "")
        w.cursorPart = ""
        w.cursorKey = "p:22"
        cardLoader.item.collapseEmptyDetail = true
        return 300
      },
      function() {
        shot(cardFrame, "panel-dark-collapsed")
        return 300
      },
      function() {
        // grabToImage renders on the next frame, so the reset waits for it.
        cardLoader.item.collapseEmptyDetail = false
        w.activateCursor() // focus pane 22 in viewer 1, raise its window
        check("acting closes the panel", !w.opened)
        return 300
      },
      function() {
        shell.openPanel()
        return 500
      },
      function() {
        shell.moving = rowItem("p:13")
        check("a working row has its own item", !!shell.moving && shell.moving.group === "working")
        // 13 finishes, and is starred elsewhere: 14 heads a new starred section.
        var d = liveState("needs_input", "ready", "ready", true)
        d.workspaces[0].agents[2].starred = true
        feed(d)
        return whenWidget(function() { return rowFor(13) && rowFor(13).group === "ready" }, "13 moves to ready")
      },
      function() {
        var keys = w.rows.map(function(r) { return r.key })
        check("starred first, above the sections", keys.slice(0, 7).join(" ") === "w:1 s:1:starred p:14 s:1:working p:12 s:1:ready p:13")
        check("the moved row is the same item, now in ready", rowItem("p:13") === shell.moving && shell.moving.shownGroup === "ready")
        check("it lands with the accent tint", shell.moving && shell.moving.landingAnimation.running)
        return 150
      },
      function() {
        shot(cardFrame, "panel-moving-dark")
        return 1800
      },
      function() {
        check("the tint fades once it has landed", shell.moving && !shell.moving.landingAnimation.running)
        check("the list's model follows the rows after a move", listKeys().join(" ") === w.rows.map(function(r) { return r.key }).join(" "))
        shot(cardFrame, "panel-starred-dark")
        w.close()
        return 400
      },
      function() {
        shell.openPanel()
        heightProbe.samples = []
        heightProbe.start()
        return 60
      },
      function() {
        // The panel builds its card hidden as it opens, then shows it. 60 ms
        // in (Omarchy's panel snaps to its content until then, and animates
        // any later change), a heading that waited to be on screen to take
        // its height would still be short of it.
        var kp = keyboardPanel()
        var list = kp && kp.loadedContent ? find(kp.loadedContent, "agentList") : null
        var heading = null
        if (list) for (var i = 0; i < list.contentItem.children.length; i++)
          if (list.contentItem.children[i].key === "w:1") heading = list.contentItem.children[i]
        check("opening the panel, a workspace heading is at its size at once",
              !!heading && heading.height > 0 && heading.height === heading.fullHeight)
        shell.openedHeight = kp ? kp.loadedContentHeight : -1
        return 600
      },
      function() {
        var kp = keyboardPanel()
        check("and the panel doesn't grow after it opens", !!kp && kp.loadedContentHeight === shell.openedHeight)
        return 10
      },
      function() {
        // 14 is starred and unread; 13 and 21 are unread too; 12 waits on you.
        var button = find(cardLoader.item, "count-unread")
        check("each count is a button", !!button && button.visible && !!find(cardLoader.item, "count-needs"))
        w.enterKind("unread")
        return 600
      },
      function() {
        shot(cardFrame, "panel-unread-dark")
        check("pointing at unread previews only those",
              rowItem("p:12").height === 0 && rowItem("s:1:working").height === 0 && rowItem("w:3").height === 0
              && rowItem("p:13").height > 0 && rowItem("p:21").height > 0 && rowItem("w:2").height > 0)
        check("the cursor skips what's filtered out", w.actionIndexes().every(function(i) { return w.rowShown(w.rows[i]) }))
        w.leaveKind("unread")
        return 600
      },
      function() {
        check("and leaving brings the rest back", rowItem("p:12").height > 0 && rowItem("w:3").height > 0)
        w.enterKind("needs")
        w.clickKind("needs")
        w.leaveKind("needs")
        check("a click keeps a filter after the pointer leaves", w.filterKind === "needs" && w.filterPinned === "needs")
        w.enterKind("unread")
        check("pointing at another previews it over the kept one", w.filterKind === "unread")
        w.clickKind("unread")
        check("clicking another moves the filter to it", w.filterPinned === "unread")
        w.clickKind("unread")
        w.enterKind("unread")
        check("clicking the kept one drops it, and it stays dropped under the pointer", w.filterKind === "" && w.filterPinned === "")
        w.leaveKind("unread")
        w.enterKind("unread")
        check("until the pointer comes back", w.filterKind === "unread")
        w.leaveKind("unread")
        // Folds: a workspace, then a section.
        w.toggleFold("workspaces", 2)
        w.toggleFold("sections", "1:working")
        return 600
      },
      function() {
        shot(cardFrame, "panel-folded-dark")
        check("a folded workspace keeps only its heading", rowItem("w:2").height > 0 && rowItem("s:2:working").height === 0
              && rowItem("p:22").height === 0)
        check("a folded section keeps its header", rowItem("s:1:working").height > 0 && rowItem("p:12").height === 0
              && rowItem("p:13").height > 0 && rowItem("p:14").height > 0)
        w.enterKind("needs")
        check("a count's filter still shows its kind inside a fold", w.rowShown(w.rowMap["p:12"]))
        w.leaveKind("needs")
        foldsFile.reload()
        return 800
      },
      function() {
        var saved = {}
        try { saved = JSON.parse(foldsFile.text()) } catch (e) {}
        check("folds are saved beside Omarchy's plugin state",
              !!saved.workspaces && saved.workspaces.indexOf("2") !== -1 && saved.sections.indexOf("1:working") !== -1)
        w.toggleFold("workspaces", 2)
        w.toggleFold("sections", "1:working")
        // A long idle section: its latest two, then "… 3 more".
        var d = liveState("idle", "idle", "idle", true)
        for (var i = 0; i < 2; i++)
          d.workspaces[0].agents.push(agent(15 + i, "Idle agent " + i, "codex", "idle", "idle", ""))
        feed(d)
        return whenWidget(function() { return !!w.rowMap["m:1"] }, "five idle agents")
      },
      function() {
        var keys = w.rows.map(function(r) { return r.key })
        var idle = w.rows.filter(function(r) { return r.kind === "agent" && r.workspace.id === 1 })
        check("a long idle section folds all but two under a more row",
              idle.filter(function(r) { return w.rowShown(r) }).length === 2 && w.rowMap["m:1"].count === 3
              && keys.indexOf("m:1") > keys.indexOf("s:1:idle"))
        w.toggleFold("idle", 1)
        check("opening it shows them all", idle.every(function(r) { return w.rowShown(w.rowMap[r.key]) }) && w.rowMap["m:1"].open)
        w.toggleFold("idle", 1)
        feed(liveState("needs_input", "working", "ready", true))
        w.close()
        return whenWidget(function() { return !w.rowMap["m:1"] }, "back to the full world")
      },
      function() {
        shell.openPanel()
        return 400
      },
      function() {
        w.newTab(w.workspaces[0]) // workspace switch 1, then action new-agent, in viewer 1
        return 1700
      },
      function() {
        // An older Corgi again: statuses derived from section and flags.
        feed(oldState())
        return whenWidget(function() { return rowFor(24) !== null }, "old-format line")
      },
      function() {
        check("old Corgi: needs_input derived", rowFor(12).status === "needs_input")
        check("old Corgi: working derived", rowFor(13).status === "working")
        check("old Corgi: ready derived", rowFor(14).status === "ready")
        check("old Corgi: idle and unread counts as ready", rowFor(24).status === "ready")
        check("old Corgi: no detail", rowFor(13).detail === "")
        check("old Corgi: no links section", w.rows[0].kind === "workspace")
        feed(liveState("needs_input", "working", "ready", true))
        return 1600
      },
      "scrubs",
      function() {
        feed(liveState("needs_input", "working", "ready", true))
        return 1600
      },
      function() {
        w.activateCursor() // cursor is empty: opens Corgi (raises the viewer's window)
        return 400
      },
      function() {
        shell.openPanel()
        return usageReady()
      },
      function() {
        setLight(true)
        showCard()
        return 600
      },
      function() {
        shot(cardFrame, "panel-usage-light")
        w.close()
        return 300
      },
      function() {
        shot(barStrip, "bar-needs-working-light")
        shot(verticalStrip, "vbar-needs-working-light")
        shot(cardFrame, "panel-light")
        feed(liveState("idle", "working", "idle"))
        return whenWidget(function() { return !w.attentionMark }, "light working")
      },
      function() { return settled("light working settles") },
      function() {
        shot(barStrip, "bar-working-light")
        feed(liveState("ready", "idle", "idle"))
        return whenWidget(function() { return !w.workingMark && w.attentionMark }, "light ready")
      },
      function() { return settled("light ready settles") },
      function() {
        shot(barStrip, "bar-ready-light")
        feed(liveState("idle", "idle", "idle"))
        return whenWidget(function() { return !w.attentionMark }, "light idle")
      },
      function() { return settled("light idle settles") },
      function() {
        shot(barStrip, "bar-idle-light")
        sh("pkill -f 'tail -n 1 -F'")
        return whenWidget(function() { return w.mode === "stopped" }, "watch exit -> stopped")
      },
      function() {
        shot(barStrip, "bar-stopped-light")
        return whenWidget(function() { return w.mode === "running" }, "watch restarted")
      },
      function() {
        sh("cd " + shell.corgiRoot + " && mkdir -p releases/R2 && cp /plugin/test/fake/corgi releases/R2/corgi && echo R2 > current.tmp && mv current.tmp current")
        return whenWidget(function() { return w.release === "R2" }, "update moves the pin")
      },
      function() { return whenWidget(function() { return w.mode === "running" }, "watch runs the new release") },
      function() {
        w.focusAgent(w.rows.find(function(r) { return r.key === "h:h-7" }).agent)
        return 1700
      },
      function() {
        sh("rm -f /tmp/scenario/viewer")
      },
      function() {
        w.openCorgi() // no viewer window left: opens Corgi in a terminal
        sh("rm -f " + shell.corgiRoot + "/current")
        return whenWidget(function() { return w.mode === "install" }, "removing current -> install")
      },
      function() {
        corgiLog.reload()
        var runs = corgiLog.text().split("\n").filter(function(l) { return l === "usage --json" }).length
        check("usage runs once per panel open and never otherwise (" + runs + " for " + shell.opens + ")", runs === shell.opens)
        check("removed: back to install, no lane", !w.installed && w.lane === 0)
        shot(barStrip, "bar-install-light")
        return 400
      },
      function() {
        // Installed again: seen again, still with no reload.
        sh("echo R2 > " + shell.corgiRoot + "/current")
        return whenWidget(function() { return w.installed && w.release === "R2" }, "a reinstall is seen too")
      }
    ]
    var expanded = []
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] === "scrubs") expanded.push(function() {
        var list = shell.steps.slice(0, shell.stepIndex).concat(shell.scrubs(), shell.steps.slice(shell.stepIndex))
        shell.steps = list
      })
      else expanded.push(steps[i])
    }
    steps = expanded
    runner.interval = 800
    runner.start()
  }

  property string idleSample: ""
}
