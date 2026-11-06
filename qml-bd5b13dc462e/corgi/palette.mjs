// src/palette.ts
import * as terminalPalette from "./terminal_palette.mjs";
//! The Omarchy panel runs this in Qt's QML engine (corgi-omarchy/tools/motion-build.ts):
//! no BigInt literals or `Intl`, and builtins Qt lacks only through
//! the Omarchy plugin's qml_shims.js.
var corgi = {
  bg: [24, 27, 32],
  surface: [35, 40, 47],
  selected: [51, 57, 65],
  line: [80, 90, 101],
  faint: [131, 144, 158],
  muted: [165, 174, 184],
  text: [209, 214, 219],
  strong: [238, 241, 244],
  accent: [123, 241, 168],
  warm: [229, 195, 139],
  hot: [237, 163, 152]
};
var themes = {
  corgi: { label: "Corgi" },
  animal_style: { label: "Animal Style" }
};
var available_themes = Object.keys(themes);
function parseTheme(name) {
  return Object.hasOwn(themes, name) ? name : null;
}
var colors = Object.fromEntries(Object.entries(corgi).map(([token, rgb]) => [token, [...rgb]]));
var current = "corgi";
function looks(host) {
  const kept = host && terminalPalette.onBackground(corgi, host.background);
  return {
    corgi: kept ? { colors: kept, clear: true } : { colors: corgi, clear: false },
    animal_style: host ? terminalPalette.tokens(host) : { colors: corgi, clear: true }
  };
}
var terminal = null;
var look = looks(null);
var refreshers = [];
function derived(refresh) {
  refresh();
  refreshers.push(refresh);
}
function use(choice, host = null) {
  const recolored = host !== terminal;
  if (recolored) {
    terminal = host;
    look = looks(host);
  }
  const name = chosen(choice);
  if (name === current && !recolored)
    return;
  current = name;
  const next = tokensOf(name);
  for (const token of Object.keys(colors))
    colors[token].splice(0, 3, ...next[token]);
  for (const refresh of refreshers)
    refresh();
}
function chosen(choice) {
  return choice !== null && choice !== undefined ? choice : terminal && terminalPalette.light(terminal) ? "animal_style" : "corgi";
}
function painted() {
  return paints(current) ? colors.bg : null;
}
function tokensOf(theme) {
  return look[theme].colors;
}
function paints(theme) {
  return !look[theme].clear;
}
function fg(t, theme = current) {
  return fgRgb(tokensOf(theme)[t]);
}
function swatch(t, theme) {
  return bgRgb(tokensOf(theme)[t]);
}
function bg(t, theme = current) {
  return `\x1B[${bgFields(t, theme).join(";")}m`;
}
function bgFields(t, theme) {
  if (t === "bg" && !paints(theme))
    return ["49"];
  return ["48", "2", ...tokensOf(theme)[t].map(String)];
}
function fgRgb(c) {
  return `\x1B[38;2;${c.join(";")}m`;
}
function bgRgb(c) {
  return `\x1B[48;2;${c.join(";")}m`;
}
function mix(a, b, percentage) {
  return a.map((v, i) => Math.floor((v * (100 - Math.min(100, percentage)) + b[i] * Math.min(100, percentage) + 50) / 100));
}

class Style {
  constructor(value = {}) {
    this.value = value;
  }
  sgr() {
    const fields = ["0"];
    if (this.value.bold)
      fields.push("1");
    if (this.value.italic)
      fields.push("3");
    if (this.value.underline)
      fields.push("4");
    if (this.value.strike)
      fields.push("9");
    if (this.value.fg)
      fields.push("38", "2", ...colors[this.value.fg].map(String));
    if (this.value.bg)
      fields.push(...bgFields(this.value.bg, current));
    return `\x1B[${fields.join(";")}m`;
  }
}
var keycap;
var outline;
var selection;
var selection_bg;
var call_to_action;
var call_to_action_bg;
derived(() => {
  keycap = new Style({ fg: "strong", bg: "line", bold: true }).sgr();
  outline = mix(colors.accent, colors.line, 50);
  selection_bg = mix(colors.selected, colors.accent, 30);
  selection = fgRgb(colors.strong) + bgRgb(selection_bg);
  call_to_action_bg = mix(colors.surface, colors.accent, 22);
  call_to_action = "\x1B[0m" + bgRgb(call_to_action_bg) + "\x1B[1m" + fgRgb(colors.accent);
});
var corgi_syntax = {
  keyword: [196, 167, 242],
  string: [167, 201, 234],
  number: [230, 177, 214],
  type: [134, 207, 208],
  property: [180, 196, 221]
};
var syntax_slots = {
  keyword: [5, 13],
  string: [4, 12],
  number: [13, 5],
  type: [6, 14],
  property: [12, 4]
};
var syntax = {};
function readableOnBg(rgb) {
  let out = rgb;
  for (let step = 10;step <= 100 && terminalPalette.contrast(out, colors.bg) < 4.6; step += 10)
    out = mix(rgb, colors.text, step);
  return out;
}
derived(() => {
  const host = current === "animal_style" ? terminal : null;
  for (const name of Object.keys(corgi_syntax)) {
    const own = syntax_slots[name].map((slot) => {
      var _a;
      return (_a = host === null || host === undefined ? undefined : host.ansi[slot]) !== null && _a !== undefined ? _a : null;
    }).find((c) => c !== null);
    syntax[name] = readableOnBg(own !== null && own !== undefined ? own : corgi_syntax[name]);
  }
  syntax.function = colors.strong;
  syntax.comment = colors.faint;
  syntax.punctuation = colors.muted;
});
function underline(token) {
  return `\x1B[58:2::${colors[token].join(":")}m`;
}
function writeFg(writer, rgb) {
  writer.write(fgRgb(rgb));
}
function luminance(rgb) {
  return rgb.reduce((sum, channel, index) => {
    const value = channel / 255;
    return sum + [0.2126, 0.7152, 0.0722][index] * (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  }, 0);
}
function contrast2(first, second) {
  const a = luminance(corgi[first]), b = luminance(corgi[second]);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
function termhtmlTheme() {
  const hex = (token) => "#" + corgi[token].map((value) => value.toString(16).padStart(2, "0")).join("");
  return "corgi: { " + Object.keys(corgi).map((token) => `${token}: "${hex(token)}", `).join("") + `fg: "${hex("text")}", danger: "${hex("hot")}" },`;
}
export {
  Style,
  available_themes,
  bg,
  bgRgb,
  call_to_action,
  call_to_action_bg,
  chosen,
  colors,
  contrast2 as contrast,
  derived,
  fg,
  fgRgb,
  keycap,
  luminance,
  mix,
  outline,
  painted,
  parseTheme,
  selection,
  selection_bg,
  swatch,
  syntax,
  termhtmlTheme,
  themes,
  underline,
  use,
  writeFg
};
