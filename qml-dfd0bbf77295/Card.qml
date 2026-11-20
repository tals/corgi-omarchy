pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "corgi/motion.mjs" as Motion

// The panel's content, built from the shell's own panel parts: a hero with
// Corgi's corgi and the way into Corgi, each account's usage, then every
// workspace (a section header, pointing at its links) with its agents under
// it in Corgi's activity sections. An agent row reads like a row of Corgi's
// sidebar: its glyph and title, its provider, and on the line below what it
// is doing. A click (or Enter on the keyboard cursor) selects its pane in the
// most recently active viewer that has a window and raises that window.
//
// Everything is read through `widget`, which owns the data and the actions.
PanelKeyCatcher {
  id: card

  property var widget: null
  // How tall the card may grow; the list scrolls past it.
  property real maxHeight: Style.space(480)
  // A row keeps its two-line height when the agent has no detail, so rows
  // don't jump as details come and go; its title then sits in the middle.
  // True drops the empty line instead.
  property bool collapseEmptyDetail: false

  readonly property string iconOpen: "\uF120"
  readonly property string iconInstall: "\uF063"
  readonly property bool listShown: widget.mode === "running" && widget.rows.length > 0
  readonly property bool usageShown: widget.mode === "running" && widget.usageAccounts.length > 0
  // Omarchy's agents plugin picks a white mark's -light twin on a light panel.
  readonly property bool lightSurface: Commons.Color.popups.background.hslLightness >= 0.5
  // Beside the QML, in the plugin folder.
  readonly property string iconDir: widget.qmlDir + "/icons"

  implicitHeight: column.implicitHeight

  // Everything in the column that is not the list, so the list knows how much
  // room it has.
  readonly property real chrome: header.height
    + (messageBox.visible ? messageBox.height + column.spacing : 0)
    + (versionLine.visible ? versionLine.height + column.spacing : 0)
    + (rule.visible ? rule.height + column.spacing * 2 : 0)
  // Usage takes at most half the card; the agents list the rest.
  readonly property real usageCap: Math.max(Style.space(160), card.maxHeight * 0.5)
  // The columns every account's usage line shares, as Manage agents sizes
  // them: each slot's widest label, percent and reset (resets as wide as
  // "23h 59m", so the columns hold still as they tick), and one spark width
  // for every row: the room left, or none when too little is. Names share a
  // column too, so the emails after them line up.
  readonly property real sparkHeight: Style.space(14)
  // An account with one of the two windows names the other faintly in its
  // slot, so its line keeps the shape of the rest; a metered account's
  // credits stand where its percent would, so it has no second slot.
  function usageNote(account, i) {
    if (account.amount !== "" || account.windows[i] !== null || account.windows[1 - i] === null) return ""
    var accounts = card.widget.usageAccounts
    for (var k = 0; k < accounts.length; k++) if (accounts[k].windows[i]) return accounts[k].windows[i].label
    return i === 0 ? "7d" : "5h"
  }
  readonly property var usageGrid: {
    var accounts = card.widget.usageAccounts
    var m = usageMetrics
    var slot = function(i) {
      var out = null
      for (var k = 0; k < accounts.length; k++) {
        var w = accounts[k].windows[i]
        var note = card.usageNote(accounts[k], i)
        if (!w && note === "") continue
        if (!out) out = { label: 0, figure: 0, reset: 0, note: true }
        out.label = Math.max(out.label, m.advanceWidth(w ? w.label : note))
        if (!w) continue
        if (out.note) {
          out.note = false
          out.figure = m.advanceWidth("100%")
          out.reset = m.advanceWidth("23h 59m")
        }
        out.figure = Math.max(out.figure, m.advanceWidth(w.figure))
        out.reset = Math.max(out.reset, m.advanceWidth(w.reset))
      }
      return out
    }
    var first = slot(0), second = slot(1)
    var gap = Style.space(6), wide = Style.space(10), sep = m.advanceWidth(" \u2502 ")
    var dash = m.advanceWidth("\u2014")
    // A slot's width without its spark.
    var fixed = function(s) { return !s ? 0 : s.note ? s.label + gap + dash : s.label + gap * 2 + s.figure + wide + s.reset }
    var indent = Style.font.body + Style.space(6)
    var room = usageColumn.width - indent - fixed(first) - (first && second ? sep : 0) - fixed(second)
    var sparks = (first && !first.note ? 1 : 0) + (second && !second.note ? 1 : 0)
    var room_each = sparks > 0 ? Math.floor(room / sparks) : 0
    // A metered line is its month's label, spark, credits and reset.
    for (var k = 0; k < accounts.length; k++) {
      if (accounts[k].amount === "" || !first) continue
      room_each = Math.min(room_each, usageColumn.width - indent - first.label - gap * 2
        - m.advanceWidth(accounts[k].amount) - wide - first.reset)
    }
    var bar = room_each >= Style.space(24) ? Math.min(room_each, Style.space(72)) : 0
    var width = function(s) {
      if (!s) return 0
      return s.note ? fixed(s) : s.label + gap + (bar > 0 ? bar + gap : 0) + s.figure + wide + s.reset
    }
    var firstWidth = width(first)
    var name = 0
    for (var k = 0; k < accounts.length; k++) name = Math.max(name, nameMetrics.advanceWidth(accounts[k].providerName))
    return { first: first, second: second, gap: gap, wide: wide, sep: sep, bar: bar, name: name,
             firstWidth: firstWidth, secondX: first ? firstWidth + sep : 0 }
  }
  readonly property real usageBlock: card.usageShown ? usageFlick.height + usageRule.height + column.spacing * 2 : 0
  readonly property real listCap: Math.max(Style.space(80), card.maxHeight - card.chrome - card.usageBlock)

  function showRow(index) {
    list.positionViewAtIndex(index, ListView.Contain)
  }

  // A drawn chevron: right when folded, down when open. Centered on the
  // shape itself, so it lines up with text by its middle, not its glyph box.
  component Chevron: Shape {
    id: chevron
    property bool open: false
    property color ink: "gray"
    property real size: 9
    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer
    rotation: open ? 90 : 0
    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    ShapePath {
      strokeColor: chevron.ink
      strokeWidth: 1.6
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: chevron.size * 0.35
      startY: chevron.size * 0.18
      PathLine { x: chevron.size * 0.7; y: chevron.size * 0.5 }
      PathLine { x: chevron.size * 0.35; y: chevron.size * 0.82 }
    }
  }

  // ------------------------------------------------------ the rows

  // The list's rows by key, so a row that changes place stays the same item
  // and travels there. Each new list from the widget becomes the removals,
  // moves and inserts that turn the old one into it.
  ListModel { id: rowModel }
  // Rows already there when the card opens appear with it, not one by one.
  property bool settled: false
  function syncRows() {
    var rows = card.widget.rows
    var want = {}
    for (var i = 0; i < rows.length; i++) want[rows[i].key] = true
    for (var i = rowModel.count - 1; i >= 0; i--)
      if (!want[rowModel.get(i).key]) rowModel.remove(i)
    for (var i = 0; i < rows.length; i++) {
      if (i < rowModel.count && rowModel.get(i).key === rows[i].key) continue
      var from = -1
      for (var j = i + 1; j < rowModel.count; j++)
        if (rowModel.get(j).key === rows[i].key) { from = j; break }
      if (from >= 0) rowModel.move(from, i, 1)
      else rowModel.insert(i, { key: rows[i].key, kind: rows[i].kind })
    }
  }
  Connections {
    target: card.widget
    function onRowsChanged() { card.syncRows() }
  }
  Component.onCompleted: {
    syncRows()
    Qt.callLater(function() { card.settled = true })
    tick()
  }

  // The terminal's timing: a row glides to its new place, eased in and out;
  // the others make room the same way.
  readonly property int glideMs: Style.duration(300)

  onCloseRequested: widget.close()
  onMoveRequested: function(dx, dy) {
    if (dy !== 0) widget.moveCursor(dy)
    else if (dx !== 0) widget.moveCursorX(dx)
  }
  // Only activateRequested, never returnRequested as well: Enter fires both.
  onActivateRequested: widget.activateCursor()
  onTabRequested: function(direction) { widget.switchPanel(direction) }
  onTextKey: function(t) { if (t === "o") widget.primaryAction() }

  // ------------------------------------------------- Corgi's animations

  // Each animated row's activity glyph and second line, from Corgi's own
  // animation code, by agent key. They move only while the panel is open and
  // the shell animates; otherwise each shows one still frame.
  property var frames: ({})
  readonly property var animated: {
    var out = []
    var list = card.widget.agents || []
    for (var i = 0; i < list.length; i++)
      if (list[i].glyph !== "none" || list[i].corgi !== "content") out.push(list[i])
    return out
  }
  // Columns a row's second line has for a corgi.
  readonly property int room: Math.max(10,
    Math.floor((list.width - Style.space(56)) / Math.max(1, detailMetrics.advanceWidth("M"))))
  onAnimatedChanged: tick()
  onRoomChanged: tick()

  function hexOf(color) {
    var text = String(color)
    return text.length === 9 ? "#" + text.slice(3) : text
  }
  function tick() {
    Motion.theme(hexOf(card.widget.foreground), hexOf(Commons.Color.popups.background), hexOf(card.widget.accent))
    var rows = []
    for (var i = 0; i < card.animated.length; i++) {
      var a = card.animated[i]
      rows.push({ key: a.key, glyph: a.glyph, corgi: a.corgi, room: card.room,
                  working: a.status === "working", bright: a.status === "ready" || a.unread, since: a.since })
    }
    var out = rows.length ? Motion.frame(Date.now(), rows) : []
    var map = {}
    for (var j = 0; j < rows.length; j++) map[rows[j].key] = out[j]
    card.frames = map
    motionTimer.interval = Math.max(40, Motion.delay())
  }
  Timer {
    id: motionTimer
    interval: 75
    repeat: true
    running: card.visible && card.animated.length > 0 && card.widget.motion
    onTriggered: card.tick()
  }

  FontMetrics {
    id: detailMetrics
    font.family: card.widget.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(12)

    // Corgi's corgi and name, and what its agents are up to, as the
    // sidebar's glyphs. The whole of it opens Corgi, installing or starting
    // it first if it must; the unread count opens the next unread agent,
    // and while the pointer rests on it the list shows only those.
    CursorSurface {
      id: header
      width: parent.width
      implicitHeight: Math.max(headerIcon.implicitHeight, headerLabels.implicitHeight) + Style.space(12)
      hasCursor: card.listShown && card.widget.onCursor("", "")
      foreground: card.widget.foreground

      MouseArea {
        id: headerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) card.widget.setCursor("", "")
        onClicked: card.widget.primaryAction()
      }

      // Corgi's corgi in its own colors, which read on light and dark
      // themes alike; the bar's stays one color, as the bar's icons are.
      Item {
        id: headerIcon
        x: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.round(Style.font.display * 1.4)
        implicitHeight: implicitWidth
        width: implicitWidth
        height: implicitHeight
        opacity: card.widget.mode === "stopped" ? 0.5 : 1.0

        Image {
          anchors.fill: parent
          source: Qt.resolvedUrl("corgi-color.png")
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
        }
        // Not installed yet: the shell's corner mark, as the bar shows it.
        Rectangle {
          visible: card.widget.mode === "install"
          width: Math.max(9, parent.width * 0.32)
          height: width
          radius: width / 2
          color: card.widget.accent
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          Text {
            anchors.centerIn: parent
            text: card.iconInstall
            textFormat: Text.PlainText
            color: Commons.Color.popups.background
            font.family: card.widget.fontFamily
            font.pixelSize: parent.width * 0.62
          }
        }
      }

      Column {
        id: headerLabels
        anchors.left: headerIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: openMark.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          text: "Corgi"
          textFormat: Text.PlainText
          color: card.widget.foreground
          font.family: card.widget.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // Not running, or nothing to count: said in words.
        Text {
          visible: !counts.visible
          text: card.widget.mode !== "running" ? card.widget.summaryText()
            : (card.widget.agents.length > 0 ? "All idle" : "No agents")
          textFormat: Text.PlainText
          color: card.widget.muted
          font.family: card.widget.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Waiting on you, at work, unread: each a button that filters the
        // list to its kind. Pointing previews; a click keeps it.
        Row {
          id: counts
          visible: card.widget.mode === "running"
            && (card.widget.needsCount + card.widget.workingCount + card.widget.readyCount) > 0
          spacing: Style.space(10)

          Repeater {
            model: card.widget.kinds

            delegate: Rectangle {
              id: kindChip
              required property string modelData
              readonly property int count: card.widget.kindCount(modelData)
              readonly property color ink: modelData === "needs" ? card.widget.warm : card.widget.accent
              readonly property bool kept: card.widget.filterPinned === modelData
              readonly property bool hot: kindMouse.containsMouse || card.widget.onCursor("", modelData)
              objectName: "count-" + modelData
              visible: count > 0
              width: kindRow.implicitWidth + Style.space(14)
              height: kindRow.implicitHeight + Style.space(6)
              radius: Style.cornerRadius
              // Lit while its filter shows, kept or previewed.
              readonly property bool showing: card.widget.filterKind === modelData
              color: kept ? Util.alpha(ink, 0.16) : (showing ? Util.alpha(ink, 0.09) : "transparent")
              border.color: kept || hot ? ink : Util.alpha(ink, 0.35)
              border.width: card.widget.onCursor("", modelData) ? 2 : 1
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }

              Row {
                id: kindRow
                anchors.centerIn: parent
                spacing: Style.space(5)
                StatusGlyph {
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.font.bodySmall
                  status: kindChip.modelData === "needs" ? "needs_input" : (kindChip.modelData === "working" ? "working" : "ready")
                  color: kindChip.ink
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: kindChip.count
                  textFormat: Text.PlainText
                  color: card.widget.foreground
                  font.family: card.widget.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              MouseArea {
                id: kindMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  card.widget.setCursor("", kindChip.modelData)
                  card.widget.enterKind(kindChip.modelData)
                }
                onExited: card.widget.leaveKind(kindChip.modelData)
                onClicked: card.widget.clickKind(kindChip.modelData)
              }
            }
          }
        }
      }

      // What a press does: open Corgi, or install it.
      Text {
        id: openMark
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: card.widget.mode === "install" ? card.iconInstall : card.iconOpen
        textFormat: Text.PlainText
        color: headerMouse.containsMouse || header.hasCursor ? card.widget.accent : card.widget.foreground
        font.family: card.widget.fontFamily
        font.pixelSize: Style.font.title
      }
    }

    // ------------------------------------------------------- usage

    PanelSeparator {
      id: usageRule
      visible: card.usageShown
      foreground: card.widget.foreground
    }

    // Corgi's usage card: each account's limits, drawn as bars.
    Flickable {
      id: usageFlick
      objectName: "usage"
      width: parent.width
      visible: card.usageShown
      // By what it holds, never by whether it's on screen yet: the panel
      // builds its content hidden, and a height that waited for that would
      // grow as the panel shows, sliding everything under it.
      height: card.usageShown ? Math.min(contentHeight, card.usageCap) : 0
      contentHeight: usageColumn.implicitHeight
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: usageColumn
        width: usageFlick.width - (usageFlick.interactive ? Style.space(10) : 0)
        spacing: Style.space(12)

        PanelSectionHeader {
          text: "Usage"
          foreground: card.widget.foreground
          fontFamily: card.widget.fontFamily
        }

        Repeater {
          model: card.usageShown ? card.widget.usageAccounts : []

          delegate: Column {
            id: account
            required property var modelData
            // Rows line up under the provider's name.
            readonly property real indent: Style.font.body + Style.space(6)
            width: usageColumn.width
            spacing: Style.space(6)

            // Provider, account and the sign-ins folded into it, and the plan.
            Item {
              width: parent.width
              height: Math.max(accountMark.height, accountTitle.implicitHeight)

              ProviderIcon {
                id: accountMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                provider: account.modelData.provider
                size: Style.font.body
                iconDir: card.iconDir
                lightSurface: card.lightSurface
              }

              Text {
                id: accountTitle
                anchors.left: parent.left
                anchors.leftMargin: account.indent
                anchors.verticalCenter: parent.verticalCenter
                text: account.modelData.providerName
                textFormat: Text.PlainText
                font.family: card.widget.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                color: card.widget.foreground
              }

              Text {
                id: accountWho
                anchors.left: parent.left
                anchors.leftMargin: account.indent + card.usageGrid.name + Style.space(8)
                anchors.baseline: accountTitle.baseline
                width: Math.min(implicitWidth, Math.max(0, accountPlan.x - x - sharedMarks.width - Style.space(12)))
                text: [account.modelData.name, account.modelData.email]
                  .filter(function(s) { return s !== "" }).join(" · ")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: card.widget.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: Util.alpha(card.widget.foreground, 0.72)
              }

              // Other harnesses signed in through this login, as small marks.
              Row {
                id: sharedMarks
                anchors.left: accountWho.right
                anchors.leftMargin: accountWho.text !== "" ? Style.space(6) : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Repeater {
                  model: account.modelData.shared

                  delegate: Item {
                    id: sharedMark
                    required property var modelData
                    width: sharedIcon.ready ? sharedIcon.width : sharedName.implicitWidth
                    height: Style.font.bodySmall

                    ProviderIcon {
                      id: sharedIcon
                      anchors.centerIn: parent
                      provider: sharedMark.modelData.provider
                      size: Style.font.bodySmall
                      iconDir: card.iconDir
                      lightSurface: card.lightSurface
                      visible: ready
                    }

                    Text {
                      id: sharedName
                      anchors.centerIn: parent
                      visible: !sharedIcon.ready
                      text: sharedMark.modelData.providerName
                      textFormat: Text.PlainText
                      font.family: card.widget.fontFamily
                      font.pixelSize: Style.font.caption
                      color: card.widget.muted
                    }

                    MouseArea {
                      id: sharedHover
                      anchors.fill: parent
                      hoverEnabled: true
                    }

                    PanelToolTip {
                      visible: sharedHover.containsMouse
                      text: "Also signed in through " + sharedMark.modelData.providerName
                        + (sharedMark.modelData.name !== "" ? " (" + sharedMark.modelData.name + ")" : "")
                      fontFamily: card.widget.fontFamily
                    }
                  }
                }
              }

              Text {
                id: accountPlan
                anchors.right: parent.right
                anchors.baseline: accountTitle.baseline
                text: account.modelData.plan
                textFormat: Text.PlainText
                font.family: card.widget.fontFamily
                font.pixelSize: Style.font.caption
                color: card.widget.muted
              }
            }

            // Its limits on one line, as Manage agents lists them: label,
            // spark, percent and reset per limit, in columns every account
            // shares. A metered month gives its credits for the percent.
            Item {
              id: groups
              readonly property var grid: card.usageGrid
              readonly property var notes: [card.usageNote(account.modelData, 0), card.usageNote(account.modelData, 1)]
              x: account.indent
              width: account.width - account.indent
              height: Math.max(usageMetrics.height, card.sparkHeight + Style.space(2))

              Repeater {
                model: 2

                delegate: Item {
                  id: group
                  required property int index
                  readonly property var window: account.modelData.windows[index]
                  readonly property var slot: index === 0 ? groups.grid.first : groups.grid.second
                  readonly property bool reading: window !== null && window.used !== null
                  readonly property bool near: reading && window.used >= 80
                  readonly property color ink: reading && window.used >= 100 ? card.widget.hot
                    : (near ? card.widget.warm : card.widget.accent)
                  readonly property bool metered: index === 0 && account.modelData.amount !== ""
                  readonly property string note: groups.notes[index]
                  readonly property real figureX: slot ? slot.label + groups.grid.gap + (groups.grid.bar > 0 ? groups.grid.bar + groups.grid.gap : 0) : 0
                  visible: (window !== null || note !== "") && slot !== null
                  x: index === 0 ? 0 : groups.grid.secondX
                  height: groups.height

                  Text {
                    text: group.window ? group.window.label : group.note
                    textFormat: Text.PlainText
                    font.family: card.widget.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: group.window ? card.widget.muted : Util.alpha(card.widget.muted, 0.6)
                  }

                  // The window this account doesn't have.
                  Text {
                    visible: group.window === null
                    x: group.slot ? group.slot.label + groups.grid.gap : 0
                    text: "\u2014"
                    textFormat: Text.PlainText
                    font.family: card.widget.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: Util.alpha(card.widget.muted, 0.6)
                  }

                  // A window as a filled sparkline across its span, start to
                  // reset, as Corgi's usage card gives it: its readings so far
                  // fill the time gone in a faint box whose top is the limit,
                  // and a dashed line carries the pace so far on to the
                  // reset. In the reading's tone: mint, then amber, then red
                  // at the limit.
                  Item {
                    id: spark
                    visible: groups.grid.bar > 0 && group.window !== null
                    x: group.slot ? group.slot.label + groups.grid.gap : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: groups.grid.bar
                    height: card.sparkHeight
                    readonly property var readings: {
                      var bars = group.window ? group.window.bars : []
                      return bars.filter(function(b) { return b.used !== null })
                    }
                    readonly property color tone: readings.length > 0
                      ? card.widget.toneColor(readings[readings.length - 1].tone) : card.widget.accent
                    // Room inside the box so the line and its dot keep off the edges.
                    readonly property real inset: 2
                    function yFor(used) {
                      return height - inset - Math.min(100, Math.max(0, used)) / 100 * (height - inset * 2)
                    }
                    // Each reading at its slot's end; slots still to come stay empty.
                    readonly property int slots: group.window ? Math.max(1, group.window.bars.length) : 1
                    readonly property real nowX: readings.length / slots * width
                    readonly property var points: {
                      var out = [Qt.point(0, yFor(0))]
                      for (var i = 0; i < readings.length; i++) out.push(Qt.point((i + 1) / slots * width, yFor(readings[i].used)))
                      return out
                    }
                    // Where the pace so far lands at the reset.
                    readonly property real paceY: readings.length > 0
                      ? yFor(readings[readings.length - 1].used * slots / readings.length) : yFor(0)

                    Rectangle {
                      anchors.fill: parent
                      radius: 2
                      color: Util.alpha(card.widget.foreground, 0.06)
                    }

                    Shape {
                      anchors.fill: parent
                      preferredRendererType: Shape.CurveRenderer
                      // The pace so far, on to the reset.
                      ShapePath {
                        strokeColor: spark.readings.length > 0 && spark.nowX < spark.width
                          ? Util.alpha(spark.tone, 0.5) : "transparent"
                        strokeWidth: 1
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2, 2]
                        fillColor: "transparent"
                        startX: spark.nowX
                        startY: spark.points[spark.points.length - 1].y
                        PathLine { x: spark.width; y: spark.paceY }
                      }
                      // Used so far, filled: the tone mixed into the panel.
                      ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.tint(Commons.Color.popups.background, Util.alpha(spark.tone, 0.4))
                        PathPolyline {
                          path: spark.points.concat([Qt.point(spark.nowX, spark.height), Qt.point(0, spark.height)])
                        }
                      }
                      ShapePath {
                        strokeColor: spark.tone
                        strokeWidth: 1.4
                        joinStyle: ShapePath.RoundJoin
                        fillColor: "transparent"
                        PathPolyline { path: spark.points }
                      }
                    }
                    // Now.
                    Rectangle {
                      visible: spark.readings.length > 0
                      width: 3
                      height: 3
                      radius: 1.5
                      color: spark.tone
                      x: spark.nowX - width / 2
                      y: spark.points[spark.points.length - 1].y - height / 2
                    }
                  }

                  Text {
                    id: figure
                    x: group.figureX
                    width: group.metered ? implicitWidth : group.slot ? group.slot.figure : 0
                    horizontalAlignment: group.metered ? Text.AlignLeft : Text.AlignRight
                    text: group.metered ? account.modelData.amount : group.window ? group.window.figure : ""
                    textFormat: Text.PlainText
                    font.family: card.widget.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.features: { "tnum": 1 }
                    // Figures keep the text's ink until a limit nears.
                    font.bold: group.near
                    color: group.near ? group.ink : card.widget.foreground
                  }

                  Text {
                    x: group.figureX + figure.width + groups.grid.wide
                    text: group.window ? group.window.reset : ""
                    textFormat: Text.PlainText
                    font.family: card.widget.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.features: { "tnum": 1 }
                    color: card.widget.usageFaint
                  }
                }
              }

              // The rule only stands between two groups.
              Text {
                visible: (account.modelData.windows[0] !== null || groups.notes[0] !== "")
                  && (account.modelData.windows[1] !== null || groups.notes[1] !== "")
                x: groups.grid.firstWidth
                width: groups.grid.sep
                horizontalAlignment: Text.AlignHCenter
                text: "\u2502"
                textFormat: Text.PlainText
                font.family: card.widget.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: card.widget.usageLine
              }

            }
          }
        }

      }
    }

    // ------------------------------------------------- nothing to list

    // Shown instead of the list: Corgi isn't installed, isn't running, or has
    // no workspaces yet.
    Item {
      id: messageBox
      width: parent.width
      visible: !card.listShown
      height: !card.listShown ? messageColumn.implicitHeight : 0

      Column {
        id: messageColumn
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: card.widget.mode === "install" ? "Corgi isn't installed yet."
            : card.widget.mode === "stopped" ? "Corgi isn't running."
            : "No workspaces yet."
          font.family: card.widget.fontFamily
          font.pixelSize: Style.font.bodySmall
          color: card.widget.muted
        }

        Button {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: card.widget.mode !== "running"
          text: card.widget.mode === "install" ? "Install Corgi" : "Open Corgi"
          iconText: card.widget.mode === "install" ? card.iconInstall : card.iconOpen
          foreground: card.widget.foreground
          fontFamily: card.widget.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          hasCursor: card.widget.cursorKey === ""
          onClicked: card.widget.primaryAction()
        }
      }
    }

    PanelSeparator {
      id: rule
      visible: card.listShown
      foreground: card.widget.foreground
    }

    // ------------------------------------------------------- the list

    ListView {
      id: list
      objectName: "agentList"
      width: parent.width
      visible: card.listShown
      height: Math.min(contentHeight, card.listCap)
      clip: true
      spacing: 0
      model: rowModel
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      // Whether it scrolls narrows its rows for the bar, which can change
      // the content's height, so it is decided once things settle.
      property bool scrolls: false
      function measure() { scrolls = contentHeight > card.listCap }
      onContentHeightChanged: Qt.callLater(measure)
      Connections {
        target: card
        function onListCapChanged() { Qt.callLater(list.measure) }
      }
      interactive: scrolls
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      // New rows fade in where they land; rows that go fade where they were.
      // A row that changes place glides there, and the rows it passes make
      // room the same way. Each also settles any fade a newer change cut short.
      add: card.settled ? fadeIn : null
      remove: fadeOut
      move: glide
      moveDisplaced: glide
      addDisplaced: glide
      removeDisplaced: glide
      displaced: glide
      Transition {
        id: fadeIn
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.duration(220); easing.type: Easing.OutCubic }
      }
      Transition {
        id: fadeOut
        NumberAnimation { property: "opacity"; to: 0; duration: Style.duration(180); easing.type: Easing.InCubic }
      }
      Transition {
        id: glide
        NumberAnimation { property: "y"; duration: card.glideMs; easing.type: Easing.InOutCubic }
        NumberAnimation { property: "opacity"; to: 1; duration: card.glideMs }
      }

      delegate: Item {
        id: row
        required property string key
        required property string kind
        required property int index
        // The row's data, kept while it fades out after leaving the list.
        readonly property var live: card.widget.rowMap[key]
        property var modelData: live
        onLiveChanged: if (live) modelData = live

        readonly property bool isAgent: kind === "agent"
        readonly property bool isLink: kind === "link"
        readonly property bool isSection: kind === "section"
        readonly property bool isAction: isAgent || isLink
        readonly property var agent: modelData ? modelData.agent : null
        readonly property string detail: isAgent && agent ? agent.detail : ""
        // Corgi's label for the heading's links, "API docs ↗" or "Open Link ↗ 2".
        readonly property string pointer: kind === "workspace" && modelData ? modelData.workspace.pointer : ""

        // A row that moves to another section rides a tint of the accent
        // from where it was, which lingers where it lands so the eye finds
        // it, then fades: the sidebar's glide, drawn by the row itself.
        readonly property string group: isAgent && agent ? agent.group : ""
        property string shownGroup: ""
        readonly property alias landingAnimation: landing
        onGroupChanged: {
          if (shownGroup !== "" && group !== "" && group !== shownGroup && card.widget.motion) landing.restart()
          if (group !== "") shownGroup = group
        }
        readonly property int arrowAt: pointer.lastIndexOf("\u2197")

        width: list.width - (list.scrolls ? Style.space(10) : 0)
        // A landing row travels over the rows it passes.
        z: landing.running ? 1 : 0
        readonly property real fullHeight: isAction ? actionRow.implicitHeight
          : (isSection ? sectionLine.height : (kind === "more" ? moreLine.height : heading.height))
        // Squished away when folded, or filtered out by a count.
        readonly property bool shown: card.widget.rowShown(modelData)
        height: shown ? fullHeight : 0
        clip: height < fullHeight
        property real squish: shown ? 1 : 0
        // A fold or a filter squishes a row smoothly; a row just made, as
        // when the panel opens, simply appears at its size. Its height
        // settles as its parts are measured, which mustn't animate.
        property bool made: false
        Timer {
          interval: 100
          running: true
          onTriggered: row.made = true
        }
        Behavior on height { enabled: row.made; NumberAnimation { duration: Style.duration(220); easing.type: Easing.InOutCubic } }
        Behavior on squish { enabled: row.made; NumberAnimation { duration: Style.duration(180) } }

        // A workspace: its name, a step up from the rows and in the theme's
        // accent, with room above to part it from the workspace before. A
        // click folds it; folded, it says beside its name what it holds.
        Item {
          id: heading
          visible: row.kind === "workspace"
          opacity: row.squish
          width: parent.width
          // As with every row, sized by what it is, not by being on screen.
          height: row.kind === "workspace" ? headingText.y + headingText.implicitHeight + Style.space(4) : 0
          readonly property var workspace: row.kind === "workspace" && row.modelData ? row.modelData.workspace : null
          readonly property bool open: !workspace || !card.widget.isFolded("workspaces", workspace.id)

          CursorSurface {
            id: foldHit
            y: headingText.y - Style.space(2)
            width: (pointerChip.visible ? pointerChip.x : newTabButton.x) - Style.space(6)
            height: headingText.implicitHeight + Style.space(4)
            hasCursor: row.kind === "workspace" && card.widget.onCursor(row.key, "")
            foreground: card.widget.foreground
            MouseArea {
              id: foldMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) card.widget.setCursor(row.key, "")
              onClicked: card.widget.toggleFold("workspaces", heading.workspace.id)
            }
          }
          Chevron {
            id: workspaceChevron
            x: Style.space(6)
            // On the middle of the name's lowercase letters.
            y: headingText.y + headingMetrics.ascent - headingMetrics.xHeight / 2 - height / 2
            size: Style.space(9)
            open: heading.open
            ink: card.widget.muted
          }
          Text {
            id: headingText
            x: workspaceChevron.x + workspaceChevron.width + Style.space(8)
            y: row.index === 0 ? Style.space(2) : Style.space(16)
            width: Math.min(implicitWidth, foldHit.width - x - (heading.open ? 0 : held.width + Style.space(10)))
            text: heading.workspace ? heading.workspace.name : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            // The theme's accent, which Corgi's own colors leave free.
            color: Commons.Color.accent
            font.family: card.widget.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Row {
            id: held
            anchors.left: headingText.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: headingText.verticalCenter
            spacing: Style.space(8)
            opacity: heading.open ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }
            Repeater {
              model: heading.workspace ? card.widget.kinds : []
              delegate: Row {
                id: heldKind
                required property string modelData
                readonly property int count: heading.workspace.agents.filter(function(a) {
                  return card.widget.kindTest(heldKind.modelData, a) }).length
                visible: count > 0
                spacing: Style.space(3)
                StatusGlyph {
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.font.caption
                  status: heldKind.modelData === "needs" ? "needs_input" : (heldKind.modelData === "working" ? "working" : "ready")
                  color: heldKind.modelData === "needs" ? card.widget.warm : card.widget.accent
                }
                Text {
                  text: heldKind.count
                  textFormat: Text.PlainText
                  color: card.widget.foreground
                  font.family: card.widget.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
            Text {
              readonly property int rest: heading.workspace ? heading.workspace.agents.filter(function(a) {
                return !card.widget.kinds.some(function(k) { return card.widget.kindTest(k, a) }) }).length : 0
              visible: rest > 0
              text: "\u25cb " + rest
              textFormat: Text.PlainText
              color: card.widget.muted
              font.family: card.widget.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // A new tab in the workspace: Corgi's new-tab picker, in the window
        // it opens in.
        Rectangle {
          id: newTabButton
          objectName: "newTab"
          visible: row.kind === "workspace"
          opacity: row.squish
          anchors.right: parent.right
          y: headingText.y + (headingText.implicitHeight - height) / 2
          width: newTabLabel.implicitWidth + Style.space(16)
          height: Math.round(headingText.implicitHeight * 1.15)
          radius: Style.cornerRadius
          readonly property bool hot: newTabMouse.containsMouse || card.widget.onCursor(row.key, "new")
          color: hot ? Style.hoverFillFor(card.widget.foreground, card.widget.accent) : "transparent"
          border.width: card.widget.onCursor(row.key, "new") ? 2 : 1
          border.color: Util.alpha(card.widget.foreground, hot ? 0.55 : 0.18)
          Behavior on color { ColorAnimation { duration: Style.duration(120) } }

          Text {
            id: newTabLabel
            anchors.centerIn: parent
            text: "New +"
            textFormat: Text.PlainText
            color: newTabButton.hot ? card.widget.accent : Util.alpha(card.widget.foreground, 0.8)
            font.family: card.widget.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          MouseArea {
            id: newTabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) card.widget.setCursor(row.key, "new")
            onClicked: card.widget.newTab(row.modelData.workspace)
          }
          PanelToolTip {
            visible: newTabMouse.containsMouse
            fontFamily: card.widget.fontFamily
            text: "New tab in " + (row.modelData ? row.modelData.workspace.name : "")
          }
        }

        // The workspace's links, as Corgi's sidebar points at them: one opens,
        // several list under the heading.
        Rectangle {
          id: pointerChip
          readonly property bool listing: card.widget.linksOpen === row.key
          readonly property bool hot: pointerMouse.containsMouse || card.widget.onCursor(row.key, "links")
          visible: row.pointer !== "" && row.kind === "workspace"
          opacity: row.squish
          anchors.right: newTabButton.left
          anchors.rightMargin: Style.space(6)
          y: headingText.y + (headingText.implicitHeight - height) / 2
          width: pointerRow.implicitWidth + Style.space(12)
          height: pointerRow.implicitHeight + Style.space(4)
          radius: Style.cornerRadius
          color: hot || listing ? Style.hoverFillFor(card.widget.foreground, card.widget.accent) : "transparent"

          Row {
            id: pointerRow
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              visible: text !== ""
              text: row.arrowAt > 0 ? row.pointer.slice(0, row.arrowAt).trim() : ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              maximumLineCount: 1
              width: Math.min(implicitWidth, row.width * 0.45)
              font.family: card.widget.fontFamily
              font.pixelSize: Style.font.caption
              color: Util.alpha(card.widget.foreground, 0.72)
            }

            Text {
              text: "\u2197"
              textFormat: Text.PlainText
              font.family: card.widget.fontFamily
              font.pixelSize: Style.font.caption
              color: card.widget.accent
            }

            Text {
              visible: text !== ""
              text: row.arrowAt >= 0 ? row.pointer.slice(row.arrowAt + 1).trim() : ""
              textFormat: Text.PlainText
              font.family: card.widget.fontFamily
              font.pixelSize: Style.font.caption
              color: card.widget.muted
            }
          }

          MouseArea {
            id: pointerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) card.widget.setCursor(row.key, "links")
            onClicked: card.widget.pointerAction(row.modelData.workspace)
          }
        }

        // An activity section's header, as the sidebar draws it between two
        // rules, with its fold's chevron past them: "── ▶ working 3 ── ▾".
        // A blank line parts it from the section above; a click folds it.
        Item {
          id: sectionLine
          visible: row.isSection
          opacity: row.squish
          width: parent.width
          height: row.isSection ? sectionText.y + sectionText.implicitHeight : 0
          readonly property real ruleY: Math.round(sectionText.y + sectionText.implicitHeight / 2)
          readonly property bool open: !(row.isSection && row.modelData) || !card.widget.isFolded("sections", row.modelData.fold)

          CursorSurface {
            anchors.fill: parent
            anchors.topMargin: sectionText.y - Style.space(2)
            hasCursor: row.isSection && card.widget.onCursor(row.key, "")
            foreground: card.widget.foreground
          }

          Rectangle {
            x: Style.space(10)
            y: sectionLine.ruleY
            width: Math.max(0, sectionText.x - x - Style.space(6))
            height: 1
            color: Util.alpha(card.widget.foreground, 0.12)
          }
          Text {
            id: sectionText
            anchors.horizontalCenter: parent.horizontalCenter
            y: row.modelData && row.modelData.first ? Style.space(2) : Style.space(6)
            // Filtered by a count, it counts those.
            text: {
              if (!row.isSection || !row.modelData || !row.modelData.section) return ""
              var w = card.widget, kind = w.filterKind, members = row.modelData.section.agents
              var n = kind === "" ? members.length : members.filter(function(a) { return w.kindTest(kind, a) }).length
              return w.sectionLabel(row.modelData.section.kind, n)
            }
            textFormat: Text.StyledText
            font.family: card.widget.fontFamily
            font.pixelSize: Style.font.caption
            color: sectionMouse.containsMouse ? card.widget.foreground : Util.alpha(card.widget.foreground, 0.85)
          }
          Rectangle {
            x: sectionText.x + sectionText.width + Style.space(6)
            y: sectionLine.ruleY
            width: Math.max(0, sectionChevron.x - x - Style.space(6))
            height: 1
            color: Util.alpha(card.widget.foreground, 0.12)
          }
          Chevron {
            id: sectionChevron
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            y: sectionLine.ruleY - height / 2
            size: Style.space(8)
            open: sectionLine.open
            ink: card.widget.muted
          }
          MouseArea {
            id: sectionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) card.widget.setCursor(row.key, "")
            onClicked: card.widget.toggleFold("sections", row.modelData.fold)
          }
        }

        // A long idle section's "… N more", under its titles; open, it folds
        // them back.
        Item {
          id: moreLine
          visible: row.kind === "more"
          opacity: row.squish
          width: parent.width
          height: row.kind === "more" ? moreText.implicitHeight + Style.space(8) : 0

          CursorSurface {
            anchors.fill: parent
            hasCursor: row.kind === "more" && card.widget.onCursor(row.key, "")
            foreground: card.widget.foreground
          }
          Text {
            id: moreText
            x: Style.space(10) + Style.font.body + Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: row.kind !== "more" || !row.modelData ? "" : (row.modelData.open ? "Show fewer" : "\u2026 " + row.modelData.count + " more")
            textFormat: Text.PlainText
            color: moreMouse.containsMouse ? card.widget.foreground : card.widget.muted
            font.family: card.widget.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: moreMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) card.widget.setCursor(row.key, "")
            onClicked: card.widget.toggleFold("idle", row.modelData.workspace.id)
          }
        }

        // An agent, as a row of Corgi's sidebar: glyph, title and provider,
        // and what it is doing on the line below.
        CursorSurface {
          id: actionRow
          visible: row.isAction
          opacity: row.squish
          width: parent.width
          implicitHeight: lines.implicitHeight + Style.spacing.rowPaddingX
          hasCursor: row.isAction && card.widget.onCursor(row.key, "")
          foreground: card.widget.foreground

          // Opaque, so the rows it passes don't show through: the panel's
          // background a fifth of the way to the accent, which is what a
          // translucent tint would show once it lands.
          Rectangle {
            id: landingTint
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.tint(Commons.Color.popups.background, Util.alpha(card.widget.accent, 0.2))
            opacity: 0
          }
          SequentialAnimation {
            id: landing
            NumberAnimation { target: landingTint; property: "opacity"; from: 0; to: 1; duration: Style.duration(70) }
            PauseAnimation { duration: card.glideMs + Style.duration(830) }
            NumberAnimation { target: landingTint; property: "opacity"; to: 0; duration: Style.duration(700); easing.type: Easing.InOutQuad }
          }

          // The glyph's line is the title's.
          StatusGlyph {
            id: glyph
            visible: row.isAgent
            x: Style.space(10)
            y: lines.y + (title.height - height) / 2
            size: Style.font.body
            status: row.isAgent && row.agent ? row.agent.status : "idle"
            color: card.widget.statusColor(row.agent)
            Behavior on color { ColorAnimation { duration: Style.duration(250) } }
          }

          // The activity glyph sits under the status glyph, as in Corgi's
          // sidebar. While it thinks or runs a tool, a drawn spinner; while
          // it compacts, a drawn pile; the rest (napping, waiting) are
          // Corgi's own glyphs.
          readonly property bool spinning: row.isAgent && !!row.agent
            && (row.agent.glyph === "thinking" || row.agent.glyph === "tool")
          readonly property bool compacting: row.isAgent && !!row.agent && row.agent.glyph === "compacting"
          Loader {
            active: actionRow.compacting
            visible: active && detail.visible
            anchors.horizontalCenter: glyph.horizontalCenter
            y: lines.y + detail.y + (detail.height - height) / 2
            width: Math.round(Style.font.bodySmall * 0.72)
            height: Math.round(width * 4 / 3)
            sourceComponent: Pile {
              objectName: "pile"
              hot: card.widget.accent
              cool: card.widget.muted
              coolMs: 400
              animate: card.widget.motion
            }
          }
          Item {
            id: spinner
            visible: actionRow.spinning && detail.visible
            anchors.horizontalCenter: glyph.horizontalCenter
            y: lines.y + detail.y + (detail.height - height) / 2
            width: Math.round(Style.font.bodySmall * 0.72)
            height: width
            Shape {
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                strokeColor: Util.alpha(card.widget.foreground, 0.18)
                strokeWidth: 1.5
                fillColor: "transparent"
                PathAngleArc { centerX: spinner.width / 2; centerY: spinner.height / 2; radiusX: spinner.width / 2 - 1; radiusY: spinner.width / 2 - 1; sweepAngle: 360 }
              }
              ShapePath {
                strokeColor: card.widget.accent
                strokeWidth: 1.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: spinner.width / 2; centerY: spinner.height / 2; radiusX: spinner.width / 2 - 1; radiusY: spinner.width / 2 - 1; startAngle: -90; sweepAngle: 100 }
              }
            }
            RotationAnimator on rotation {
              from: 0
              to: 360
              duration: 900
              loops: Animation.Infinite
              running: spinner.visible && card.widget.motion && card.visible
            }
          }
          Text {
            visible: row.isAgent && detail.visible && !actionRow.spinning && !actionRow.compacting
            anchors.horizontalCenter: glyph.horizontalCenter
            y: lines.y + detail.y + (detail.height - height) / 2
            text: detail.activity
            textFormat: Text.PlainText
            font.family: card.widget.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: Util.alpha(card.widget.foreground, 0.5)
          }

          Text {
            visible: row.isLink
            x: glyph.x
            y: lines.y + (title.height - height) / 2
            width: glyph.width
            horizontalAlignment: Text.AlignHCenter
            text: "↗"
            font.family: card.widget.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: card.widget.accent
          }

          Column {
            id: lines
            anchors.left: glyph.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            // An empty second line keeps its room; the title moves down into
            // the middle of the row.
            anchors.verticalCenterOffset: detail.empty && detail.visible ? (detail.height + spacing) / 2 : 0
            spacing: Style.space(1)

            Item {
              width: parent.width
              height: title.implicitHeight

              Text {
                id: title
                anchors.left: parent.left
                anchors.right: providerMark.visible ? providerMark.left : (provider.visible ? provider.left : parent.right)
                anchors.rightMargin: providerMark.visible || provider.visible ? Style.space(8) : 0
                text: row.isLink && row.modelData ? card.widget.linkName(row.modelData.link)
                  : (row.isAgent && row.agent ? row.agent.title : "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: card.widget.fontFamily
                font.pixelSize: row.isLink ? Style.font.bodySmall : Style.font.body
                font.bold: card.widget.emphasized(row.agent)
                color: row.isLink ? Util.alpha(card.widget.foreground, 0.85) : card.widget.foreground
              }

              // The provider's brand mark, or its name where no mark ships.
              ProviderIcon {
                id: providerMark
                anchors.right: parent.right
                anchors.verticalCenter: title.verticalCenter
                provider: row.isAgent && row.agent ? String(row.agent.provider).toLowerCase() : ""
                size: Style.font.body
                iconDir: card.iconDir
                lightSurface: card.lightSurface
                visible: ready
              }

              Text {
                id: provider
                anchors.right: parent.right
                anchors.baseline: title.baseline
                visible: text !== "" && !providerMark.ready
                text: row.isAgent && row.agent ? row.agent.provider : ""
                textFormat: Text.PlainText
                font.family: card.widget.fontFamily
                font.pixelSize: Style.font.caption
                color: card.widget.muted
              }
            }

            // Corgi's second line: the activity glyph (the spinner while it
            // works), then the corgi playing there or what the agent is doing.
            Item {
              id: detail
              readonly property var motion: row.isAgent && row.agent ? card.frames[row.agent.key] : undefined
              readonly property string activity: motion ? motion.glyph : ""
              readonly property string corgi: motion ? motion.line : ""
              readonly property bool empty: row.detail === "" && activity === "" && corgi === ""
              readonly property bool herding: row.isAgent && !!row.agent && row.agent.corgi === "herding"
              width: parent.width
              // A link is one line: its name.
              readonly property bool wanted: !row.isLink && !(empty && card.collapseEmptyDetail)
              visible: wanted
              height: wanted ? detailMetrics.height : 0

              Loader {
                active: detail.herding
                visible: active
                anchors.left: parent.left
                anchors.right: parent.right
                sourceComponent: Herd {
                  objectName: "herd"
                  since: row.agent ? row.agent.since : 0
                  animate: card.widget.motion
                  fontFamily: card.widget.fontFamily
                  pixelSize: Style.font.bodySmall
                  ink: Util.alpha(card.widget.foreground, 0.72)
                  faint: card.widget.faint
                }
              }

              Text {
                visible: !detail.herding
                anchors.left: parent.left
                anchors.leftMargin: 0
                anchors.right: parent.right
                // The corgi's line is Corgi's own markup; the detail is the agent's, so plain.
                text: detail.corgi !== "" ? detail.corgi : row.detail
                textFormat: detail.corgi !== "" ? Text.StyledText : Text.PlainText
                elide: detail.corgi !== "" ? Text.ElideNone : Text.ElideRight
                clip: true
                maximumLineCount: 1
                font.family: card.widget.fontFamily
                // A step under the title and dimmer, but meant to be read:
                // the theme's muted caption washes out on most themes.
                font.pixelSize: Style.font.bodySmall
                color: Util.alpha(card.widget.foreground, 0.72)
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) card.widget.setCursor(row.key, "")
            onClicked: {
              if (row.isLink) card.widget.openLink(row.modelData.link)
              else card.widget.focusAgent(row.agent)
            }
          }
        }
      }
    }

    // The Corgi release installed, as Corgi's usage card ends with it.
    Text {
      id: versionLine
      visible: card.widget.release !== ""
      width: parent.width
      horizontalAlignment: Text.AlignRight
      text: "Corgi " + card.widget.release
      textFormat: Text.PlainText
      elide: Text.ElideLeft
      font.family: card.widget.fontFamily
      font.pixelSize: Style.font.caption
      color: card.widget.faint
    }
  }

  FontMetrics {
    id: headingMetrics
    font.family: card.widget.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  FontMetrics {
    id: nameMetrics
    font.family: card.widget.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  FontMetrics {
    id: usageMetrics
    readonly property real cell: advanceWidth("M")
    font.family: card.widget.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
