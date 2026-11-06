import { expect, test } from "bun:test";
import { dirname, join } from "node:path";
import manifest from "../manifest.json";

const { display } = await import(join(import.meta.dir, "..", dirname(manifest.entryPoints.barWidget), "usage.mjs"));
const day = 86400;
const start = Date.UTC(2026, 10, 1) / 1000;
const now = start + 10 * day;
const weekly = { minutes: 10080, used: 86, reset_at: now + 3 * day };
const short = { minutes: 300, used: 42, reset_at: now + 2 * 3600 };
const account = {
  provider: "codex",
  limits: { windows: [short, weekly] },
  history: [
    [10, 20],
    [20, 15, null, 80],
  ],
  usage_fetched_at: now,
};

test("raw limits keep their histories when the weekly window moves first", () => {
  const result = display(account, now);
  expect(result.windows.map(w => w.label)).toEqual(["7d", "5h"]);
  expect(result.windows[0].bars.slice(0, 4).map(b => b.used)).toEqual([20, 20, null, 80]);
  expect(result.windows[1].bars.slice(0, 2).map(b => b.used)).toEqual([10, 20]);
  expect(result.windows[0].bars[7]).toEqual({ used: 86, tone: "warm" });
  expect(result.windows[0].bars[8]).toEqual({ used: null, tone: "remaining" });
  expect(result.windows[1].reset).toBe("2h");
  expect(account.history[1][1]).toBe(15);
});

test("a lone short limit stays in the second column and stale data stays gray", () => {
  const result = display({ ...account, limits: { windows: [short, null] }, usage_fetched_at: now - 1200 }, now);
  expect(result.windows[0]).toBeNull();
  expect(result.windows[1].bars[0]).toEqual({ used: 10, tone: "stale" });
  expect(result.windows[1].bars[8]).toEqual({ used: null, tone: "unread" });
});

const spend = {
  used_minor: 155000,
  limit_minor: 250000,
  currency: null,
  exponent: 0,
  period_start: start,
  reset_at: start + 30 * day,
};
test("monthly spend uses raw UTC day timestamps and excludes other billing periods", () => {
  const result = display(
    {
      limits: "metered",
      spend,
      usage_fetched_at: now,
      spend_history: [
        { day: start - day, period_start: start - 30 * day, used_minor: 999999 },
        { day: start, period_start: start, used_minor: 25000 },
        { day: start + 3 * day, period_start: start, used_minor: 50000 },
      ],
    },
    now,
  );
  expect(result.metered).toBe(true);
  expect(result.amount).toBe("⛁155k / ⛁250k");
  expect(result.windows[0].figure).toBe("62%");
  expect(result.windows[0].bars.map(b => b.used)).toEqual([10, 20, 20, 20, 62, ...Array(9).fill(null)]);
  expect(result.windows[1]).toBeNull();
});

test("unlimited spend shows money without a percentage; expired months disappear", () => {
  const a = {
    limits: "metered",
    spend: { ...spend, used_minor: 820, limit_minor: null, currency: "USD", exponent: 2 },
    usage_fetched_at: now,
  };
  const result = display(a, now);
  expect(result.amount).toBe("$8.20");
  expect(result.windows[0].used).toBeNull();
  expect(result.windows[0].figure).toBe("");
  expect(display(a, spend.reset_at).windows).toEqual([null, null]);
});

test("the pinned Corgi's display format remains supported", () => {
  const legacy = { windows: [{ label: "7d", bars: [] }, null], amount: "" };
  expect(display(legacy, now)).toBe(legacy);
});

test("missing or invalid readings leave no display groups", () => {
  for (const a of [
    {},
    { limits: "none" },
    { limits: { windows: [7, { used: "lots" }] } },
    { limits: "metered", spend: { ...spend, exponent: 1000 } },
  ])
    expect(display(a, now).windows).toEqual([null, null]);
});
