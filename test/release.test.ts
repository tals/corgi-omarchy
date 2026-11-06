import { afterEach, beforeEach, expect, spyOn, test } from "bun:test";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import * as release from "../tools/release-plugin.ts";

const trials: string[] = [];
let logging: ReturnType<typeof spyOn>;
beforeEach(() => {
  logging = spyOn(console, "log").mockImplementation(() => {});
});
afterEach(async () => {
  logging.mockRestore();
  await Promise.all(trials.splice(0).map(p => rm(p, { recursive: true, force: true })));
});
const git = (cwd: string, ...args: string[]) => release.run(cwd, ["git", ...args]);
const script = (n: number, base = "https://example.invalid") =>
  `#!/bin/sh\nbase='${base}'\nversion='20261105T12000${n}Z-aaaaaaaaaaaa'\nexpected='${String(n).repeat(64)}' size=${n + 1}\n`;

async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), "plugin release ' $ "));
  trials.push(dir);
  const checkout = join(dir, "plugin"),
    remote = join(dir, "remote"),
    source = join(dir, "corgi");
  await mkdir(checkout);
  await mkdir(source);
  await mkdir(remote);
  await git(remote, "init", "-q", "--bare", "--initial-branch=main");
  await git(checkout, "init", "-q", "--initial-branch=main");
  await git(checkout, "config", "user.name", "Test");
  await git(checkout, "config", "user.email", "test@example.invalid");
  await mkdir(join(checkout, "tools"));
  await mkdir(join(checkout, "test"));
  await mkdir(join(checkout, "qml-000000000000/corgi"), { recursive: true });
  await writeFile(join(checkout, "qml-000000000000/Widget.qml"), "import QtQuick\nItem {}\n");
  await writeFile(join(checkout, "qml-000000000000/corgi/motion.mjs"), "export const frame = 1;\n");
  await writeFile(join(source, "animation"), "export const frame = 1;\n");
  await writeFile(
    join(checkout, "tools/motion-build.ts"),
    `import { join } from 'node:path';\nconst [source, entry, out] = process.argv.slice(2);\nawait Bun.write(join(out, 'motion.mjs'), await Bun.file(join(source, 'animation')).text());\n`,
  );
  await writeFile(join(checkout, "tools/rehash"), await Bun.file(join(import.meta.dir, "../tools/rehash")).text());
  await writeFile(
    join(checkout, "test/check.test.ts"),
    "import {test,expect} from 'bun:test'; test('fixture',()=>expect(true).toBe(true));\n",
  );
  await writeFile(
    join(checkout, "manifest.json"),
    JSON.stringify({
      entryPoints: { barWidget: "qml-000000000000/Widget.qml" },
    }),
  );
  await writeFile(join(checkout, "install.sh"), script(0));
  await chmod(join(checkout, "install.sh"), 0o755);
  await release.run(checkout, ["bash", "tools/rehash"]);
  await git(checkout, "add", ".");
  await git(checkout, "commit", "-qm", "initial");
  await git(checkout, "push", "-q", remote, "main");
  return {
    dir,
    checkout,
    remote,
    source,
    head: await git(checkout, "rev-parse", "HEAD"),
  };
}

test("binary-only Corgi releases retain the pin and don't push the plugin", async () => {
  const f = await fixture();
  const state = await release.prepare(f.checkout, f.source, script(1), false, f.remote);
  expect(state.commit).toBe(f.head);
  await release.publish(f.checkout);
  expect(await git(f.remote, "rev-parse", "main")).toBe(f.head);
  expect(await readFile(join(f.checkout, "install.sh"), "utf8")).toBe(script(0));
});

test("animation changes advance the pin; publishing can be retried without another commit", async () => {
  const f = await fixture();
  await writeFile(join(f.source, "animation"), "export const frame = 2;\n");
  const state = await release.prepare(f.checkout, f.source, script(1), false, f.remote);
  expect(state.commit).not.toBe(f.head);
  await release.publish(f.checkout);
  await release.publish(f.checkout);
  expect(await git(f.remote, "rev-parse", "main")).toBe(state.commit);
  expect(await readFile(join(f.checkout, "install.sh"), "utf8")).toBe(script(1));
});

test("a test release advances its own pin and branch; a failed mirror can be retried", async () => {
  const f = await fixture();
  const first = await release.prepare(f.checkout, f.source, script(1, "https://example.invalid/test"), true, f.remote);
  await expect(
    release.publish(f.checkout, async () => {
      throw Error("bucket offline");
    }),
  ).rejects.toThrow("bucket offline");
  expect(await git(f.remote, "rev-parse", "main")).toBe(f.head);
  expect(await git(f.remote, "rev-parse", "test")).toBe(first.commit);
  await release.publish(f.checkout, async () => {});
  const same = await release.prepare(f.checkout, f.source, script(1, "https://example.invalid/test"), true, f.remote);
  expect(same.commit).toBe(first.commit);
  const second = await release.prepare(f.checkout, f.source, script(2, "https://example.invalid/test"), true, f.remote);
  expect(second.commit).not.toBe(first.commit);
  await release.publish(f.checkout, async () => {});
  expect(await git(f.remote, "rev-parse", "test")).toBe(second.commit);
  expect(await git(f.remote, "rev-parse", "main")).toBe(f.head);
});

test("an independently advanced main is not overwritten", async () => {
  const f = await fixture();
  await release.prepare(f.checkout, f.source, script(1) + "echo changed\n", false, f.remote);
  const other = join(f.dir, "other");
  await release.run(f.dir, ["git", "clone", "-q", f.remote, other]);
  await writeFile(join(other, "README.md"), "another change\n");
  await git(other, "add", ".");
  await git(other, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "other");
  await git(other, "push", "-q", "origin", "main");
  await expect(release.publish(f.checkout)).rejects.toThrow("Command failed");
  expect(await git(f.remote, "rev-parse", "main")).toBe(await git(other, "rev-parse", "HEAD"));
});

test("a stale source selection cannot undo a pin update on main", async () => {
  const f = await fixture();
  const other = join(f.dir, "other");
  await release.run(f.dir, ["git", "clone", "-q", f.remote, other]);
  await writeFile(join(other, "install.sh"), script(2));
  await git(other, "add", ".");
  await git(other, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "new pin");
  await git(other, "push", "-q", "origin", "main");
  await expect(release.prepare(f.checkout, f.source, script(1), false, f.remote)).rejects.toThrow("Command failed");
  expect(await readFile(join(f.checkout, "install.sh"), "utf8")).toBe(script(0));
  expect(await git(f.remote, "show", "main:install.sh")).toBe(script(2).trim());
});

test("test repositories support real HTTP clone and update, with objects uploaded before refs", async () => {
  const f = await fixture();
  const published = new Map<string, Uint8Array>(),
    writes: string[] = [];
  const put = async (path: string, bytes: Uint8Array) => {
    writes.push(path);
    published.set(path, bytes);
  };
  await release.mirror(f.checkout, f.head, put);
  expect(writes.indexOf("info/refs")).toBeGreaterThan(writes.findLastIndex(p => p.startsWith("objects/")));
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request) {
      const key = new URL(request.url).pathname.slice(1),
        bytes = published.get(key);
      return bytes ? new Response(bytes) : new Response("missing", { status: 404 });
    },
  });
  try {
    const clone = join(f.dir, "http-clone");
    await release.run(f.dir, ["git", "clone", "-q", `http://127.0.0.1:${server.port}`, clone]);
    expect(await git(clone, "rev-parse", "HEAD")).toBe(f.head);
    await writeFile(join(f.checkout, "README.md"), "second\n");
    await git(f.checkout, "add", ".");
    await git(f.checkout, "commit", "-qm", "second");
    const second = await git(f.checkout, "rev-parse", "HEAD");
    await release.mirror(f.checkout, second, put);
    await git(clone, "pull", "--ff-only");
    expect(await git(clone, "rev-parse", "HEAD")).toBe(second);
  } finally {
    server.stop(true);
  }
});

test("release flags reject ambiguity and installer code retains channel and behavior changes", () => {
  expect(release.options(["--test"])).toMatchObject({ test: true });
  expect(() => release.options(["--test", "--test"])).toThrow();
  expect(() => release.options(["--unknown"])).toThrow();
  expect(release.installerCode(script(0))).toBe(release.installerCode(script(1)));
  expect(release.installerCode(script(0))).not.toBe(release.installerCode(script(1, "https://example.invalid/test")));
});
