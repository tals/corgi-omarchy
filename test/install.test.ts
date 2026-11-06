import { afterEach, expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import manifest from "../manifest.json";

const script = join(import.meta.dir, "..", dirname(manifest.entryPoints.barWidget), "open_installer.sh");
const trials: string[] = [];
afterEach(async () => {
  await Promise.all(trials.splice(0).map(path => rm(path, { recursive: true, force: true })));
});

async function fixture() {
  const trialHome = await mkdtemp(join(tmpdir(), "corgi-plugin-install-"));
  trials.push(trialHome);
  const plugin = join(trialHome, "plugin 'with spaces' $literal"),
    bin = join(trialHome, "bin"),
    log = join(trialHome, "launches");
  async function checkout() {
    await mkdir(plugin);
    await writeFile(join(plugin, "manifest.json"), "{}");
    await writeFile(join(plugin, "install.sh"), "#!/bin/sh\n");
  }
  await checkout();
  await mkdir(bin);
  const launcher = join(bin, "omarchy-launch-terminal");
  await writeFile(
    launcher,
    '#!/bin/bash\nprintf "%s\\0" "$@" >> "$OPEN_LOG"\nprintf "\\n" >> "$OPEN_LOG"\nexit "${LAUNCH_EXIT:-0}"\n',
  );
  await chmod(launcher, 0o755);
  const env = {
    ...process.env,
    HOME: trialHome,
    XDG_STATE_HOME: join(trialHome, "state"),
    PATH: bin + ":" + process.env.PATH,
    OPEN_LOG: log,
  };
  return {
    trialHome,
    plugin,
    checkout,
    async run(once = true, code = 0) {
      const child = Bun.spawn(["bash", script, plugin, ...(once ? ["--once"] : [])], {
        env: { ...env, LAUNCH_EXIT: String(code) },
        stdout: "pipe",
        stderr: "pipe",
      });
      const error = await new Response(child.stderr).text();
      expect(await child.exited, error).toBe(code);
    },
    async launches() {
      return (await readFile(log, "utf8").catch(() => ""))
        .split("\n")
        .filter(Boolean)
        .map(line => line.split("\0").slice(0, -1));
    },
  };
}

test("multiple monitors and reloads open one installer; a click can retry", async () => {
  const f = await fixture();
  await Promise.all(Array.from({ length: 8 }, () => f.run()));
  const args = [
    "env",
    "CORGI_INSTALL_PLUGIN=" + f.plugin,
    "CORGI_INSTALL_START=1",
    "bash",
    join(f.plugin, "install.sh"),
  ];
  expect(await f.launches()).toEqual([args]);
  await f.run();
  expect(await f.launches()).toEqual([args]);
  await f.run(false);
  expect(await f.launches()).toEqual([args, args]);
});

test("updates keep the first-launch marker; a fresh checkout opens again", async () => {
  const f = await fixture();
  await f.run();
  await writeFile(join(f.plugin, "manifest.json"), '{"version":"2"}');
  await f.run();
  expect((await f.launches()).length).toBe(1);
  await rename(f.plugin, f.plugin + ".old");
  await f.checkout();
  await f.run();
  expect((await f.launches()).length).toBe(2);
});

test("an existing Corgi installation does not open the installer", async () => {
  const f = await fixture();
  const root = join(f.trialHome, ".local/share/corgi");
  await mkdir(root, { recursive: true });
  await writeFile(join(root, "current"), "release");
  await f.run();
  expect(await f.launches()).toEqual([]);
});

test("a failed terminal launch can be retried automatically", async () => {
  const f = await fixture();
  await f.run(true, 1);
  await f.run();
  expect((await f.launches()).length).toBe(2);
});
