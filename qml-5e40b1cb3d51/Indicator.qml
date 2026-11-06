import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// One of the two marks beside the bar's corgi: a dot (an agent is ready, or
// needs input) or a play triangle (an agent is working).
//
// A mark buds out of the corgi's side as it appears: it starts small, tucked
// under the silhouette's edge, and slides out to its place, stretching along
// the way it travels, while a neck joins it to where it came from and thins
// until it pinches off. Leaving runs the same way back. When the other mark
// is already showing, a new mark splits off that one instead of the corgi, and
// a leaving mark merges back into it.
//
// The geometry is a function of `progress` and the rest point, so nothing
// recomputes while the mark sits still: the only per-frame work is the
// transition itself. Its durations go through Style.duration, which is 0 when
// Hyprland's animations are off, so there it simply appears and disappears.
//
// Coordinates are the parent's: this Shape fills it.
Shape {
  id: root

  property string kind: "dot"
  property bool shown: false
  property color color: Commons.Color.foreground
  property real size: 5
  // Where the mark's centre rests.
  property real restX: 0
  property real restY: 0
  // The corgi's edge on the side the mark sits: x for a horizontal bar,
  // y (the bottom) for a vertical one.
  property real edge: 0
  property bool vertical: false
  // The other mark (an Indicator).
  property var sibling: null

  property real progress: shown ? 1 : 0
  Behavior on progress {
    id: growth
    NumberAnimation {
      id: growthAnimation
      duration: Style.duration(growth.targetValue > 0.5 ? 250 : 170)
      easing.type: Easing.Bezier
      // Older Omarchy builds have no Style.easeOut; the same curve.
      easing.bezierCurve: Style.easeOut || [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]
    }
  }

  Behavior on color {
    ColorAnimation { id: colorAnimation; duration: Style.duration(160); easing.type: Easing.OutCubic }
  }

  readonly property bool animating: growthAnimation.running || colorAnimation.running

  // Whether this transition runs from or to the other mark rather than the
  // corgi. Latched when it starts and dropped when it ends, so two marks never
  // take each other as their origin at once.
  property bool viaSibling: false
  onShownChanged: viaSibling = !!sibling && sibling.shown && sibling.progress > 0.5
    && !(sibling.viaSibling && sibling.animating)
  onAnimatingChanged: if (!animating) viaSibling = false

  visible: progress > 0
  // A mark splitting off the other starts out underneath it.
  z: viaSibling ? 0 : 1
  preferredRendererType: Shape.CurveRenderer

  // Where it comes from: a point just inside the corgi's edge, level with the
  // rest point, or the other mark's centre.
  readonly property real inset: size * 0.3
  readonly property real originX: viaSibling ? sibling.centerX : (vertical ? restX : edge - inset)
  readonly property real originY: viaSibling ? sibling.centerY : (vertical ? edge - inset : restY)

  readonly property real centerX: originX + (restX - originX) * progress
  readonly property real centerY: originY + (restY - originY) * progress

  // Travel direction, its normal, and how far along it the mark is now.
  readonly property real travel: Math.sqrt(Math.pow(restX - originX, 2) + Math.pow(restY - originY, 2))
  readonly property real ux: travel > 0.01 ? (restX - originX) / travel : (vertical ? 0 : 1)
  readonly property real uy: travel > 0.01 ? (restY - originY) / travel : (vertical ? 1 : 0)
  readonly property real reach: travel * progress

  // Grows from 45% as it comes out, stretched along its path mid-flight.
  readonly property real grown: 0.45 + 0.55 * progress
  readonly property real stretch: 0.22 * Math.sin(Math.PI * progress)
  readonly property bool travelsX: Math.abs(ux) >= Math.abs(uy)
  readonly property real sx: grown * (travelsX ? 1 + stretch : 1 - stretch * 0.6)
  readonly property real sy: grown * (travelsX ? 1 - stretch * 0.6 : 1 + stretch)
  readonly property real across: size / 2 * grown * (1 - stretch * 0.6)

  // The neck: a waisted band from the origin to the mark's centre. Its ends
  // and, faster, its waist thin out until it pinches off three quarters of the
  // way.
  readonly property real neck: Math.max(0, 1 - progress / 0.75)
  readonly property real neckRoot: (viaSibling ? sibling.size / 2 * 0.8 : size * 0.42) * Math.sqrt(neck)
  readonly property real neckEnd: across * 0.85 * Math.sqrt(neck)
  readonly property real neckWaist: Math.max(0, (8 * Math.min(neckRoot, neckEnd) * neck - neckRoot - neckEnd) / 6)

  function along(t, side, offset) {
    return { x: originX + ux * t - uy * offset * side, y: originY + uy * t + ux * offset * side }
  }

  ShapePath {
    id: neckPath
    readonly property var a: root.along(0, 1, root.neckRoot)
    readonly property var b: root.along(root.reach / 3, 1, root.neckWaist)
    readonly property var c: root.along(root.reach * 2 / 3, 1, root.neckWaist)
    readonly property var d: root.along(root.reach, 1, root.neckEnd)
    readonly property var e: root.along(root.reach, -1, root.neckEnd)
    readonly property var f: root.along(root.reach * 2 / 3, -1, root.neckWaist)
    readonly property var g: root.along(root.reach / 3, -1, root.neckWaist)
    readonly property var h: root.along(0, -1, root.neckRoot)
    fillColor: root.neck > 0 && root.reach > 0.05 ? root.color : "transparent"
    strokeWidth: 0
    startX: neckPath.a.x; startY: neckPath.a.y
    PathCubic {
      control1X: neckPath.b.x; control1Y: neckPath.b.y
      control2X: neckPath.c.x; control2Y: neckPath.c.y
      x: neckPath.d.x; y: neckPath.d.y
    }
    PathLine { x: neckPath.e.x; y: neckPath.e.y }
    PathCubic {
      control1X: neckPath.f.x; control1Y: neckPath.f.y
      control2X: neckPath.g.x; control2Y: neckPath.g.y
      x: neckPath.h.x; y: neckPath.h.y
    }
    PathLine { x: neckPath.a.x; y: neckPath.a.y }
  }

  ShapePath {
    fillColor: root.kind === "dot" ? root.color : "transparent"
    strokeWidth: 0
    PathAngleArc {
      moveToStart: true
      centerX: root.centerX; centerY: root.centerY
      radiusX: root.size / 2 * root.sx; radiusY: root.size / 2 * root.sy
      startAngle: 0; sweepAngle: 360
    }
  }

  // ▶, a touch taller than the dot so the two weigh the same, and nudged right
  // of centre so its mass sits in the middle (as StatusGlyph's).
  ShapePath {
    id: play
    readonly property real h: root.size * 1.1 * root.sy
    readonly property real w: root.size * 1.1 * 0.88 * root.sx
    readonly property real left: root.centerX - w / 2 + w * 0.06
    fillColor: root.kind === "play" ? root.color : "transparent"
    strokeWidth: 0
    startX: play.left; startY: root.centerY - play.h / 2
    PathLine { x: play.left + play.w; y: root.centerY }
    PathLine { x: play.left; y: root.centerY + play.h / 2 }
    PathLine { x: play.left; y: root.centerY - play.h / 2 }
  }
}
