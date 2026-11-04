pragma ComponentBehavior: Bound

import QtQuick

// Corgi's compaction spinner, drawn: dots fall into a pile two wide and four
// high, then squash flat into its floor. Each falls in the hot color and
// cools to the rest color once it lands. Laid out on a 9 by 12 grid scaled
// to the item. Without motion, a full pile at rest.
Item {
  id: pile

  property color hot: "white"
  property color cool: "gray"
  property int coolMs: 400
  property bool animate: true

  property real now: Date.now()
  readonly property int cycleMs: 1425
  // Each drop's column, row, and when it starts and lands, as a share of the cycle.
  readonly property var drops: [[0, 2, 0.02, 0.15], [1, 2, 0.15, 0.28], [0, 1, 0.3, 0.42],
                                [1, 1, 0.42, 0.53], [0, 0, 0.53, 0.63], [1, 0, 0.6, 0.7]]
  readonly property var columns: [2.5, 6.5]
  readonly property var rows: [1.6, 4.6, 7.6, 10.6]
  readonly property real dot: 1.15
  readonly property real unit: width / 9
  readonly property real phase: animate ? (now % cycleMs) / cycleMs : 0.75
  // Full by 0.7, held, then flattened into the floor.
  readonly property real squash: phase < 0.8 ? 0 : smoothstep(Math.min(1, (phase - 0.8) / 0.14))

  function smoothstep(s) { return s * s * (3 - 2 * s) }

  // A dot's color `age` ms after it lands.
  function colorAt(age) {
    var k = 1 - Math.pow(1 - Math.min(1, Math.max(0, age / coolMs)), 2)
    return Qt.rgba(hot.r + (cool.r - hot.r) * k, hot.g + (cool.g - hot.g) * k,
                   hot.b + (cool.b - hot.b) * k, hot.a + (cool.a - hot.a) * k)
  }

  // The floor, spreading as the pile flattens into it.
  Repeater {
    model: 2

    delegate: Rectangle {
      required property int index
      readonly property real r: (pile.dot + 0.4 * Math.sin(Math.PI * pile.squash)) * pile.unit
      x: pile.columns[index] * pile.unit - r
      y: pile.rows[3] * pile.unit - r
      width: r * 2
      height: r * 2
      radius: r
      color: pile.cool
    }
  }

  Repeater {
    model: pile.drops.length

    delegate: Rectangle {
      required property int index
      readonly property var drop: pile.drops[index]
      readonly property real fall: pile.phase < drop[2] ? 0
        : Math.min(1, (pile.phase - drop[2]) / (drop[3] - drop[2]))
      // Falls from above the pile under gravity, then sinks into the floor.
      readonly property real gridY: {
        var y = pile.phase < drop[2] ? -2 : -2 + (pile.rows[drop[1]] + 2) * fall * fall
        return y + (pile.rows[3] - y) * pile.squash
      }
      x: pile.columns[drop[0]] * pile.unit - width / 2
      y: gridY * pile.unit - height / 2
      width: pile.dot * 2 * pile.unit
      height: width
      radius: width / 2
      opacity: (pile.phase < drop[2] ? 0 : Math.min(1, fall * 3)) * (1 - pile.squash)
      color: !pile.animate ? pile.cool
        : pile.phase < drop[3] ? pile.hot : pile.colorAt((pile.phase - drop[3]) * pile.cycleMs)
    }
  }

  FrameAnimation {
    running: pile.visible && pile.animate
    onTriggered: pile.now = Date.now()
  }
}
