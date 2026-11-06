// Turns Corgi's raw usage readings into the panel's two display slots.
// Keep this module compatible with Qt's ES2016 engine (no Intl).
const count = 14;
const day = 86400;
const number = value => typeof value === "number" && isFinite(value);
const amount = value => number(value) && value >= 0;
const percent = value => Math.max(0, Math.min(100, value));
const tone = used => (used >= 100 ? "hot" : used >= 80 ? "warm" : "accent");
const empty = kind => ({ used: null, tone: kind });

function countdown(at, now) {
  if (!number(at)) return "unknown";
  if (at <= now) return "now";
  const minutes = Math.ceil((at - now) / 60);
  const days = Math.floor(minutes / 1440),
    hours = Math.floor(minutes / 60) % 24,
    mins = minutes % 60;
  if (days) return days + "d" + (hours ? " " + hours + "h" : mins ? " " + mins + "m" : "");
  return hours ? hours + "h" + (mins ? " " + mins + "m" : "") : mins + "m";
}

function window(raw, history, fresh, now) {
  if (!raw || typeof raw !== "object" || !amount(raw.used)) return null;
  const minutes = raw.minutes,
    reset = raw.reset_at;
  const span = amount(minutes) ? minutes * 60 : 0;
  const elapsed =
    span > 0 && number(reset) ? Math.ceil((percent(((now - reset + span) * 100) / span) * count) / 100) : 0;
  const readings = Array.isArray(history) ? history : [];
  let top = 0;
  const bars = Array.from({ length: count }, (_, i) => {
    if (i >= elapsed) return empty("remaining");
    let used = amount(readings[i]) ? readings[i] : null;
    if (fresh && i + 1 === elapsed) used = Math.max(used || 0, raw.used);
    if (used === null) return empty("unread");
    top = Math.max(top, percent(used));
    return { used: top, tone: fresh ? tone(top) : "stale" };
  });
  const label = !span
    ? "Window"
    : minutes % 1440 === 0
      ? minutes / 1440 + "d"
      : minutes % 60 === 0
        ? minutes / 60 + "h"
        : minutes + "m";
  return { label, bars, used: raw.used, figure: raw.used + "%", reset: countdown(reset, now) };
}

function money(reading, minor) {
  const major = minor / Math.pow(10, reading.exponent);
  const unit = major >= 1e9 ? [1e9, "B"] : major >= 1e6 ? [1e6, "M"] : major >= 1000 ? [1000, "k"] : null;
  const figure = unit
    ? Math.round((major / unit[0]) * 10) / 10 + unit[1]
    : major.toFixed(reading.currency === null || Number.isInteger(major) ? 0 : reading.exponent);
  const symbols = { USD: "$", EUR: "€", GBP: "£", JPY: "¥" };
  return (reading.currency === null ? "⛁" : symbols[reading.currency] || reading.currency + " ") + figure;
}

function month(reading, history, fresh, now) {
  if (
    !reading ||
    !amount(reading.used_minor) ||
    !(reading.limit_minor === null || amount(reading.limit_minor)) ||
    !number(reading.period_start) ||
    !number(reading.reset_at) ||
    reading.reset_at <= reading.period_start ||
    now < reading.period_start ||
    now >= reading.reset_at ||
    !Number.isInteger(reading.exponent) ||
    reading.exponent < 0 ||
    reading.exponent > 6 ||
    !(reading.currency === null || (typeof reading.currency === "string" && /^[A-Z]{3}$/.test(reading.currency)))
  )
    return null;
  const span = reading.reset_at - reading.period_start;
  const samples = (Array.isArray(history) ? history : []).filter(
    s =>
      s &&
      number(s.day) &&
      s.period_start === reading.period_start &&
      amount(s.used_minor) &&
      s.day >= Math.floor(reading.period_start / day) * day &&
      s.day <= now,
  );
  const top =
    reading.limit_minor === null
      ? Math.max(reading.used_minor, ...samples.map(s => s.used_minor))
      : reading.limit_minor;
  const height = minor => percent(top > 0 ? (minor * 100) / top : minor > 0 ? 100 : 0);
  const elapsed = Math.ceil(((now - reading.period_start) * count) / span);
  let peak = 0;
  const bars = Array.from({ length: count }, (_, i) => {
    if (i >= elapsed) return empty("remaining");
    const end = reading.period_start + ((i + 1) * span) / count;
    const covered = samples.filter(s => s.day + day <= end);
    let minor = covered.length ? Math.max(...covered.map(s => s.used_minor)) : null;
    if (fresh && i + 1 === elapsed) minor = Math.max(minor || 0, reading.used_minor);
    if (minor === null) return empty("unread");
    peak = Math.max(peak, height(minor));
    return { used: peak, tone: !fresh ? "stale" : reading.limit_minor === null ? "accent" : tone(peak) };
  });
  const used =
    reading.limit_minor === null
      ? null
      : reading.limit_minor > 0
        ? (reading.used_minor * 100) / reading.limit_minor
        : reading.used_minor > 0
          ? 100
          : 0;
  return {
    window: {
      label: "mo",
      bars,
      used,
      figure: used === null ? "" : used > 0 && used < 1 ? "<1%" : Math.floor(used) + "%",
      reset: countdown(reading.reset_at, now),
    },
    amount:
      money(reading, reading.used_minor) +
      (reading.limit_minor === null ? "" : " / " + money(reading, reading.limit_minor)),
  };
}

export function display(account, now) {
  // The pinned installer can still start a Corgi that sends display slots.
  if (!account || typeof account !== "object" || Array.isArray(account.windows)) return account;
  const fresh =
    number(account.usage_fetched_at) && account.usage_fetched_at > 0 && now - account.usage_fetched_at < 1200;
  const limits = account.limits;
  const raw = limits && Array.isArray(limits.windows) ? limits.windows.slice(0, 2) : [];
  const history = Array.isArray(account.history) ? account.history : [];
  const pairs = raw.map((w, i) => ({ raw: w, view: window(w, history[i], fresh, now) })).filter(w => w.view !== null);
  const short = w => amount(w.raw.minutes) && w.raw.minutes > 0 && w.raw.minutes < 1440;
  let windows = [null, null],
    total = "";
  if (pairs.length === 2) {
    if (short(pairs[0]) && !short(pairs[1])) pairs.reverse();
    windows = pairs.map(w => w.view);
  } else if (pairs.length === 1) windows[short(pairs[0]) ? 1 : 0] = pairs[0].view;
  const metered = limits === "metered" || !!(limits && limits.metered);
  if (!pairs.length && metered) {
    const spend = month(account.spend, account.spend_history, fresh, now);
    if (spend) {
      windows[0] = spend.window;
      total = spend.amount;
    }
  }
  return Object.assign({}, account, { windows, metered, amount: total });
}
