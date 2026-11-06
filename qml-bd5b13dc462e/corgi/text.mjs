// src/text.ts
import { codepointWidths } from "./viewer_native.mjs";
//! Text measurement and clipping as the Zig viewer does it: Ghostty's width
//! per codepoint, byte lengths where Zig counts bytes. sidebar.zig keeps
//! these helpers; the TypeScript viewer shares them from here.
//! The Omarchy panel runs this in Qt's QML engine (corgi-omarchy/tools/motion-build.ts):
//! no BigInt literals or `Intl`, and builtins Qt lacks only through
//! the Omarchy plugin's qml_shims.js.

class Writer {
  constructor(column = 0) {
    this.column = column;
    this.s = "";
  }
  cup(row, column) {
    return `\x1B[${row};${column + this.column}H`;
  }
  withColumns(columns, draw) {
    const previous = this.column;
    this.column += columns;
    try {
      return draw();
    } finally {
      this.column = previous;
    }
  }
  write(text) {
    this.s += text;
  }
  splat(char, count) {
    if (count > 0)
      this.s += char.repeat(count);
  }
  buffered() {
    return this.s;
  }
  clear() {
    this.s = "";
  }
}
function codepointWidth(cp) {
  var _a;
  return (_a = codepointWidths()[cp]) !== null && _a !== undefined ? _a : 1;
}
function displayWidth(text) {
  const table = codepointWidths();
  let width = 0;
  for (let i = 0;i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 128) {
      width += table[c];
      continue;
    }
    const cp = text.codePointAt(i);
    if (cp > 65535)
      i++;
    width += table[cp];
  }
  return width;
}
function byteLength(text) {
  return Buffer.byteLength(text);
}
function byteSlice(text, bytes) {
  if (bytes >= text.length * 3)
    return text;
  let used = 0;
  let end = 0;
  for (const ch of text) {
    const size = utf8Size(ch.codePointAt(0));
    if (used + size > bytes)
      break;
    used += size;
    end += ch.length;
  }
  return text.slice(0, end);
}
function utf8Size(cp) {
  return cp < 128 ? 1 : cp < 2048 ? 2 : cp < 65536 ? 3 : 4;
}
function writeClipped(w, text, room) {
  w.write(clipped(text, room));
}
function clipped(text, room) {
  let used = 0;
  let end = 0;
  for (const ch of text) {
    used += codepointWidth(ch.codePointAt(0));
    if (used > room)
      break;
    end += ch.length;
  }
  return text.slice(0, end);
}
function wrap(value, width) {
  if (width <= 0 || !value)
    return [];
  const lines = [];
  for (let paragraph of value.split(`
`)) {
    paragraph = paragraph.trim();
    if (!paragraph) {
      lines.push("");
      continue;
    }
    while (paragraph) {
      let part = clipped(paragraph, width);
      if (!part) {
        const first = [...paragraph][0];
        lines.push("…");
        paragraph = paragraph.slice(first.length).trimStart();
        continue;
      }
      if (part.length < paragraph.length) {
        const space = part.lastIndexOf(" ");
        if (space > 0)
          part = part.slice(0, space);
      }
      lines.push(part.trimEnd());
      paragraph = paragraph.slice(part.length).trimStart();
    }
  }
  return lines;
}
function writeEllipsis(w, text, room) {
  w.write(ellipsis(text, room));
}
function ellipsis(text, room) {
  if (displayWidth(text) <= room)
    return text;
  if (room <= 0)
    return "";
  return clipped(text, room - 1) + "…";
}
function isControl(cp) {
  return cp < 32 || cp >= 127 && cp <= 159 || cp >= 55296 && cp <= 57343;
}
function spacedControls(text) {
  let out = "";
  for (const ch of text)
    out += isControl(ch.codePointAt(0)) ? " " : ch;
  return out;
}
function writeSanitized(w, value, room) {
  let clean = "";
  let n = 0;
  for (const ch of value) {
    if (n >= 2048 - 4)
      break;
    const cp = ch.codePointAt(0);
    if (isControl(cp)) {
      clean += " ";
      n += 1;
      continue;
    }
    clean += ch;
    n += utf8Size(cp);
  }
  writeEllipsis(w, clean, room);
}
function shortPath(path, room) {
  if (displayWidth(path) <= room)
    return path;
  const split = path.split("/"), parts = path.startsWith("/") ? ["/" + split[1], ...split.slice(2)] : split, last = parts[parts.length - 1], fits = (s) => displayWidth(s) <= room;
  if (parts.length > 3) {
    const join = (kept) => [parts[0], parts[1], "…", ...kept, last].join("/");
    if (fits(join([]))) {
      let kept = [];
      for (let i = parts.length - 2;i >= 3 && fits(join([parts[i], ...kept])); i--)
        kept = [parts[i], ...kept];
      return join(kept);
    }
  }
  const prefix = parts[0] + "/…/";
  if (parts.length > 2 && fits(prefix + last))
    return prefix + last;
  if (parts.length > 2 && room - displayWidth(prefix) >= 6)
    return prefix + ellipsis(last, room - displayWidth(prefix));
  return ellipsis(path, room);
}
function directoryLabel(cwd, home = null, cap = 4097) {
  let source = cwd.length === 0 ? "?" : cwd;
  let out = "";
  let len = 0;
  if (home !== null && home.length > 0 && source.startsWith(home) && (source.length === home.length || source[home.length] === "/")) {
    out = "~";
    len = 1;
    source = source.slice(home.length);
  }
  for (const ch of source) {
    if (len >= cap)
      break;
    const cp = ch.codePointAt(0);
    const valid = cp >= 32 && !(cp >= 127 && cp <= 159);
    const count = valid ? utf8Size(cp) : 1;
    if (len + count > cap)
      break;
    out += valid ? ch : "?";
    len += count;
  }
  return out;
}
var countScales = [
  [1000000000000000000, "E"],
  [1000000000000000, "P"],
  [1000000000000, "T"],
  [1e9, "G"],
  [1e6, "M"],
  [1000, "k"]
];
function compactCount(value) {
  const v = Number(value);
  for (const [scale, suffix] of countScales)
    if (v >= scale)
      return `${Math.floor(v / scale)}${suffix}`;
  return String(value);
}
function sat(a, b) {
  return a > b ? a - b : 0;
}
function clamp(value, low, high) {
  return Math.min(Math.max(value, low), high);
}
function zigRound(value) {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}
function truncatedText(value, cap) {
  return byteSlice(value, cap);
}
function asciiText(value, cap) {
  const bytes = Buffer.from(value).subarray(0, cap);
  return Array.from(bytes, (ch) => ch >= 32 && ch < 127 ? String.fromCharCode(ch) : " ").join("");
}
export {
  Writer,
  asciiText,
  byteLength,
  byteSlice,
  clamp,
  clipped,
  codepointWidth,
  compactCount,
  directoryLabel,
  displayWidth,
  ellipsis,
  isControl,
  sat,
  shortPath,
  spacedControls,
  truncatedText,
  utf8Size,
  wrap,
  writeClipped,
  writeEllipsis,
  writeSanitized,
  zigRound
};
