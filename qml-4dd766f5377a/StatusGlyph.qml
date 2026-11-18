import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The glyph Corgi's sidebar puts in front of an agent, for its status:
// ▶ working, ● needs_input and ready, ‖ paused and retrying, ◌ starting, ○ idle and done,
// · anything else. Drawn rather than set in a font: Omarchy lets the user
// pick any monospace font, and these have to stay crisp and centred in all of
// them. The triangle has the bar's working mark's proportions (Indicator.qml).
Item {
  id: root

  property string status: "idle"
  property color color: Commons.Color.foreground
  property real size: Style.space(10)

  implicitWidth: size
  implicitHeight: size

  readonly property real mid: size / 2
  readonly property bool filledDot: status === "needs_input" || status === "ready"
  readonly property bool ring: status === "idle" || status === "done" || status === "starting"

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // ▶, nudged right of centre so its mass sits in the middle.
    ShapePath {
      id: play
      readonly property real h: root.size * 0.68
      readonly property real w: h * 0.88
      readonly property real left: root.mid - w / 2 + w * 0.06
      fillColor: root.status === "working" ? root.color : "transparent"
      strokeWidth: 0
      startX: play.left; startY: root.mid - play.h / 2
      PathLine { x: play.left + play.w; y: root.mid }
      PathLine { x: play.left; y: root.mid + play.h / 2 }
      PathLine { x: play.left; y: root.mid - play.h / 2 }
    }

    // ● and ·
    ShapePath {
      id: dot
      readonly property real r: root.filledDot ? root.size * 0.32 : root.size * 0.12
      fillColor: root.filledDot || root.status === "other" ? root.color : "transparent"
      strokeWidth: 0
      PathAngleArc {
        moveToStart: true
        centerX: root.mid; centerY: root.mid
        radiusX: dot.r; radiusY: dot.r
        startAngle: 0; sweepAngle: 360
      }
    }

    // ○, dashed for ◌
    ShapePath {
      id: circle
      readonly property real stroke: Math.max(1, root.size * 0.12)
      readonly property real r: root.size * 0.30 - stroke / 2
      fillColor: "transparent"
      strokeColor: root.ring ? root.color : "transparent"
      strokeWidth: circle.stroke
      strokeStyle: root.status === "starting" ? ShapePath.DashLine : ShapePath.SolidLine
      dashPattern: [1.3, 1.3]
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        moveToStart: true
        centerX: root.mid; centerY: root.mid
        radiusX: circle.r; radiusY: circle.r
        startAngle: 0; sweepAngle: 360
      }
    }

    // ‖
    ShapePath {
      id: bars
      readonly property real bw: Math.max(1, root.size * 0.15)
      readonly property real bh: root.size * 0.62
      readonly property real top: root.mid - bh / 2
      readonly property real l1: root.mid - root.size * 0.08 - bw
      readonly property real l2: root.mid + root.size * 0.08
      fillColor: root.status === "paused" || root.status === "retrying" ? root.color : "transparent"
      strokeWidth: 0
      startX: bars.l1; startY: bars.top
      PathLine { x: bars.l1 + bars.bw; y: bars.top }
      PathLine { x: bars.l1 + bars.bw; y: bars.top + bars.bh }
      PathLine { x: bars.l1; y: bars.top + bars.bh }
      PathLine { x: bars.l1; y: bars.top }
      PathMove { x: bars.l2; y: bars.top }
      PathLine { x: bars.l2 + bars.bw; y: bars.top }
      PathLine { x: bars.l2 + bars.bw; y: bars.top + bars.bh }
      PathLine { x: bars.l2; y: bars.top + bars.bh }
      PathLine { x: bars.l2; y: bars.top }
    }
  }
}
