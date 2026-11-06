// src/terminal_palette.ts
var steps = { surface: 1.17, selected: 1.5, line: 2.4 };
var min_line = 2.2;
var readable = 4.6;
var keycap_room = 4.7;
var min_text = 7.5;
var dark_enough = 8;
var min_chroma = 0.04;
var slots = { accent: [2, 10], warm: [3, 11], hot: [1, 9] };
var fallback_hues = { accent: [155, 230], warm: [80, 55], hot: [30, 0] };
var apart = 0.06;
var families = { warm: [45, 125], hot: [330, 50] };
function inFamily(name, hue) {
  const range = families[name];
  if (!range)
    return true;
  const h = (hue + 360) % 360;
  return range[0] <= range[1] ? h >= range[0] && h <= range[1] : h >= range[0] || h <= range[1];
}
function tokens(c) {
  const terminal = c.background, dark = !light(c), extreme = dark ? [255, 255, 255] : [0, 0, 0], opposite = dark ? [0, 0, 0] : [255, 255, 255], clear = contrast(extreme, terminal) / keycap_room >= min_line, bg = clear ? terminal : reach(terminal, opposite, (g) => contrast(extreme, g) / keycap_room >= steps.line), scale = Math.log(Math.min(steps.line, contrast(extreme, bg) / keycap_room)) / Math.log(steps.line), ink = luminance(c.foreground) > luminance(bg) === dark ? c.foreground : extreme, text = reach(ink, extreme, (ground) => contrast(ground, bg) >= min_text), along = (to, target) => reach(bg, to, (ground) => contrast(ground, bg) >= target ** scale), surface = along(text, steps.surface), selected = along(text, steps.selected), line = along(text, steps.line), faint = reach(bg, text, (ink) => contrast(ink, surface) >= readable && contrast(ink, bg) >= readable), middle = Math.sqrt(contrast(faint, bg) * contrast(text, bg)), muted = reach(faint, text, (ink) => contrast(ink, bg) >= middle && contrast(ink, selected) >= readable), strong = reach(mixLab(text, extreme, 0.55), extreme, (ink) => contrast(ink, line) >= readable), status = statuses(c.ansi, [bg, surface, selected], extreme);
  return {
    colors: {
      bg,
      surface,
      selected,
      line,
      faint,
      muted,
      text,
      strong,
      accent: status.accent,
      warm: status.warm,
      hot: status.hot
    },
    clear
  };
}
function light(c) {
  const ink = luminance(c.foreground), ground = luminance(c.background);
  return ink !== ground ? ink < ground : ground >= 0.18;
}
function onBackground(own, background) {
  if (luminance(background) >= luminance(own.text) || contrast(own.text, background) < dark_enough)
    return null;
  const bg = background, white = [255, 255, 255], along = (target) => reach(bg, own.text, (ground) => contrast(ground, bg) >= target), surface = along(steps.surface), selected = along(steps.selected), line = along(steps.line), keep = (ink, grounds) => lift(ink, white, (lifted) => grounds.every((ground) => contrast(lifted, ground) >= 4.5)).rgb, grounds = [bg, surface, selected];
  return {
    bg,
    surface,
    selected,
    line,
    faint: keep(own.faint, [bg, surface]),
    muted: keep(own.muted, grounds),
    text: keep(own.text, grounds),
    strong: keep(own.strong, [...grounds, line]),
    accent: keep(own.accent, grounds),
    warm: keep(own.warm, grounds),
    hot: keep(own.hot, grounds)
  };
}
function supplied(ansi) {
  const has = (name) => slots[name].some((slot) => {
    const color = ansi[slot];
    if (!color)
      return false;
    const [, chroma, hue] = lch(oklab(color));
    return chroma >= min_chroma && inFamily(name, hue);
  });
  return { accent: has("accent"), warm: has("warm"), hot: has("hot") };
}
function hue(rgb) {
  const [, chroma, h] = lch(oklab(rgb));
  return { chroma, hue: (h + 360) % 360, gray: chroma < min_chroma };
}
function statuses(ansi, grounds, extreme) {
  var _a, _b;
  const fits = (ink) => grounds.every((ground) => contrast(ink, ground) >= readable), chromas = ansi.flatMap((color) => color ? [lch(oklab(color))[1]] : []).filter((c) => c >= min_chroma), chroma = chromas.length > 0 ? Math.min(0.16, Math.max(0.08, median(chromas))) : 0.12, chosen = [], out = {};
  for (const name of ["warm", "hot", "accent"]) {
    const distinct = (ink) => chosen.every((other) => distance(ink, other) >= apart);
    const own = slots[name].map((slot) => ansi[slot]).filter((color) => color !== null && lch(oklab(color))[1] >= min_chroma).filter((color) => inFamily(name, lch(oklab(color))[2]));
    const candidates = own.map((color) => lift(color, extreme, fits)).filter((candidate) => distinct(candidate.rgb));
    const fallbacks = () => fallback_hues[name].map((hue) => lift(fromLch([0.75, chroma, hue]), extreme, fits).rgb);
    const pick = candidates.length > 0 ? candidates.reduce((best, next) => next.moved < best.moved ? next : best).rgb : (_b = (_a = own.length > 0 ? turn(own[0], fallback_hues[name][0], (ink) => distinct(ink) && inFamily(name, lch(oklab(ink))[2]), extreme, fits) : null) !== null && _a !== undefined ? _a : fallbacks().find(distinct)) !== null && _b !== undefined ? _b : fallbacks()[0];
    out[name] = pick;
    chosen.push(pick);
  }
  return out;
}
function turn(color, hue, distinct, extreme, fits) {
  const [l, c, h] = lch(oklab(color)), way = Math.sign((hue - h + 540) % 360 - 180) || 1;
  for (let degrees = 5;degrees <= 120; degrees += 5) {
    const ink = lift(fromLch([l, c, h + way * degrees]), extreme, fits).rgb;
    if (distinct(ink))
      return ink;
  }
  return null;
}
function distance(a, b) {
  const x = oklab(a), y = oklab(b);
  return Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2]);
}
function lift(color, extreme, ok) {
  if (ok(color))
    return { rgb: color, moved: 0 };
  const [l, c, h] = lch(oklab(color)), end = oklab(extreme)[0], at = (hue) => {
    const t = solve((t) => ok(fromLch([l + (end - l) * t, c, hue])));
    return { rgb: fromLch([l + (end - l) * t, c, hue]), moved: t };
  }, keeps = (lifted) => lch(oklab(lifted.rgb))[1] >= c * 0.75, straight = at(h);
  if (end > l || h < 60 || h > 120 || keeps(straight))
    return straight;
  for (let degrees = 5;degrees <= 25; degrees += 5) {
    const turned = at(h - degrees);
    if (keeps(turned))
      return turned;
  }
  return straight;
}
function reach(from, to, ok) {
  return ok(from) ? from : mixLab(from, to, solve((t) => ok(mixLab(from, to, t))));
}
function solve(ok) {
  let lo = 0, hi = 1;
  for (let i = 0;i < 24; i++) {
    const mid = (lo + hi) / 2;
    if (ok(mid))
      hi = mid;
    else
      lo = mid;
  }
  return hi;
}
function luminance(rgb) {
  const [r, g, b] = rgb.map(linear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a, b) {
  const x = luminance(a), y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}
function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}
function mixLab(a, b, t) {
  const x = oklab(a), y = oklab(b);
  return fromLab(x.map((v, i) => v + (y[i] - v) * t));
}
var linear = (c) => {
  const v = c / 255;
  return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
};
var encode = (v) => v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055;
function oklab(rgb) {
  const [r, g, b] = rgb.map(linear), l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b), m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b), s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  ];
}
function linearRgb([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3, m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3, s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
  ];
}
function fromLab(lab) {
  const inGamut = (x) => linearRgb(x).every((v) => v >= -0.0001 && v <= 1 + 0.0001);
  let fitted = lab;
  if (!inGamut(lab)) {
    const keep = 1 - solve((t) => inGamut([lab[0], lab[1] * (1 - t), lab[2] * (1 - t)]));
    fitted = [lab[0], lab[1] * keep, lab[2] * keep];
  }
  return linearRgb(fitted).map((v) => Math.round(encode(Math.min(1, Math.max(0, v))) * 255));
}
function lch(lab) {
  return [lab[0], Math.hypot(lab[1], lab[2]), Math.atan2(lab[2], lab[1]) * 180 / Math.PI];
}
function fromLch([l, c, h]) {
  const rad = h * Math.PI / 180;
  return fromLab([l, c * Math.cos(rad), c * Math.sin(rad)]);
}
export {
  contrast,
  hue,
  light,
  onBackground,
  supplied,
  tokens
};
