// site/browser/viewer_native.ts
import WIDTHS from "./widths.mjs";
//! The Omarchy panel runs this in Qt's QML engine (tools/omarchy_motion.ts):
//! no BigInt literals or `Intl`, and builtins Qt lacks only through
//! the Omarchy plugin's qml_shims.js.
var table = null;
function codepointWidths() {
  if (!table) {
    table = new Uint8Array(1114112).fill(1);
    for (const [from, to, width] of WIDTHS)
      table.fill(width, from, to + 1);
  }
  return table;
}
export {
  codepointWidths
};
