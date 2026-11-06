#!/usr/bin/env bun
import { createHash } from "node:crypto";
import { mkdir, rmdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";

// Opens the shared installer once per plugin checkout, or again on a click.
const [plugin, mode] = process.argv.slice(2);
if (!plugin) throw new Error("plugin directory required");
let marker: string | undefined;

if (mode === "--once") {
  if (await Bun.file(join(homedir(), ".local/share/corgi/current")).exists()) process.exit(0);
  if (
    !(await Bun.file(join(plugin, "manifest.json")).exists()) ||
    !(await Bun.file(join(plugin, "install.sh")).exists())
  )
    process.exit(0);
  const state = join(process.env.XDG_STATE_HOME || join(homedir(), ".local/state"), "omarchy/corgi.computer");
  // Updates keep the checkout; removing and adding it creates a new one.
  const info = await stat(plugin, { bigint: true });
  const identity = createHash("sha256")
    .update(`${info.dev}:${info.ino}:${info.birthtimeNs}`)
    .digest("hex")
    .slice(0, 16);
  marker = join(state, `install-${identity}`);
  await mkdir(state, { recursive: true });
  try {
    await mkdir(marker);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") process.exit(0);
    throw error;
  }
}

try {
  const child = Bun.spawn(
    [
      "omarchy-launch-terminal",
      "env",
      `CORGI_INSTALL_PLUGIN=${plugin}`,
      "CORGI_INSTALL_START=1",
      "bash",
      join(plugin, "install.sh"),
    ],
    { stdin: "inherit", stdout: "inherit", stderr: "inherit" },
  );
  if (await child.exited) throw new Error("Could not open the installer terminal");
} catch (error) {
  if (marker) await rmdir(marker);
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
