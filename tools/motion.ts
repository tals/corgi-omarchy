//! Corgi's sidebar animations for the Omarchy panel: each agent row's activity
//! glyph and the corgi on its second line, drawn by Corgi's own animation code
//! and handed to QML as styled text. tools/build_corgi.ts compiles it, with the
//! Corgi modules it imports as `@corgi/NAME`, into ES modules for Qt's engine:
//! see HACKING.md. That engine has no BigInt literals or `Intl`, and builtins
//! it lacks come from qml_shims.js.
import "./qml_shims.js";
import * as corgiAnimation from "@corgi/corgi_animation";
import * as palette from "@corgi/palette";

/** One animated row, as `corgi watch --json` describes its agent. */
export type Row = {
  key: string;
  glyph: corgiAnimation.Activity;
  corgi: corgiAnimation.Mode;
  /** Columns the corgi may use. */
  room: number;
  working: boolean;
  /** Finished and unseen: its nap stays bright, as in the sidebar. */
  bright: boolean;
  /** When its compaction began, in ms, or 0. */
  since: number;
};
export type Frame = { glyph: string; line: string };

type Rgb = [number, number, number];
const hex = (c: Rgb) => "#" + c.map(v => Math.round(v).toString(16).padStart(2, "0")).join("");
const rgb = (value: string): Rgb => [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16)) as Rgb;

/** Corgi's own colors, by value, and what each becomes in the panel. */
let recolor = new Map<string, string>();
let background: Rgb = palette.colors.bg;

/** The panel's colors: its text and background, and Corgi's accent as the widget shows it. */
export function theme(text: string, panel: string, accent: string) {
  const fade = (amount: number) => {
    const t = rgb(text),
      b = rgb(panel);
    return hex(t.map((v, i) => b[i] + (v - b[i]) * amount) as Rgb);
  };
  background = rgb(panel);
  recolor = new Map([
    [hex(palette.colors.text), text],
    [hex(palette.colors.strong), text],
    [hex(palette.colors.muted), fade(0.72)],
    [hex(palette.colors.faint), fade(0.5)],
    [hex(palette.colors.accent), accent],
  ]);
}

const entities: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", " ": "&nbsp;" };
/** A line of terminal output as QML styled text, in the panel's colors. */
function styled(ansi: string): string {
  let out = "",
    open = false;
  const parts = ansi.split(/\x1b\[([0-9;]*)m/);
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 0) {
      out += parts[i].replace(/[&<>" ]/g, c => entities[c]);
      continue;
    }
    const codes = parts[i].split(";").map(Number);
    if (codes[0] !== 38 || codes[1] !== 2) continue;
    const color = hex([codes[2], codes[3], codes[4]]);
    if (open) out += "</font>";
    out += `<font color="${recolor.get(color) ?? color}">`;
    open = true;
  }
  return open ? out + "</font>" : out;
}

/** Each row's glyph and second line at `now`, in ms. Rows not asked about
 * again forget their corgi, as rows scrolled out of the sidebar do. */
export function frame(now: number, rows: Row[]): Frame[] {
  corgiAnimation.beginFrame();
  const sleepers = rows.filter(r => r.corgi === "asleep").map(r => r.key),
    dream = corgiAnimation.dreamer(sleepers, now);
  const frames = rows.map(r => {
    const glyph = corgiAnimation.activityGlyph(r.glyph, now),
      p = corgiAnimation.observe(r.key, r.corgi, now, r.since > 0 ? r.since : undefined);
    if (!p || r.corgi === "content") return { glyph, line: "" };
    if (r.corgi === "herding") return { glyph, line: styled(p.writeHerding(r.room, now)) };
    const sleep = new corgiAnimation.Sleep({
      background,
      bright: r.bright,
      puff_ms: dream && dream.key === r.key ? dream.puff_ms : null,
    });
    return { glyph, line: styled(p.writeCorgi(r.room, now, r.working, sleep)) };
  });
  corgiAnimation.endFrame();
  return frames;
}

/** How long until the next frame is due, in ms. */
export function delay(): number {
  return corgiAnimation.frameDelay();
}
