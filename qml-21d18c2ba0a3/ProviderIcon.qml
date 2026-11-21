import QtQuick
import qs.Commons

// A provider's brand mark from the plugin's icons/ folder, by the rule of
// Omarchy's agents plugin: a mark drawn in white ships a -light twin, tried
// first on a light panel; colored marks ship one file. `ready` is false for a
// provider with no mark, so the caller can show its name instead.
Item {
  id: mark

  property string provider: ""
  property real size: Style.font.body
  property string iconDir: ""
  property bool lightSurface: false

  readonly property var brands: ["claude", "codex", "opencode", "omp", "pi"]
  readonly property var whiteMarks: ["codex", "opencode", "omp"]
  readonly property bool known: iconDir !== "" && brands.indexOf(provider) !== -1
  readonly property var candidates: {
    if (!known) return []
    var base = iconDir + "/" + provider
    var out = []
    if (lightSurface && whiteMarks.indexOf(provider) !== -1) out.push(Util.fileUrl(base + "-light.svg"))
    out.push(Util.fileUrl(base + ".svg"))
    return out
  }
  property int candidateIndex: 0
  onCandidatesChanged: candidateIndex = 0
  readonly property bool ready: markImage.status === Image.Ready

  width: size
  height: size

  Image {
    id: markImage
    anchors.fill: parent
    source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
    sourceSize.width: mark.size * 2
    sourceSize.height: mark.size * 2
    fillMode: Image.PreserveAspectFit
    smooth: true
    // Stepping from inside its own status change trips the binding-loop
    // detector; defer it a tick, as Omarchy does.
    onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
      Qt.callLater(function() { mark.candidateIndex++ })
  }
}
