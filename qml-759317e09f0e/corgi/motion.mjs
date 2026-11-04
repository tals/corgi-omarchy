// motion.ts
import"./qml_shims.mjs";
import * as corgiAnimation from "./corgi_animation.mjs";
import * as palette from "./palette.mjs";
//! Corgi's sidebar animations for the Omarchy panel: each agent row's activity
//! glyph and the corgi on its second line, drawn by Corgi's own animation code
//! and handed to QML as styled text. Corgi's build compiles it, with the
//! Corgi modules it imports as `@corgi/NAME`, into ES modules for Qt's engine:
//! see HACKING.md. That engine has no BigInt literals or `Intl`, and builtins
//! it lacks come from qml_shims.js.
var hex = (c) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
var rgb = (value) => [1, 3, 5].map((i) => parseInt(value.slice(i, i + 2), 16));
var recolor = new Map;
var background = palette.colors.bg;
function theme(text, panel, accent) {
  const fade = (amount) => {
    const t = rgb(text), b = rgb(panel);
    return hex(t.map((v, i) => b[i] + (v - b[i]) * amount));
  };
  background = rgb(panel);
  recolor = new Map([
    [hex(palette.colors.text), text],
    [hex(palette.colors.strong), text],
    [hex(palette.colors.muted), fade(0.72)],
    [hex(palette.colors.faint), fade(0.5)],
    [hex(palette.colors.accent), accent]
  ]);
}
var entities = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", " ": "&nbsp;" };
function styled(ansi) {
  var _a;
  let out = "", open = false;
  const parts = ansi.split(/\x1b\[([0-9;]*)m/);
  for (let i = 0;i < parts.length; i++) {
    if (i % 2 === 0) {
      out += parts[i].replace(/[&<>" ]/g, (c) => entities[c]);
      continue;
    }
    const codes = parts[i].split(";").map(Number);
    if (codes[0] !== 38 || codes[1] !== 2)
      continue;
    const color = hex([codes[2], codes[3], codes[4]]);
    if (open)
      out += "</font>";
    out += `<font color="${(_a = recolor.get(color)) !== null && _a !== undefined ? _a : color}">`;
    open = true;
  }
  return open ? out + "</font>" : out;
}
function frame(now, rows) {
  corgiAnimation.beginFrame();
  const sleepers = rows.filter((r) => r.corgi === "asleep").map((r) => r.key), dream = corgiAnimation.dreamer(sleepers, now);
  const frames = rows.map((r) => {
    const glyph = corgiAnimation.activityGlyph(r.glyph, now), p = corgiAnimation.observe(r.key, r.corgi, now, r.since > 0 ? r.since : undefined);
    if (!p || r.corgi === "content")
      return { glyph, line: "" };
    if (r.corgi === "herding")
      return { glyph, line: styled(p.writeHerding(r.room, now)) };
    const sleep = new corgiAnimation.Sleep({
      background,
      bright: r.bright,
      puff_ms: dream && dream.key === r.key ? dream.puff_ms : null
    });
    return { glyph, line: styled(p.writeCorgi(r.room, now, r.working, sleep)) };
  });
  corgiAnimation.endFrame();
  return frames;
}
function delay() {
  return corgiAnimation.frameDelay();
}
export {
  delay,
  frame,
  theme
};
