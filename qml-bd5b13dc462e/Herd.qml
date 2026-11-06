pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Corgi's compaction on a row's second line, as its sidebar plays it, only
// smooth: "Compacting" lies scattered along the line, faint and bobbing; the
// corgi walks in from the right and herds the letters home, lighting each
// one it reaches, sits, then melts into the ellipsis, and the time so far
// shows at the right. The scene is Corgi's herdScene in fractional cells.
// Without motion it is the finished line.
Item {
  id: herd

  // When the compaction began, in ms since the epoch; 0 starts it now.
  property real since: 0
  property bool animate: true
  property string fontFamily: ""
  property real pixelSize: 12
  property color ink: "white"
  property color faint: "gray"

  readonly property var word: ["C", "o", "m", "p", "a", "c", "t", "i", "n", "g"]
  readonly property var gaps: [1, 2, 0, 2, 1, 0, 2, 1, 1]
  readonly property var walk: ["‹o[/\\]~", "‹o[||]~", "‹o[\\/]~", "‹o[||]~"]
  // Each curled pose and the cells after the word it sits at.
  readonly property var curl: [[2, "ᐯ◡ᴥ◡ᐯ"], [2, "ᐯ◡ᴥ◡ᐯ"], [3, "◡ᴥ◡"], [2, "•ᴥ•"], [1, "•.•"], [0, "..."], [0, "…"]]
  readonly property var tail: ["~", "-", "~", "^"]

  property real shownAt: Date.now()
  readonly property real started: since > 0 ? since : shownAt
  readonly property real cell: Math.max(1, metrics.advanceWidth("0"))
  readonly property int cells: Math.floor(width / cell)
  // Narrow rows keep the text; the pile beside it still moves.
  readonly property bool narrow: cells < word.length + 8

  // Where the ellipsis's dots and the bullet's ink sit, measured large and
  // scaled down: the dots' centres from the glyph's middle, their size and
  // height above the baseline, and the same for the bullet the eyes are
  // drawn as. The ink box doesn't say how wide each dot is, so they take a
  // fifth of it at most, as JetBrains Mono's pills do. Qt's box always
  // reaches down to the baseline, so the bullet, which floats above it, is
  // taken as round, hanging from its top.
  readonly property var geo: {
    var font = large.font, k = pixelSize / 200
    var e = large.tightBoundingRect("\u2026"), b = large.tightBoundingRect("\u2022")
    var dw = Math.min(e.height, e.width / 5), half = large.advanceWidth("\u2026") / 2
    var left = e.x + dw / 2 - half, right = e.x + e.width - dw / 2 - half
    return { dots: [left * k, (left + right) / 2 * k, right * k], dw: dw * k, dh: e.height * k,
             dotY: -(e.y + e.height / 2) * k, ew: b.width * k, eh: b.width * k, eyeY: -(b.y + b.width / 2) * k }
  }

  // The frame: where each letter is and whether it's been herded, the
  // corgi, and the time so far once it has curled up.
  property var letterX: []
  property var letterY: []
  property var lit: []
  property var litAt: []
  property string dogText: ""
  property real dogX: 0
  property bool finished: false
  property string took: ""
  // Once it sits, the corgi part by part: melt()'s frame.
  property bool melting: false
  property var face: ({})
  property color dogColor: finished ? ink : faint
  Behavior on dogColor { ColorAnimation { duration: Style.duration(250) } }

  implicitHeight: metrics.height

  function elapsed(ms) {
    var s = Math.floor(Math.max(0, ms) / 1000)
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m " + (s % 60) + "s"
    return Math.floor(s / 3600) + "h " + (Math.floor(s / 60) % 60) + "m"
  }

  function scene(width, step) {
    var n = word.length, total = 0, spread = [0], sum = 0
    for (var g = 0; g < gaps.length; g++) total += gaps[g]
    for (var i = 1; i < n; i++) {
      sum += gaps[(i - 1) % gaps.length]
      spread.push(i + sum * (width - n - 1) / total)
    }
    var roundup = width - n + 1
    if (step < roundup) {
      // The nose stops at the word's end, as whole steps do.
      var nose = Math.max(n, width - step), letters = spread.slice()
      letters[n - 1] = Math.min(spread[n - 1], nose - 1)
      for (var k = n - 1; k > 0; k--) letters[k - 1] = Math.min(spread[k - 1], letters[k] - 1)
      return { letters: letters, lit: letters.map(function(at, j) { return at <= j || at < spread[j] }),
               dog: walk[Math.floor(step) % 4], x: nose, finished: false }
    }
    var p = Math.floor(step - roundup), c = p >= 10 ? Math.min(p - 10, curl.length - 1) : -1
    return { letters: word.map(function(_, j) { return j }), lit: word.map(function() { return true }),
             dog: c >= 0 ? curl[c][1] : (p === 6 ? "~ᐯ◡ᴥ◡ᐯ" : "~ᐯ•ᴥ•ᐯ"),
             x: c >= 0 ? n + curl[c][0] : n + 1, finished: p >= 10 + curl.length - 1 }
  }

  function between(s, from, to) {
    var t = Math.min(1, Math.max(0, (s - from) / (to - from)))
    return t * t * (3 - 2 * t)
  }
  function lerp(a, b, k) { return a + (b - a) * k }

  // The sitting corgi melting into the ellipsis, from the sit (q = 0) to
  // curled up (q = 16), in Corgi's steps. It follows the console's poses
  // without their jumps: the tail tucks in, the eyes shut and the ears fold,
  // then the eyes and nose shrink to dots that slide left into the "…"
  // beside the word, where the font's own ellipsis takes over. Glyphs give
  // their centre, scale and opacity; dots their centre, size, height above
  // the baseline and opacity.
  function melt(q, wag) {
    var s = q - 10, g = geo, cw = cell, home = word.length * cw + cw / 2
    var tuck = between(s, 0, 1.2), fold = between(s, 0.4, 2.2)
    var shut = s < 0 ? (q >= 6 && q < 7 ? Math.sin(Math.PI * (q - 6)) : 0) : between(s, 0, 0.6) * (1 - between(s, 2.4, 3))
    var shrink = between(s, 2.6, 4.2), nose = between(s, 3, 4), drift = between(s, 2, 6), close = between(s, 4, 6)
    var glyphed = between(s, 5.6, 6)
    var mid = lerp(home + 4 * cw, home + g.dots[1], drift), gap = lerp(cw, (g.dots[2] - g.dots[0]) / 2, close)
    var ew = lerp(g.ew, g.dw, shrink), eh = lerp(g.eh, g.dh, shrink) * (1 - 0.8 * shut), eyeY = lerp(g.eyeY, g.dotY, shrink)
    return {
      tail: { text: s < 0 ? wag : "~", x: mid - 3 * cw + 0.6 * cw * tuck, scale: 1, opacity: 1 - tuck },
      earL: { text: "\u142f", x: mid - 2 * cw + 0.6 * cw * fold, scale: 1 - 0.6 * fold, opacity: 1 - fold },
      earR: { text: "\u142f", x: mid + 2 * cw - 0.6 * cw * fold, scale: 1 - 0.6 * fold, opacity: 1 - fold },
      nose: { text: "\u1d25", x: mid, scale: 1 - 0.7 * nose, opacity: 1 - nose },
      ellipsis: { text: "\u2026", x: home, scale: 1, opacity: glyphed },
      eyeL: { x: mid - gap, w: ew, h: eh, y: eyeY, opacity: 1 - glyphed },
      eyeR: { x: mid + gap, w: ew, h: eh, y: eyeY, opacity: 1 - glyphed },
      noseDot: { x: mid, w: g.dw * nose, h: g.dh * nose, y: g.dotY, opacity: nose * (1 - glyphed) }
    }
  }

  function update() {
    if (narrow) return
    var now = Date.now()
    var raw = animate ? Math.max(0, now - started) / 110 : 1e9
    var s = scene(cells, raw)
    var xs = [], ys = [], at = litAt.slice()
    for (var i = 0; i < word.length; i++) {
      if (s.lit[i] && !at[i]) at[i] = now
      if (!s.lit[i]) at[i] = 0
      // Scattered letters graze; herded ones settle onto the line.
      var settle = s.lit[i] ? Math.max(0, 1 - (now - at[i]) / 220) : 1
      xs.push(s.letters[i] * cell)
      ys.push(animate && i > 0 ? Math.sin(now / 420 + i * 1.7) * 1.4 * settle : 0)
    }
    litAt = at
    letterX = xs
    letterY = ys
    lit = s.lit
    var wag = tail[Math.floor(raw / 2) % 4]
    dogText = s.dog.split("").map(function(g) { return g === "~" ? wag : g }).join("")
    dogX = s.x * cell
    finished = s.finished
    var q = raw - (cells - word.length + 1)
    melting = animate && q >= 0
    if (melting) face = melt(q, wag)
    var so_far = elapsed(now - started)
    took = s.finished && word.length + 1 + so_far.length <= cells ? so_far : ""
  }

  onCellsChanged: update()
  onStartedChanged: update()
  onAnimateChanged: update()
  onVisibleChanged: if (visible) update()
  Component.onCompleted: update()

  // Every frame while it moves; once it has curled up, once a second for the time.
  FrameAnimation {
    running: herd.visible && herd.animate && !herd.finished && !herd.narrow
    onTriggered: herd.update()
  }
  Timer {
    interval: 1000
    repeat: true
    running: herd.visible && !herd.narrow && (herd.finished || !herd.animate)
    onTriggered: herd.update()
  }

  Text {
    visible: herd.narrow
    width: herd.width
    text: "Compacting…"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    font.family: herd.fontFamily
    font.pixelSize: herd.pixelSize
    color: herd.ink
  }

  Repeater {
    model: herd.narrow ? 0 : herd.word.length

    delegate: Text {
      required property int index
      x: herd.letterX[index] || 0
      y: herd.letterY[index] || 0
      text: herd.word[index]
      textFormat: Text.PlainText
      font.family: herd.fontFamily
      font.pixelSize: herd.pixelSize
      color: herd.lit[index] ? herd.ink : herd.faint
      Behavior on color { ColorAnimation { duration: Style.duration(180) } }
    }
  }

  // Walking glides. Once it sits, the corgi is drawn part by part: glyphs
  // centred in their cells, the eyes and dots as pills on the baseline.
  Text {
    id: dog
    visible: !herd.narrow && !herd.melting
    x: herd.dogX
    text: herd.dogText
    textFormat: Text.PlainText
    font.family: herd.fontFamily
    font.pixelSize: herd.pixelSize
    color: herd.dogColor
  }

  Repeater {
    model: herd.melting ? ["tail", "earL", "earR", "nose", "ellipsis"] : []

    delegate: Text {
      required property string modelData
      readonly property var part: herd.face[modelData] || { text: "", x: 0, scale: 1, opacity: 0 }
      x: part.x - herd.cell / 2
      width: herd.cell
      horizontalAlignment: Text.AlignHCenter
      scale: part.scale
      opacity: part.opacity
      text: part.text
      textFormat: Text.PlainText
      font.family: herd.fontFamily
      font.pixelSize: herd.pixelSize
      color: herd.dogColor
    }
  }

  Repeater {
    model: herd.melting ? ["eyeL", "eyeR", "noseDot"] : []

    delegate: Rectangle {
      required property string modelData
      readonly property var part: herd.face[modelData] || { x: 0, w: 0, h: 0, y: 0, opacity: 0 }
      x: part.x - part.w / 2
      y: dog.baselineOffset - part.y - part.h / 2
      width: part.w
      height: part.h
      radius: Math.min(width, height) / 2
      opacity: part.opacity
      antialiasing: true
      color: herd.dogColor
    }
  }

  Text {
    anchors.right: parent.right
    visible: !herd.narrow
    opacity: herd.took !== "" ? 1 : 0
    text: herd.took
    textFormat: Text.PlainText
    font.family: herd.fontFamily
    font.pixelSize: herd.pixelSize
    font.features: { "tnum": 1 }
    color: herd.faint
    Behavior on opacity { NumberAnimation { duration: Style.duration(300) } }
  }

  FontMetrics {
    id: metrics
    font.family: herd.fontFamily
    font.pixelSize: herd.pixelSize
  }
  FontMetrics {
    id: large
    font.family: herd.fontFamily
    font.pixelSize: 200
  }
}
