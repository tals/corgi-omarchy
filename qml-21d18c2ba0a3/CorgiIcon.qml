pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The head from Corgi's logo, without its circle, in one colour. corgi.png is
// white with the logo's tones in its alpha: the cream at full, the orange fur
// at 45%, the eyes, nose and mouth clear. It's tinted with MultiEffect's
// colorization, as the shell tints one-colour notification icons. Those also
// set brightness 1.0 to whiten dark artwork first; this artwork is already
// white, and with brightness 1.0 the result comes out at twice the colour
// (#2a2a2a paints as #545454), so it stays at 0 and the corgi takes the
// colour exactly, matching the bar's glyphs.
//
// The PNG is decoded at the icon's size in device pixels and drawn 1:1. Left
// to the GPU, a 64px image shrunk to twelve pixels blends in a smaller mipmap
// level, and the two tones go soft. The box is the PNG's whole square rather
// than the head's ink, so it is a whole number of pixels tall and the shell
// centres it on whole pixels. The head spans the full width, so the shell's
// icon sizing, which measures an image by its painted box, still scales the
// head to the icon size. Widget.qml puts the box on whole device pixels.
Item {
  id: root

  property real iconSize: Style.bar.iconSize
  property color color: Commons.Color.foreground
  // A small download mark in the bottom-right corner, drawn like the shell's
  // own corner marks (Tailscale's login warning).
  property bool installMark: false
  property color markColor: Commons.Color.accent

  // The head's own ink (alpha above 16) inside the PNG's 64px square.
  readonly property rect ink: Qt.rect(0, 3, 64, 58)

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: implicitWidth
  height: implicitHeight

  Image {
    anchors.fill: parent
    source: Qt.resolvedUrl("corgi.png")
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
    layer.enabled: true
    layer.effect: MultiEffect {
      colorization: 1.0
      colorizationColor: root.color
    }
  }

  BorderSurface {
    visible: root.installMark
    width: Math.max(7, root.iconSize * 0.42)
    height: width
    radius: width / 2
    color: root.markColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    // On the head's bottom edge, not the square's.
    anchors.bottomMargin: root.iconSize * (64 - root.ink.y - root.ink.height) / 64
    borderSpec: Border.flat(Commons.Color.popups.background, 1)

    // A down arrow: a stem and a head, drawn rather than set in a font so it
    // stays centred at this size whatever font the bar uses.
    Shape {
      id: arrow
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: Commons.Color.background
        strokeWidth: 0
        startX: arrow.width * 0.43; startY: arrow.height * 0.22
        PathLine { x: arrow.width * 0.57; y: arrow.height * 0.22 }
        PathLine { x: arrow.width * 0.57; y: arrow.height * 0.48 }
        PathLine { x: arrow.width * 0.76; y: arrow.height * 0.48 }
        PathLine { x: arrow.width * 0.50; y: arrow.height * 0.80 }
        PathLine { x: arrow.width * 0.24; y: arrow.height * 0.48 }
        PathLine { x: arrow.width * 0.43; y: arrow.height * 0.48 }
        PathLine { x: arrow.width * 0.43; y: arrow.height * 0.22 }
      }
    }
  }
}
