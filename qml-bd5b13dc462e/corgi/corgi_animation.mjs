// src/corgi_animation.ts
import * as palette from "./palette.mjs";
import * as frames from "./corgi_frames.mjs";
import * as i18n from "./i18n.mjs";
import { displayWidth, ellipsis } from "./text.mjs";
//! Viewer-local corgi motion policies mirrored from corgi_animation.zig.
//! The landing page bundles this module, so it uses only what browsers have.
//! The Omarchy panel runs this in Qt's QML engine (corgi-omarchy/tools/motion-build.ts):
//! no BigInt literals or `Intl`, and builtins Qt lacks only through
//! the Omarchy plugin's qml_shims.js.
var golden = 2654435769;
function mix(value) {
  let z = Math.imul(value ^ value >>> 16, 2246822507);
  z = Math.imul(z ^ z >>> 13, 3266489909);
  return (z ^ z >>> 16) >>> 0;
}
function hash(key) {
  let h = 2166136261;
  for (let i = 0;i < key.length; i++)
    h = Math.imul(h ^ key.charCodeAt(i), 16777619);
  return h >>> 0;
}
var randomSeed = () => typeof crypto !== "undefined" ? crypto.getRandomValues(new Uint32Array(1))[0] : Math.floor(Math.random() * 4294967296);
var rotate = (v, n) => (v << n | v >>> 32 - n) >>> 0;

class Random {
  constructor(seed = 0) {
    let value = seed >>> 0;
    this.state = Array.from({ length: 4 }, () => {
      value = value + golden >>> 0;
      return mix(value);
    });
  }
  next() {
    const s = this.state, r = Math.imul(rotate(Math.imul(s[1], 5) >>> 0, 7), 9) >>> 0, t = s[1] << 9 >>> 0;
    s[2] = (s[2] ^ s[0]) >>> 0;
    s[3] = (s[3] ^ s[1]) >>> 0;
    s[1] = (s[1] ^ s[2]) >>> 0;
    s[0] = (s[0] ^ s[3]) >>> 0;
    s[2] = (s[2] ^ t) >>> 0;
    s[3] = rotate(s[3], 11);
    return r;
  }
  float() {
    return ((this.next() >>> 5) * 67108864 + (this.next() >>> 6)) / 9007199254740992;
  }
  int(n) {
    const threshold = (4294967296 - n) % n;
    for (;; ) {
      const product = this.next() * n;
      if (product % 4294967296 >= threshold)
        return Math.floor(product / 4294967296);
    }
  }
  boolean() {
    return (this.next() & 1) !== 0;
  }
}

class Throw {
  constructor(fields = {}) {
    this.speed = 1.6;
    this.lift = 1.1;
    this.spin = 0;
    this.seed = 0;
    Object.assign(this, fields);
  }
  static random(r) {
    const seed = r.next(), kind = r.int(3);
    if (kind === 0) {
      const speed = 1.5 + 0.4 * r.float();
      return new Throw({
        speed,
        lift: -(0.4 + 0.4 * r.float()),
        spin: -speed * (0.5 + 0.5 * r.float()),
        seed
      });
    }
    const angle = (kind === 1 ? 15 + 35 * r.float() : 30 + 15 * r.float()) * Math.PI / 180, force = kind === 1 ? 1.8 + 0.8 * r.float() : 2.6 + 0.8 * r.float(), speed = force * Math.cos(angle);
    return new Throw({
      speed,
      lift: force * Math.sin(angle) * (kind === 1 ? 1 : -1),
      spin: kind === 1 ? speed * (0.5 + 0.5 * r.float()) : 0,
      seed
    });
  }
}
var gait_right = ["~[/\\]o>", "~[||]o>", "~[\\/]o>", "~[||]o>"];
var gait_left_carry = ["●‹o[/\\]~", "●‹o[||]~", "●‹o[\\/]~", "●‹o[||]~"];
var dots = [
  [64, 4, 2, 1],
  [128, 32, 16, 8]
];

class Ball {
  constructor(value) {
    this.x = 12;
    this.y = 1;
    this.vx = value.speed;
    this.vy = value.lift;
    this.spin = value.spin;
    this.random = new Random(value.seed);
  }
  resting() {
    return this.y === 0 && this.vx === 0 && this.vy === 0;
  }
  reachable() {
    return Math.round(this.y) <= 1;
  }
  bounce(normal, kept) {
    const askew = (this.random.float() - 0.5) * 10 * Math.PI / 180, nx = normal[0] * Math.cos(askew) - normal[1] * Math.sin(askew), ny = normal[0] * Math.sin(askew) + normal[1] * Math.cos(askew), into = this.vx * nx + this.vy * ny;
    if (into >= 0)
      return false;
    const share = kept[0] + (kept[1] - kept[0]) * this.random.float(), along = this.vx * ny - this.vy * nx, slip = along + this.spin, rub = -Math.sign(slip) * Math.min(2 / 7 * Math.abs(slip), 0.15 * (1 + share) * -into), out = -share * into;
    this.spin += 2.5 * rub;
    this.vx = (along + rub) * ny + out * nx;
    this.vy = -(along + rub) * nx + out * ny;
    return true;
  }
  land() {
    this.y = 0;
    this.bounce([0, 1], [0.7, 0.9]);
    this.vy = Math.abs(this.vy);
    if (this.vy < 0.3) {
      this.vy = 0;
      this.vx -= 2 / 7 * (this.vx + this.spin);
      this.spin = -this.vx;
    }
  }
  step(width, near) {
    const foot = 2 * width - 3, far = 2 * width - 1, rolling = this.y === 0 && this.vy === 0;
    if (rolling) {
      const drag = 0.6 / (2 * width - 12);
      this.vx = Math.abs(this.vx) <= 0.25 ? 0 : this.vx - Math.sign(this.vx) * drag;
      this.spin = -this.vx;
    } else {
      this.vy -= 0.16;
      this.y += this.vy;
      if (this.y >= 3) {
        this.y = 3;
        this.bounce([0, -1], [0.7, 0.9]);
      } else if (this.y <= 0 && this.x <= foot)
        this.land();
    }
    this.x += this.vx;
    const surface = Math.min(this.x, far) - foot;
    if (surface > 0 && this.y < surface) {
      const depth = (surface - this.y) / 2;
      this.x -= depth;
      this.y = Math.max(0, this.y + depth);
      this.bounce([-Math.SQRT1_2, Math.SQRT1_2], rolling ? [0.25, 0.65] : [0.7, 0.9]);
    } else if (this.y < 0)
      this.land();
    if (this.x >= far) {
      this.x = far;
      this.bounce([-1, 0], [0.7, 0.9]);
      this.vx = -Math.abs(this.vx);
    } else if (this.x <= near) {
      this.x = near;
      this.bounce([1, 0], [0.7, 0.9]);
      this.vx = Math.abs(this.vx);
    }
  }
  dot() {
    const col = Math.round(this.x), row = Math.round(this.y);
    return { cell: Math.floor(col / 2), dots: dots[col % 2][row] };
  }
}
function chase(width, value, ticks) {
  const ball = new Ball(value), result = { ball, dog: null, landed: 0, caught: 0, stop: 0 };
  let up = null, x = 0, ran = false;
  for (let tick = 0;tick <= 1000; tick++) {
    const cell = ball.dot().cell, ready = result.landed > 0 && tick >= result.landed + 4;
    if (up !== null) {
      if (tick - up >= 4 && (tick - up) % 2 === 0) {
        ran = cell > x + 7 && x + 8 < width;
        if (ran)
          x++;
      }
    } else if (ready && cell >= x + 7)
      up = tick;
    if (tick === ticks) {
      result.ball = Object.assign(Object.create(Ball.prototype), ball);
      if (up !== null)
        result.dog = { x, pose: ran ? gait_right[x % 4] : gait_right[1] };
    }
    const near = up !== null ? x + 7 : 6;
    if (ready && cell <= near && ball.reachable() || tick === 1000) {
      result.caught = tick + 1;
      result.stop = x;
      return result;
    }
    ball.step(width, 2 * near);
    if (ball.y === 0 && !result.landed)
      result.landed = tick + 1;
  }
  return result;
}
function fetchScene(width, value, tick) {
  var _a, _b, _c, _d;
  let p = tick;
  const stage = (duration) => {
    if (p < duration)
      return true;
    p -= duration;
    return false;
  };
  const rest = "~ᐯ•ᴥ•ᐯ", held = "~ᐯ•●•ᐯ";
  if (stage(16))
    return { dog: Math.floor(p / 2) === 4 ? "~ᐯ◡ᴥ◡ᐯ" : rest, x: 0, ball: null };
  const run = chase(width, value, p);
  if (stage(run.caught))
    return {
      dog: (_b = (_a = run.dog) === null || _a === undefined ? undefined : _a.pose) !== null && _b !== undefined ? _b : p > run.landed ? "~ᐯ•ᴥ•ᐱ" : rest,
      x: (_d = (_c = run.dog) === null || _c === undefined ? undefined : _c.x) !== null && _d !== undefined ? _d : 0,
      ball: run.ball.dot()
    };
  p = Math.floor(p / 2);
  const stop = run.stop, turn = stop > 0 ? 2 : 0;
  if (stage(2))
    return { dog: "~[||]o●", x: stop, ball: null };
  if (stage(5))
    return { dog: held, x: stop, ball: null };
  if (stage(turn))
    return { dog: gait_left_carry[1], x: stop - 1, ball: null };
  if (stage(stop))
    return { dog: gait_left_carry[p % 4], x: stop - 1 - p, ball: null };
  if (stage(3))
    return { dog: held, x: 0, ball: null };
  return { dog: rest, x: 0, ball: null };
}
function fetchTicks(width, value) {
  const run = chase(width, value, 0);
  return 16 + run.caught + 2 * ((run.stop > 0 ? 2 : 0) + run.stop + 13);
}
var fetchPace = (width, value) => Math.max(fetchTicks(width, value), 192);
var wagTail = (step) => ["~", "-", "~", "^"][step % 4];
function activityGlyph(kind, now_ms) {
  switch (kind) {
    case "waiting":
      return "◷";
    case "tool":
      return "\uD83D\uDD27";
    case "thinking":
      return spinner(false, now_ms);
    case "compacting":
      return spinner(true, now_ms);
    case "napping":
      return "ᶻ";
    case "none":
      return "";
  }
}
function spinner(compacting, now_ms) {
  const list = compacting ? frames.pile : frames.thinking;
  return list[Math.floor(Math.max(0, now_ms) / (compacting ? 75 : 80)) % list.length];
}
function writeFetch(width, value, tick) {
  var _a, _b;
  const scene = fetchScene(width, value, tick), dog = [...scene.dog];
  let at = 0, out = "";
  for (let col = 0;col < width; col++) {
    const ball = ((_a = scene.ball) === null || _a === undefined ? undefined : _a.cell) === col ? scene.ball.dots : 0;
    if (col === width - 1)
      out += (ball ? "" : palette.fg("faint")) + String.fromCodePoint(10240 + (96 | ball)) + (ball ? "" : palette.fg("text"));
    else if (ball)
      out += String.fromCodePoint(10240 + ball);
    else if (col >= scene.x) {
      const glyph = (_b = dog[at++]) !== null && _b !== undefined ? _b : " ";
      out += glyph === "~" ? wagTail(Math.floor(tick / 4)) : glyph;
    } else
      out += " ";
  }
  return out;
}
var frame = (room, value) => [...value].slice(0, Math.max(0, room)).join("");
var bone_tick_ms = 40;
var bone_width = 16;
var bone_two_tries_width = 22;

class Bone {
  constructor(fields = {}) {
    this.tries = 1;
    this.seed = 0;
    Object.assign(this, fields);
  }
  static random(r) {
    return new Bone({ tries: r.boolean() ? 2 : 1, seed: r.next() });
  }
}

class Ground {
  constructor(room, random) {
    this.random = random;
    this.mounds = [];
    this.clods = [];
    this.dog = { x: 0, pose: "~ᐯ•ᴥ•ᐯ", wag: 0 };
    this.tick = 0;
    this.dust = 0;
    this.pile = Array(room * 2).fill(0);
  }
  pose(x, pose, wag = 0) {
    this.dog = { x, pose, wag };
  }
  bury(x, bone) {
    const find = {
      x,
      bone,
      glyphs: bone ? ["ε", "=", "з"] : [" ", "∘", " "],
      revealed: [null, null, null],
      eaten: 0,
      shown: true
    };
    const mound = { dot: 2 * x, heights: [1, 2, 3, 3, 2, 1], born: this.tick, find };
    this.mounds.push(mound);
    return mound;
  }
  dig(mound, from) {
    var _a;
    var _b;
    const i = mound.heights.findIndex((h) => h > 0);
    if (i < 0)
      return false;
    mound.heights[i]--;
    const r = this.random;
    this.clods.push({ x: from, y: 0.6, vx: -(0.45 + r.float() * 0.5), vy: 0.8 + r.float() * 0.5 });
    const cell = i >> 1;
    if (mound.heights[2 * cell] + mound.heights[2 * cell + 1] === 0)
      (_a = (_b = mound.find.revealed)[cell]) !== null && _a !== undefined || (_b[cell] = this.tick);
    return true;
  }
  step() {
    for (const clod of this.clods) {
      clod.x += clod.vx;
      clod.y += clod.vy;
      clod.vy -= 0.3;
    }
    this.clods = this.clods.filter((clod) => {
      if (clod.y > 0)
        return clod.x > -2;
      const at = Math.round(clod.x);
      if (at >= 0 && at < this.pile.length)
        this.settle(at);
      return false;
    });
  }
  settle(at) {
    const p = this.pile;
    for (;; ) {
      const height = p[at] + 1, left = at > 0 ? p[at - 1] : Infinity, right = at < p.length - 1 ? p[at + 1] : Infinity, low = Math.min(left, right);
      if (height <= 4 && height - low <= 1) {
        p[at] = height;
        return;
      }
      if (low >= p[at])
        return;
      at = left < right ? at - 1 : right < left ? at + 1 : this.random.boolean() ? at - 1 : at + 1;
    }
  }
}
function* beats(ground, x, list) {
  for (const [ticks, pose, wag] of list)
    for (let i = 0;i < ticks; i++) {
      ground.pose(x, pose, wag);
      yield;
    }
}
function* trot(ground, from, to) {
  for (let x = from;x <= to; x++)
    yield* beats(ground, x, [[2, gait_right[x % 4], 1]]);
}
function* digOut(ground, mound, x) {
  for (let k = 0;k % 2 !== 0 || ground.dig(mound, 2 * x - 1); k++) {
    ground.pose(x, k % 4 < 2 ? "~[\\/]o›" : "~[/\\]o›");
    yield;
  }
  yield* beats(ground, x, [[2, "~[||]o›"]]);
}
function* eat(ground, find) {
  const x = find.x - 8;
  yield* beats(ground, x, [
    [6, "~ᐱ•ᴥ•ᐱ", 2],
    [3, "~ᐯ•ω•ᐯ"],
    [2, "~ᐯ•ˑ•ᐯ"],
    [3, "~ᐯ•ω•ᐯ"],
    [3, "~ᐯ•ˑ•ᐯ"],
    [4, "~ᐯ◡ᴥ◡ᐯ", 2]
  ]);
  for (let k = 0;k < 24; k++) {
    ground.pose(x, k % 6 < 3 ? "~ᐯ◡ω◡ᐯ" : "~ᐯ◡ᴥ◡ᐯ", 1);
    find.eaten = Math.min(3, Math.floor((k + 2) / 6));
    ground.dust = Math.min(1, k / 40);
    yield;
  }
  find.shown = false;
  for (let at = x;at >= 0; at--)
    for (let i = 0;i < 2; i++) {
      ground.pose(at, walk_left[at % 4], 1);
      ground.dust = Math.min(1, ground.dust + 0.04);
      yield;
    }
  ground.dust = 1;
  yield* beats(ground, 0, [
    [3, "~ᐯ◡ᴥ◡ᐯ", 1],
    [3, "~ᐯ•ᴥ•ᐯ", 1]
  ]);
}
function* digUp(ground, tries) {
  const first = ground.bury(13, tries === 1);
  yield* beats(ground, 0, [
    [3, "~ᐯ•ᴥ•ᐯ"],
    [3, "~ᐯ•ω•ᐯ"],
    [2, "~ᐯ•ˑ•ᐯ"],
    [2, "~ᐯ•ω•ᐯ"],
    [4, "~ᐱ•ᴥ•ᐱ", 2]
  ]);
  yield* trot(ground, 0, 6);
  yield* digOut(ground, first, 6);
  if (tries === 1)
    return yield* eat(ground, first.find);
  yield* beats(ground, 6, [
    [9, "~ᐯ•ᴥ•ᐱ"],
    [3, "~ᐯ•ω•ᐯ"],
    [2, "~ᐯ•ˑ•ᐯ"]
  ]);
  const second = ground.bury(19, true);
  yield* beats(ground, 6, [
    [3, "~ᐯ•ω•ᐯ"],
    [4, "~ᐱ•ᴥ•ᐱ", 2]
  ]);
  yield* trot(ground, 6, 12);
  yield* digOut(ground, second, 12);
  yield* eat(ground, second.find);
}
var bone_runs = new Map;
function boneTicks(tries) {
  let ticks = bone_runs.get(tries);
  if (ticks === undefined) {
    const ground = new Ground(bone_two_tries_width, new Random), run = digUp(ground, tries);
    for (ticks = 0;!run.next().done; ticks++) {
      ground.tick = ticks + 1;
      ground.step();
    }
    bone_runs.set(tries, ticks);
  }
  return ticks;
}
function boneScene(room, value, tick) {
  const ground = new Ground(room, new Random(value.seed)), run = digUp(ground, room >= bone_two_tries_width ? value.tries : 1);
  for (let t = 0;t <= tick; t++) {
    ground.tick = t;
    run.next();
    ground.step();
  }
  return ground;
}
function writeBone(room, value, tick, background = palette.colors.bg) {
  if (room < bone_width) {
    const run = boneTicks(1), phase = Math.floor(Math.min(tick, run - 1) * 4 / run);
    return (room > 0 ? wagTail(Math.floor(tick / 4)) : "") + frame(room - 1, ["ᐯ•ω•ᐯ", "ᐯ•ᴥ•ᐱ", "ᐯ◡ω◡ᐯ", "ᐯ•ᴥ•ᐯ"][phase]);
  }
  const ground = boneScene(room, value, tick), text = palette.colors.text, cells = Array.from({ length: room }, () => ({ glyph: " ", color: text })), pile = Array(room).fill(0), mound = Array(room).fill(0), clods = Array(room).fill(0), risen = Array(room).fill(1);
  const unearthed = (age) => age < 2 ? dirt : age < 4 ? blend(dirt, text, 0.5) : text;
  const raise = (into, dot, height) => {
    for (let row = 0;row < Math.min(4, height); row++)
      into[dot >> 1] |= dots[dot & 1][row];
  };
  ground.pile.forEach((height, dot) => raise(pile, dot, height));
  for (const m of ground.mounds)
    m.heights.forEach((height, i) => {
      if (height === 0)
        return;
      raise(mound, m.dot + i, height);
      risen[m.dot + i >> 1] = Math.min(1, (ground.tick - m.born + 1) / 8);
    });
  for (const clod of ground.clods) {
    const dot = Math.round(clod.x);
    if (dot >= 0 && dot < 2 * room)
      clods[dot >> 1] |= dots[dot & 1][Math.max(0, Math.min(3, Math.round(clod.y)))];
  }
  const settled = 1 - ground.dust;
  for (let i = 0;i < room; i++) {
    const bits = pile[i] | mound[i] | clods[i];
    if (bits === 0)
      continue;
    const amount = mound[i] ? risen[i] * settled : pile[i] ? settled : 1;
    cells[i] = { glyph: String.fromCodePoint(10240 + bits), color: blend(background, dirt, amount) };
  }
  for (const { find } of ground.mounds) {
    if (!find.shown)
      continue;
    find.glyphs.slice(find.eaten).forEach((glyph, k) => {
      const at = find.revealed[find.eaten + k];
      if (glyph === " " || at === null)
        return;
      const age = ground.tick - at;
      cells[find.x + k] = {
        glyph,
        color: find.bone ? unearthed(age) : blend(background, age < 2 ? dirt : palette.colors.faint, settled)
      };
    });
  }
  const { x, pose, wag } = ground.dog;
  [...pose].forEach((glyph, j) => {
    if (x + j < 0 || x + j >= room)
      return;
    cells[x + j] = {
      glyph: glyph === "~" && wag ? wagTail(Math.floor(ground.tick / (wag === 2 ? 2 : 4))) : glyph,
      color: text
    };
  });
  let color = null;
  let out = "";
  for (const cell of cells) {
    if (cell.glyph !== " " && (color === null || cell.color.some((v, i) => v !== color[i]))) {
      color = cell.color;
      out += palette.fgRgb(color);
    }
    out += cell.glyph;
  }
  return out;
}
var fleas_tick_ms = 80;
var fleas_width = 18;
var fleas_ticks = 92;
var flea_dog = 6;
var flea_launch = 30;
var flea_returns = [55, 61, 52, 58];
var flea_hops = [
  [1, 8, 14, 3, 16],
  [6, 7, 16, 3, 18],
  [34, 8, 20, 3, 22],
  [28, 6, 22, 2, 20]
].map(([to, ticks, from, high, home], i) => [
  { start: flea_launch, ticks, from, to, high },
  { start: 41 + i, ticks: 3, from: to, to, high: 1 },
  { start: 46 + i * 3 % 4, ticks: 3, from: to, to, high: 1 },
  { start: flea_returns[i], ticks: 9, from: to, to: home, high: 3 }
]);
function hopAt(hops, tick) {
  let at = null;
  for (const hop of hops) {
    if (tick < hop.start)
      return at;
    const p = Math.min(1, (tick - hop.start) / hop.ticks);
    at = { x: Math.round(hop.from + (hop.to - hop.from) * p), y: Math.round(hop.high * 4 * p * (1 - p)) };
  }
  return at;
}
function fleasPose(tick) {
  if (flea_returns.some((r) => tick >= r + 9 && tick < r + 11))
    return "~ᐯ>ᴥ•ᐱ";
  if (tick < 4)
    return "~ᐯ•ᴥ•ᐯ";
  if (tick < 20)
    return tick % 2 ? "~ᐯ>ᴥ<ᐱ⸝" : "~ᐯ>ᴥ<ᐯ⸜";
  if (tick < 24)
    return "~ᐯ•ˑ•ᐯ";
  if (tick < 34)
    return tick % 2 ? "≈ᐱ-ᴥ-ᐱ≈" : "≋ᐯ-ᴥ-ᐯ≋";
  if (tick < 38)
    return "~ᐱ•ᴥ•ᐱ";
  if (tick < 52)
    return "~ᐯ◡ᴥ◡ᐯ";
  if (tick < 61)
    return "~ᐱ•ᴥ•ᐱ";
  if (tick < 72)
    return "~ᐯ•ᴥ•ᐯ";
  if (tick < 76)
    return "~ᐯ-ᴥ-ᐯ";
  return "~ᐯ•ˑ•ᐯ";
}
function fleasScene(tick) {
  const riding = (i) => {
    const shaking = tick >= 24 && tick < flea_launch;
    return { x: 26 + i + (shaking ? tick % 2 ? 1 : -1 : 0), y: [3, 1, 2, 0][(tick + i * 2) % 4] };
  };
  const fleas = flea_hops.map((hops, i) => tick < flea_launch ? tick < 4 || i > 1 ? null : riding(i) : hopAt(hops, tick));
  if (tick >= 78)
    fleas.push(riding(0));
  return fleas.filter((flea) => flea !== null);
}
function writeFleas(room, tick) {
  const pose = fleasPose(Math.min(tick, fleas_ticks - 1));
  if (room < fleas_width)
    return palette.fgRgb(palette.colors.text) + frame(room, pose);
  return drawFleas(room, pose, fleasScene(Math.min(tick, fleas_ticks - 1)));
}
function drawFleas(room, pose, fleas) {
  const cells = Array.from({ length: room }, () => " "), bits = Array(room).fill(0);
  [...pose].forEach((glyph, i) => cells[flea_dog + i] = glyph);
  for (const { x, y } of fleas)
    if (x >= 0 && x < 2 * room && cells[x >> 1] === " ")
      bits[x >> 1] |= dots[x & 1][Math.min(3, y)];
  const flea = palette.fgRgb(palette.colors.muted), dog = palette.fgRgb(palette.colors.text);
  let out = "", current = "";
  for (let i = 0;i < room; i++) {
    const glyph = bits[i] ? String.fromCodePoint(10240 + bits[i]) : cells[i], color = bits[i] ? flea : dog;
    if (glyph !== " " && color !== current)
      out += current = color;
    out += glyph;
  }
  return out;
}
var flea_cycle_ticks = 121;
var flea_asleep = 56;
var flea_stirs = 110;
var flea_one_eyed = 113;
var flea_back = [64, 72, 80, 88];
var cycle_hops = flea_hops.map((hops, i) => hops.map((hop, k) => k === 3 ? Object.assign(Object.assign({}, hop), { start: flea_back[i] }) : hop));
function cyclePose(tick) {
  if (tick < 50)
    return fleasPose(tick);
  if (tick < flea_asleep)
    return "~ᐯ-ᴥ-ᐯ";
  if (tick < flea_stirs)
    return "~ᐯ◡ᴥ◡ᐯ";
  if (tick < flea_one_eyed)
    return "~ᐯ-ᴥ•ᐯ";
  return tick % 2 ? "~ᐯ-ᴥ•ᐱ⸝" : "~ᐯ-ᴥ•ᐯ⸜";
}
function fleaCycleScene(tick) {
  if (tick >= flea_one_eyed)
    return fleasScene(4 + tick - flea_one_eyed);
  if (tick < 4)
    return fleasScene(4 + tick);
  if (tick < flea_launch)
    return fleasScene(tick);
  return cycle_hops.flatMap((hops) => {
    var _a;
    const back = hops[hops.length - 1];
    return tick < back.start + back.ticks ? (_a = hopAt(hops, tick)) !== null && _a !== undefined ? _a : [] : [];
  });
}
function writeFleaCycle(room, tick) {
  const t = tick % flea_cycle_ticks, pose = cyclePose(t);
  if (room < fleas_width)
    return palette.fgRgb(palette.colors.text) + frame(room, pose);
  return drawFleas(room, pose, fleaCycleScene(t));
}
var routines = {
  idle: { frame_ms: 75, bright: false },
  sniff: { frame_ms: 75, bright: false },
  fetch: { frame_ms: 30, bright: true },
  bone: { frame_ms: 30, bright: true }
};

class Playback {
  constructor() {
    this.active = false;
    this.routine = "idle";
    this.started_ms = 0;
    this.deadline_ms = 0;
    this.random = new Random;
    this.throw = new Throw;
    this.bone = new Bone;
  }
  static choose(roll) {
    for (const [routine, percent] of Playback.odds) {
      if (roll < percent)
        return routine;
      roll -= percent;
    }
    return "idle";
  }
  enter(routine, now) {
    this.routine = routine;
    this.started_ms = now;
    if (routine === "fetch")
      this.throw = Throw.random(this.random);
    if (routine === "bone")
      this.bone = Bone.random(this.random);
    this.deadline_ms = now + this.duration(routine);
  }
  duration(routine) {
    switch (routine) {
      case "idle":
        return Infinity;
      case "sniff":
        return (1 + this.random.int(2)) * frames.sniff.length * 200;
      case "fetch":
        return Playback.max_activity_ms;
      case "bone":
        return boneTicks(this.bone.tries) * bone_tick_ms;
    }
  }
  update(active, now) {
    const before = this.active;
    this.active = active;
    if (!active)
      return;
    if (!before) {
      this.enter(Playback.choose(this.random.float() * 100), now);
      return;
    }
    if (this.routine !== "idle" && now >= this.deadline_ms)
      this.enter("idle", now);
  }
  write(room, now, background = palette.colors.bg) {
    const elapsed = Math.max(0, now - this.started_ms);
    if (this.routine === "idle")
      return frame(room, frames.wag[Math.floor(elapsed / 200) % frames.wag.length]);
    if (this.routine === "sniff")
      return frame(room, frames.sniff[Math.floor(elapsed / 200) % frames.sniff.length]);
    if (this.routine === "bone")
      return writeBone(room, this.bone, Math.floor(elapsed / bone_tick_ms), background);
    if (room >= 18)
      return writeFetch(room, this.throw, Math.floor(Math.min(elapsed, 9599) * fetchPace(room, this.throw) / 9600));
    const phase = Math.floor(Math.min(elapsed, 9599) * 4 / 9600);
    return (room > 0 ? wagTail(Math.floor(elapsed / 300)) : "") + frame(room - 1, ["ᐯ•ᴥ•ᐯ", "ᐯ•ᴥ•ᐱ", "ᐯ•●•ᐯ", "ᐯ•ᴥ•ᐯ"][phase]);
  }
}
Playback.odds = [
  ["fetch", 5],
  ["bone", 5]
];
Playback.max_activity_ms = 9600;

class Fetch {
  constructor(min_room = 18) {
    this.min_room = min_room;
    this.thrown_ms = null;
    this.throw = new Throw;
  }
  throwBall(room, now) {
    if (room < this.min_room || this.tick(room, now) !== null)
      return;
    this.thrown_ms = now;
    this.throw = Throw.random(new Random(randomSeed()));
  }
  tick(room, now) {
    if (this.thrown_ms === null)
      return null;
    const elapsed = Math.max(0, now - this.thrown_ms);
    if (room < this.min_room || elapsed >= 9600)
      return null;
    const at = 16 + Math.floor(elapsed * fetchPace(room, this.throw) / 9600);
    return at < fetchTicks(room, this.throw) ? at : null;
  }
  write(room, now) {
    const at = this.tick(room, now);
    return palette.fg(at !== null ? "text" : "faint") + (at !== null ? writeFetch(room, this.throw, at) : frame(room, frames.wag[Math.floor(Math.max(0, now) / 200) % frames.wag.length]));
  }
}
function wordCells(word) {
  let start = 0;
  return Array.from(word).map((glyph) => {
    const width = displayWidth(glyph), cell = { glyph, width, start };
    start += width;
    return cell;
  });
}
function herdWidth() {
  return displayWidth(i18n.t`Compacting`) + 8;
}
var walk_left = ["‹o[/\\]~", "‹o[||]~", "‹o[\\/]~", "‹o[||]~"];
var curl = [
  { after: 2, pose: "ᐯ◡ᴥ◡ᐯ" },
  { after: 2, pose: "ᐯ◡ᴥ◡ᐯ" },
  { after: 3, pose: "◡ᴥ◡" },
  { after: 2, pose: "•ᴥ•" },
  { after: 1, pose: "•.•" },
  { after: 0, pose: "..." },
  { after: 0, pose: "…" }
];
function herdScene(width, step) {
  var _a;
  const word = wordCells(i18n.t`Compacting`), word_width = word.reduce((sum, cell) => sum + cell.width, 0), gap_pattern = [1, 2, 0, 2, 1, 0, 2, 1, 1], gaps = word.slice(1).map((_, i) => gap_pattern[i % gap_pattern.length]), gap_total = Math.max(1, gaps.reduce((sum, gap) => sum + gap, 0)), spread = [0];
  let sum = 0;
  for (const [i, gap] of gaps.entries()) {
    sum += gap;
    spread.push(word[i + 1].start + Math.floor(sum * (width - word_width - 1) / gap_total));
  }
  const roundup = width - word_width + 1;
  if (step < roundup) {
    const nose = width - step, letters = [...spread], last = word.length - 1;
    letters[last] = Math.min(spread[last], nose - word[last].width);
    for (let i = last;i > 0; i--)
      letters[i - 1] = Math.min(spread[i - 1], letters[i] - word[i - 1].width);
    return {
      word,
      letters,
      lit: letters.map((at, i) => at === word[i].start || at < spread[i]),
      dog: walk_left[step % 4],
      x: nose,
      finished: false
    };
  }
  const p = step - roundup, pose = p >= 10 ? curl[Math.min(p - 10, curl.length - 1)] : null;
  return {
    word,
    letters: word.map((cell) => cell.start),
    lit: Array(word.length).fill(true),
    dog: (_a = pose === null || pose === undefined ? undefined : pose.pose) !== null && _a !== undefined ? _a : p === 6 ? "~ᐯ◡ᴥ◡ᐯ" : "~ᐯ•ᴥ•ᐯ",
    x: pose ? word_width + pose.after : word_width + 1,
    finished: p >= 10 + curl.length - 1
  };
}
function writeHerd(width, step) {
  if (width < herdWidth())
    return palette.fg("text") + ellipsis(i18n.t`Compacting…`, width);
  const scene = herdScene(width, step), dog = [...scene.dog];
  let at = 0, letter = 0, out = "";
  let current = null;
  const tint = (color) => {
    if (color === current)
      return "";
    current = color;
    return palette.fg(color);
  };
  for (let col = 0;col < width; col++) {
    if (col >= scene.x && at < dog.length) {
      const glyph = dog[at++];
      out += tint(scene.finished ? "text" : "faint") + (glyph === "~" ? wagTail(Math.floor(step / 2)) : glyph);
    } else if (letter < scene.word.length && scene.letters[letter] === col) {
      const cell = scene.word[letter];
      out += tint(scene.lit[letter++] ? "text" : "faint") + cell.glyph;
      col += cell.width - 1;
    } else
      out += " ";
  }
  return out;
}
var farewell_tick_ms = 35;
var farewell_sit = 16;
var farewell_read = [
  [3, "‹o[||]~"],
  [14, "~ᐱ•ᴥ•ᐱ"],
  [10, "~ᐯ◡ᴥ◡ᐯ"]
];
var farewell_read_ticks = farewell_read.reduce((sum, [ticks]) => sum + ticks, 0);
var farewell_board_rows = 3;
var farewellHome = (width) => Math.max(0, Math.floor((width - 7) / 2));
function signpost(width) {
  const label = "← " + i18n.t`The Farm`, board = displayWidth(label) + 4, x = 2;
  return x + board <= farewellHome(width) ? { x, width: board, post: x + Math.floor(board / 2), label } : null;
}
function farewellScene(width, step, sign = signpost(width)) {
  const home = farewellHome(width), stop = sign ? sign.post + 2 : home;
  let p = step;
  const stage = (ticks) => {
    if (p < ticks)
      return true;
    p -= ticks;
    return false;
  };
  if (stage(farewell_sit))
    return { dog: p === 9 ? "~ᐯ◡ᴥ◡ᐯ" : "~ᐯ•ᴥ•ᐯ", x: home };
  if (stage(home - stop))
    return { dog: walk_left[p % 4], x: home - p };
  if (sign) {
    for (const [ticks, pose] of farewell_read)
      if (stage(ticks))
        return { dog: pose, x: stop };
  }
  return { dog: walk_left[p % 4], x: stop - p };
}
function farewellTicks(width, sign = signpost(width)) {
  return farewell_sit + farewellHome(width) + (sign ? farewell_read_ticks : 0) + walk_left[0].length + 1;
}
function writeFarewell(width, step, sign = signpost(width)) {
  const scene = farewellScene(width, step, sign), dog = [...scene.dog], wood = palette.fg("muted"), text = palette.fg("text");
  let ground = "", color = "";
  for (let col = 0;col < width; col++) {
    const glyph = dog[col - scene.x], [paint, cell] = glyph !== undefined ? [text, glyph === "~" ? wagTail(Math.floor(step / 2)) : glyph] : col === (sign === null || sign === undefined ? undefined : sign.post) ? [wood, "│"] : [color, " "];
    if (paint !== color)
      ground += color = paint;
    ground += cell;
  }
  if (!sign)
    return [ground];
  const left = " ".repeat(sign.x), right = " ".repeat(width - sign.x - sign.width), inner = sign.width - 2, post = sign.post - sign.x - 1;
  return [
    left + wood + "╭" + "─".repeat(inner) + "╮" + right,
    left + wood + "│ " + text + sign.label + wood + " │" + right,
    left + wood + "╰" + "─".repeat(post) + "┬" + "─".repeat(inner - post - 1) + "╯" + right,
    ground
  ];
}

class Farewell {
  constructor(width, height) {
    this.width = width;
    this.height = height;
    this.sign = height >= 3 + farewell_board_rows ? signpost(width) : null;
    this.top = Math.max(1, Math.floor((height - (this.sign ? 3 + farewell_board_rows : 3)) / 2) + 1);
    this.ticks = farewellTicks(width, this.sign);
  }
  rows(step) {
    const caption = ellipsis(i18n.t`Corgi was uninstalled.`, this.width), pad = Math.max(0, Math.floor((this.width - displayWidth(caption)) / 2)), rest = Math.max(0, this.width - pad - displayWidth(caption));
    return [
      palette.fg("text") + " ".repeat(pad) + caption + " ".repeat(rest),
      " ".repeat(this.width),
      ...writeFarewell(this.width, step, this.sign)
    ];
  }
}
var Dig = {
  lead: 17,
  word: (dig) => dig === "restoring" ? i18n.t`Restoring…` : i18n.t`Forking…`,
  wordWidth: (dig) => displayWidth(Dig.word(dig)),
  width: (dig) => Dig.lead + Dig.wordWidth(dig)
};
var Asleep = {
  get word() {
    return i18n.t`Hibernated`;
  },
  get wordWidth() {
    return displayWidth(Asleep.word);
  },
  get width() {
    return Dig.lead + Asleep.wordWidth;
  }
};
function writeAsleep(width) {
  const word = "\x1B[1m" + palette.fg("accent") + ellipsis(Asleep.word, width);
  if (width < Asleep.width)
    return word;
  return " ".repeat(7) + palette.fg("muted") + "~ᐯ◡ᴥ◡ᐯ " + palette.fg("faint") + "ᶻz " + word;
}
var blend = (from, to, amount) => from.map((v, i) => Math.round(v + (to[i] - v) * amount));
var dirt = [150, 126, 96];
var buried = ["⣶", "⣿", "⣷", "⣾", "⣿", "⣶", "⣷", "⣿", "⣾", "⣶"];
var pile2 = [" ", "⣀", "⣤", "⣶", "⣿"];
var clods = ["⠄", "⠂", "⠁", "⠁", "⠂"];
function writeUnearth(width, shown_ms, dig) {
  const label = Dig.word(dig), word = wordCells(label), restored = palette.colors.accent;
  if (width < Dig.width(dig))
    return "\x1B[1m" + palette.fg("accent") + ellipsis(label, width);
  const step = Math.floor(Math.max(0, shown_ms) / 80), cells = Array.from({ length: Dig.width(dig) }, () => ({
    glyph: " ",
    color: dirt,
    bold: false
  })), heights = [0, 0, 0, 0];
  for (const [i, letter] of word.entries()) {
    const age = step - i * 2;
    for (let col = 0;col < letter.width; col++)
      cells[Dig.lead + letter.start + col] = age < 0 ? { glyph: buried[(letter.start + col) % buried.length], color: dirt, bold: false } : age < 2 ? { glyph: age === 0 ? "⣤" : "⠤", color: dirt, bold: false } : {
        glyph: col === 0 ? letter.glyph : "",
        color: age === 2 ? dirt : age === 3 ? blend(dirt, restored, 0.5) : restored,
        bold: true
      };
    if (age < 0)
      continue;
    if (age < 5)
      cells[8 - age] = { glyph: clods[age], color: dirt, bold: false };
    else {
      const column = [1, 0, 3, 2][i % 4];
      heights[column] = Math.min(heights[column] + 1, 4);
    }
  }
  for (const [i, h] of heights.entries())
    cells[i].glyph = pile2[h];
  const dug = word.length * 2 + 2;
  let col = 9;
  let dog;
  if (step < dug)
    dog = step % 2 ? "~[/\\]o›" : "~[\\/]o›";
  else {
    col++;
    cells[15] = {
      glyph: wagTail(Math.floor(step / 2)),
      color: palette.colors.faint,
      bold: false
    };
    dog = step - dug < 5 ? "ᐱ•ᴥ•ᐱ" : "ᐯ•ᴥ•ᐯ";
  }
  for (const glyph of dog)
    cells[col++] = { glyph, color: palette.colors.faint, bold: false };
  let bold = null;
  let color = null;
  let out = "";
  for (const cell of cells) {
    if (bold !== cell.bold) {
      bold = cell.bold;
      out += bold ? "\x1B[1m" : "\x1B[22m";
    }
    if (color === null || color.some((v, i) => v !== cell.color[i])) {
      color = cell.color;
      out += palette.fgRgb(color);
    }
    out += cell.glyph;
  }
  return out;
}

class Sleep {
  constructor(fields = {}) {
    this.background = palette.colors.bg;
    this.intensity = 50;
    this.bright = false;
    this.selected = false;
    this.puff_ms = null;
    Object.assign(this, fields);
  }
}
var puff_duration_ms = 4500;
var dream_period_ms = 11000;
function pick(sleepers, period, skip) {
  let best = null, bestScore = 0;
  for (const key of sleepers) {
    if (key === skip)
      continue;
    const score = mix((hash(key) ^ mix(period + golden >>> 0)) >>> 0);
    if (best === null || score > bestScore) {
      best = key;
      bestScore = score;
    }
  }
  return best;
}
function dreamer(sleepers, now_ms) {
  const keys = sleepers, now = Math.max(0, now_ms), period = Math.floor(now / 11000), elapsed = now % 11000;
  if (elapsed >= 4500)
    return null;
  const previous = period > 0 && keys.length > 1 ? pick(keys, period - 1, null) : null, key = pick(keys, period, previous);
  return key === null ? null : { key, puff_ms: elapsed };
}
function puffAmount(puff_ms, col) {
  if (puff_ms === null || puff_ms >= 4500 || col < 7)
    return null;
  const step = Math.floor(puff_ms / 900), t = Math.floor(puff_ms % 900 / 150) / 6, shift = t * t * (3 - 2 * t), amount = col - 7 === step ? (1 - shift) * (1 - step / 5) : col - 7 === step + 1 ? shift * (1 - (step + 1) / 5) : 0;
  return amount > 0 ? amount : null;
}
function idle(width, sleep = {}) {
  const s = new Sleep(sleep);
  if (s.intensity === 0)
    return " ".repeat(width);
  const grey = intensityColor(s.background, s.intensity, s.selected ? palette.colors.muted : palette.colors.faint), body = s.bright || s.selected ? grey : blend(s.background, grey, 0.42), sprite = [...frames.asleep];
  let out = palette.fgRgb(body);
  for (let col = 0;col < width; col++) {
    if (col < 6)
      out += sprite[col];
    else {
      const amount = puffAmount(s.puff_ms, col);
      out += amount !== null ? palette.fgRgb(blend(s.background, grey, amount)) + ((col - 7) % 2 === 0 ? "ᶻ" : "z") + palette.fgRgb(body) : " ";
    }
  }
  return out;
}
function intensityColor(background, intensity, normal = palette.colors.faint) {
  return intensity <= 50 ? blend(background, normal, intensity / 50) : blend(normal, palette.colors.text, (intensity - 50) / 50);
}
function writeWag(room, now, intensity, background = palette.colors.bg) {
  if (intensity === 0)
    return " ".repeat(room);
  return palette.fgRgb(intensityColor(background, intensity)) + frame(room, frames.wag[Math.floor(Math.max(0, now) / 200) % frames.wag.length]);
}

class Presentation {
  constructor() {
    this.playback = new Playback;
    this.mode = "content";
    this.last_corgi = null;
    this.reveal_started_ms = null;
    this.herd_started_ms = 0;
  }
  update(mode, now, herd_started_ms) {
    this.playback.update(mode === "awake", now);
    if (mode === "herding") {
      if (herd_started_ms !== undefined || this.mode !== "herding")
        this.herd_started_ms = herd_started_ms !== null && herd_started_ms !== undefined ? herd_started_ms : now;
      this.last_corgi = null;
      this.reveal_started_ms = null;
    } else if (mode !== "content") {
      this.last_corgi = mode;
      this.reveal_started_ms = null;
    } else if (this.mode === "asleep") {
      this.last_corgi = null;
      this.reveal_started_ms = null;
    } else if (this.mode === "awake" && this.last_corgi)
      this.reveal_started_ms = now;
    if (this.reveal_started_ms !== null && now - this.reveal_started_ms >= 450) {
      this.reveal_started_ms = null;
      this.last_corgi = null;
    }
    this.mode = mode;
  }
  skipReveal() {
    if (this.mode === "content") {
      this.reveal_started_ms = null;
      this.last_corgi = null;
    }
  }
  frameDelay() {
    if (this.reveal_started_ms !== null)
      return 30;
    return this.mode === "awake" ? routines[this.playback.routine].frame_ms : 75;
  }
  revealPosition(room, now) {
    return this.reveal_started_ms === null ? room + 3 : (room + 3) * Math.max(0, Math.min(450, now - this.reveal_started_ms)) / 450;
  }
  revealedColumns(room, now) {
    return Math.min(room, Math.floor(this.revealPosition(room, now)));
  }
  writeHerding(room, now) {
    return writeHerd(room, this.herdStep(now));
  }
  herded(room, now) {
    return room < herdWidth() || herdScene(room, this.herdStep(now)).finished;
  }
  herdStep(now) {
    return Math.floor(Math.max(0, now - this.herd_started_ms) / 110);
  }
  writeCorgi(room, now, working, sleep) {
    const pose = this.last_corgi;
    if (!pose || sleep.intensity === 0)
      return "";
    if (pose === "asleep" && !working)
      return idle(room, sleep);
    const playback = pose === "asleep" ? new Playback : this.playback;
    const color = routines[playback.routine].bright ? palette.colors.text : intensityColor(sleep.background, sleep.intensity);
    return palette.fgRgb(color) + playback.write(room, now, sleep.background);
  }
  hide() {
    this.playback.active = false;
    this.mode = "content";
    this.last_corgi = null;
    this.reveal_started_ms = null;
  }
}
Presentation.reveal_feather = 3;
var slots = Array.from({ length: 256 }, () => ({
  key: null,
  seen: false,
  presentation: new Presentation
}));
var frame_delay = 75;
function beginFrame() {
  for (const slot of slots)
    slot.seen = false;
}
function endFrame() {
  frame_delay = 75;
  for (const slot of slots) {
    if (slot.seen)
      frame_delay = Math.min(frame_delay, slot.presentation.frameDelay());
    else
      slot.presentation.hide();
  }
}
function frameDelay() {
  return frame_delay;
}
function observe(key, mode, now, herd_started_ms) {
  const id = key;
  let slot = slots.find((s) => s.key === id);
  if (!slot) {
    if (mode === "content")
      return null;
    slot = slots.find((s) => !s.seen && !s.presentation.last_corgi);
    if (!slot)
      throw Error("AnimationCapacity");
    slot.key = id;
    slot.presentation = new Presentation;
    slot.presentation.playback.random = new Random(randomSeed());
  }
  slot.seen = true;
  slot.presentation.update(mode, now, herd_started_ms);
  return slot.presentation;
}
export {
  Asleep,
  Ball,
  Bone,
  Dig,
  Farewell,
  Fetch,
  Playback,
  Presentation,
  Random,
  Sleep,
  Throw,
  activityGlyph,
  beginFrame,
  boneScene,
  boneTicks,
  bone_tick_ms,
  bone_two_tries_width,
  bone_width,
  buried,
  chase,
  clods,
  curl,
  dirt,
  dream_period_ms,
  dreamer,
  endFrame,
  farewellScene,
  farewellTicks,
  farewell_board_rows,
  farewell_tick_ms,
  fetchScene,
  fetchTicks,
  fleaCycleScene,
  flea_cycle_ticks,
  fleasScene,
  fleas_tick_ms,
  fleas_ticks,
  fleas_width,
  frameDelay,
  herdScene,
  herdWidth,
  idle,
  intensityColor,
  observe,
  pick,
  pile2 as pile,
  puffAmount,
  puff_duration_ms,
  signpost,
  spinner,
  wagTail,
  walk_left,
  writeAsleep,
  writeBone,
  writeFarewell,
  writeFetch,
  writeFleaCycle,
  writeFleas,
  writeHerd,
  writeUnearth,
  writeWag
};
