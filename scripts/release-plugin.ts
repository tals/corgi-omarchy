#!/usr/bin/env bun
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { homedir, tmpdir } from "node:os";

const root = resolve(import.meta.dir, "..");
const repository = "https://github.com/tals/corgi-omarchy";
const remote = () => process.env.CORGI_OMARCHY_REMOTE ?? "git@github.com:tals/corgi-omarchy.git";
const corgiRemote = () => process.env.CORGI_SOURCE_REMOTE ?? "https://github.com/tals/corgi";
const digest = (bytes: Uint8Array | string) => createHash("sha256").update(bytes).digest("hex");

export async function run(cwd: string, argv: string[], capture = true) {
  const child = Bun.spawn(argv, {
    cwd,
    stdout: capture ? "pipe" : "inherit",
    stderr: capture ? "pipe" : "inherit",
    stdin: "ignore",
  });
  const [text, error, code] = await Promise.all([
    capture ? new Response(child.stdout).text() : "",
    capture ? new Response(child.stderr).text() : "",
    child.exited,
  ]);
  if (code !== 0) throw Error(`Command failed: ${argv.join(" ")}\n${error}${text}`);
  return text.trim();
}
const git = (cwd: string, ...args: string[]) => run(cwd, ["git", ...args]);

export function options(args: string[]) {
  const flags = new Set(args);
  if (flags.size !== args.length || args.some(arg => !["--test", "--dry-run", "--help"].includes(arg)))
    throw Error("Usage: ./scripts/release-plugin [--test] [--dry-run]");
  return {
    test: flags.has("--test"),
    dryRun: flags.has("--dry-run"),
    help: flags.has("--help"),
  };
}

/** Binary-only releases don't need another plugin commit. Keep the existing pin. */
export function installerCode(script: string) {
  return script
    .replace(/^version='[^']+'$/m, "version=RELEASE")
    .replace(/expected='[a-f0-9]{64}' size=\d+/g, "expected=SHA256 size=SIZE");
}

export function pin(script: string) {
  const base = /^base='(https:\/\/[^'\s]+)'$/m.exec(script)?.[1];
  const version = /^version='([0-9]{8}T[0-9]{6}Z-[a-f0-9]{7,40})'$/m.exec(script)?.[1];
  if (!base || !version) throw Error("The installer has no Corgi release pin.");
  return { base, version };
}

type State = {
  remote: string;
  branch: string;
  commit: string;
  test: boolean;
  base: string;
};
const stateFile = (checkout: string) => join(checkout, ".git", "corgi-release.json");

async function branchHead(checkout: string, url: string, branch: string) {
  const head = (await git(checkout, "ls-remote", url, `refs/heads/${branch}`)).split(/\s/)[0];
  if (!head) return null;
  await git(checkout, "fetch", "--quiet", url, `refs/heads/${branch}`);
  return head;
}

export async function prepare(checkout: string, source: string, install: string, test: boolean, url = remote()) {
  const branch = test ? "test" : "main";
  const previous = await branchHead(checkout, url, branch);
  if (!test && previous) await git(checkout, "merge-base", "--is-ancestor", previous, "HEAD");
  const baseline = previous ?? (await git(checkout, "rev-parse", "HEAD"));
  const oldInstall = await git(checkout, "show", `${baseline}:install.sh`);
  const manifest = JSON.parse(await readFile(join(checkout, "manifest.json"), "utf8"));
  const qml = dirname(manifest.entryPoints.barWidget);
  console.log("Refreshing plugin animations...");
  await run(
    checkout,
    [process.execPath, "tools/motion-build.ts", source, "tools/motion.ts", join(qml, "corgi")],
    false,
  );
  await run(checkout, ["bash", "tools/rehash"], false);
  const runtimeChanged = !!(await git(
    checkout,
    "diff",
    "--name-only",
    baseline,
    "--",
    "manifest.json",
    "qml-*",
    "CONTRACT.md",
  ));
  const next = pin(install);
  const changed =
    !previous ||
    runtimeChanged ||
    installerCode(oldInstall) !== installerCode(install.trim()) ||
    (test && pin(oldInstall).version !== next.version);
  await writeFile(join(checkout, "install.sh"), changed ? install : oldInstall + "\n", { mode: 0o755 });
  await chmod(join(checkout, "install.sh"), 0o755);
  console.log("Checking plugin...");
  await run(checkout, ["bash", "-n", "install.sh"], false);
  await run(checkout, ["bash", "tools/rehash", "--check"], false);
  await run(checkout, [process.execPath, "test", "test"]);
  await git(checkout, "add", "-A");
  const tree = await git(checkout, "write-tree");
  let commit: string;
  if (previous && tree === (await git(checkout, "rev-parse", `${previous}^{tree}`))) {
    commit = previous;
  } else if (test) {
    // Test snapshots advance their own history without merging the stable branch.
    commit = await git(
      checkout,
      "-c",
      "user.name=Corgi releases",
      "-c",
      "user.email=releases@corgi.computer",
      "commit-tree",
      tree,
      "-p",
      baseline,
      "-m",
      `plugin: publish test with Corgi ${next.version}`,
    );
  } else {
    if (previous) await git(checkout, "merge-base", "--is-ancestor", previous, "HEAD");
    if (await git(checkout, "diff", "--cached", "--name-only"))
      await git(
        checkout,
        "-c",
        "user.name=Corgi releases",
        "-c",
        "user.email=releases@corgi.computer",
        "commit",
        "-qm",
        `plugin: update for Corgi ${next.version}`,
      );
    commit = await git(checkout, "rev-parse", "HEAD");
  }
  const state: State = {
    remote: url,
    branch,
    commit,
    test,
    base: process.env.CORGI_TEST_BASE_URL ?? "https://corgi.computer/test",
  };
  if (commit !== previous) await git(checkout, "push", "--dry-run", url, `${commit}:refs/heads/${branch}`);
  await git(checkout, "update-ref", "refs/corgi/release", commit);
  await writeFile(stateFile(checkout), JSON.stringify(state));
  return state;
}

async function files(path: string, prefix = ""): Promise<string[]> {
  const entries = await readdir(join(path, prefix), { withFileTypes: true });
  return (
    await Promise.all(entries.map(e => (e.isDirectory() ? files(path, join(prefix, e.name)) : [join(prefix, e.name)])))
  ).flat();
}

/** The Omarchy installer takes a repository URL, without a branch option. */
export async function mirror(
  checkout: string,
  commit: string,
  put: (path: string, bytes: Uint8Array, mutable: boolean) => Promise<void>,
) {
  const bare = await mkdtemp(join(tmpdir(), "corgi-plugin-http-"));
  try {
    await git(bare, "init", "--quiet", "--bare", "--initial-branch=main");
    await git(bare, "fetch", "--quiet", checkout, commit);
    await git(bare, "update-ref", "refs/heads/main", commit);
    await git(bare, "repack", "-a", "-d", "-q");
    await git(bare, "update-server-info");
    const paths = (await files(bare)).filter(
      p => p.startsWith("objects/") || ["info/refs", "HEAD", "refs/heads/main"].includes(p),
    );
    const mutable = (p: string) => !p.startsWith("objects/") || p.startsWith("objects/info/");
    // Upload objects before advertising refs, keeping every older pack available.
    for (const path of paths.filter(p => !mutable(p))) await put(path, await readFile(join(bare, path)), false);
    for (const path of ["objects/info/packs", "refs/heads/main", "info/refs", "HEAD"])
      await put(path, await readFile(join(bare, path)), true);
    await put("published.json", Buffer.from(JSON.stringify({ commit })), true);
  } finally {
    await rm(bare, { recursive: true, force: true });
  }
}

async function publishMirror(checkout: string, state: State) {
  const existing = await fetch(`${state.base}/corgi.computer.git/published.json`, { cache: "no-store" });
  if (existing.ok && ((await existing.json()) as { commit: string }).commit === state.commit) return;
  const config = JSON.parse(
    await readFile(process.env.CORGI_RELEASE_CONFIG ?? join(homedir(), ".config/corgi/release.json"), "utf8"),
  );
  // Credentials and bucket settings are shared with Corgi's publisher.
  let credentials = {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  };
  if (!credentials.accessKeyId && !credentials.secretAccessKey && config.credentialsFile) {
    const { stat } = await import("node:fs/promises");
    if ((await stat(config.credentialsFile)).mode & 0o077)
      throw Error("Release credentials must be private (chmod 600).");
    credentials = JSON.parse(await readFile(config.credentialsFile, "utf8"));
  }
  if (!credentials.accessKeyId || !credentials.secretAccessKey) throw Error("Release bucket credentials are missing.");
  const s3 = new Bun.S3Client({
    endpoint: config.endpoint,
    region: config.region,
    bucket: config.bucket,
    ...credentials,
  });
  const base = String(config.publicBaseUrl).replace(/\/+$/, "");
  if (state.base !== `${base}/test`) throw Error("The test plugin must use the release bucket's /test prefix.");
  await mirror(checkout, state.commit, async (path, bytes, mutable) => {
    const key = `test/corgi.computer.git/${path}`;
    for (let attempt = 0; ; attempt++) {
      try {
        const response = await fetch(s3.file(key).presign({ method: "PUT", expiresIn: 3600 }), {
          method: "PUT",
          body: new Uint8Array(bytes),
          headers: {
            "Content-Type": "application/octet-stream",
            "Cache-Control": mutable ? "no-cache, max-age=0" : "public, max-age=31536000, immutable",
          },
        });
        if (!response.ok) throw Error(`Uploading ${key}: HTTP ${response.status}`);
        const served = await fetch(`${base}/${key}`, { cache: "no-store" });
        if (!served.ok || digest(new Uint8Array(await served.arrayBuffer())) !== digest(bytes))
          throw Error(`Public verification failed: ${key}`);
        break;
      } catch (error) {
        if (attempt === 2) throw error;
        await Bun.sleep(1000 * (attempt + 1));
      }
    }
  });
}

export async function publish(checkout: string, mirrorTest = publishMirror) {
  const state: State = JSON.parse(await readFile(stateFile(checkout), "utf8"));
  const current = await branchHead(checkout, state.remote, state.branch);
  if (current !== state.commit) {
    await git(checkout, "push", state.remote, `${state.commit}:refs/heads/${state.branch}`);
    console.log(`Published ${state.test ? "test " : ""}plugin.`);
  } else console.log("Plugin is up to date; nothing pushed.");
  if (state.test) await mirrorTest(checkout, state);
  instructions(state.test, state.base);
}

function instructions(test: boolean, base: string) {
  console.log(
    `\nInstall with the Omarchy plugin:\n  omarchy plugin add ${test ? `${base}/corgi.computer.git` : repository} --enable\n\nUpdate an existing ${test ? "test " : ""}plugin:\n  omarchy plugin update corgi.computer`,
  );
}

async function get(url: string) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) throw Error(`Downloading ${url}: HTTP ${response.status}`);
  return response.text();
}

async function standalone(test: boolean) {
  const temp = await mkdtemp(join(tmpdir(), "corgi-plugin-release-"));
  const checkout = join(temp, "plugin");
  try {
    const head = await git(root, "rev-parse", "HEAD");
    await run(temp, ["git", "clone", "--quiet", "--no-hardlinks", root, checkout]);
    await git(checkout, "checkout", "--quiet", "--detach", head);
    // Incorporate an automatic pin update before choosing which Corgi to compile against.
    if (!test) {
      const previous = await branchHead(checkout, remote(), "main");
      if (previous)
        await git(
          checkout,
          "-c",
          "user.name=Corgi releases",
          "-c",
          "user.email=releases@corgi.computer",
          "rebase",
          previous,
        );
    }
    const configPath = process.env.CORGI_RELEASE_CONFIG ?? join(homedir(), ".config/corgi/release.json");
    const base = existsSync(configPath)
      ? String(JSON.parse(await readFile(configPath, "utf8")).publicBaseUrl).replace(/\/+$/, "")
      : "https://corgi.computer";
    const testBase = `${base}/test`;
    process.env.CORGI_TEST_BASE_URL = testBase;
    let install = await readFile(join(checkout, "install.sh"), "utf8");
    if (test) {
      const channel = await fetch(`${testBase}/channels/stable.json`, { cache: "no-store" });
      if (channel.ok) {
        const { version } = JSON.parse(((await channel.json()) as { payload: string }).payload);
        if (!/^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{7,40}$/.test(version)) throw Error("Invalid Corgi channel version.");
        install = await get(`${testBase}/releases/${version}/install.sh`);
      } else if (channel.status !== 404) throw Error(`Checking test channel: HTTP ${channel.status}`);
    }
    const selected = pin(install);
    const { commit } = JSON.parse(
      JSON.parse(await get(`${selected.base}/releases/${selected.version}/manifest.json`)).payload,
    );
    if (!/^[a-f0-9]{40}$/.test(commit)) throw Error("The Corgi release has an invalid source commit.");
    const source = join(temp, "corgi");
    await mkdir(source);
    await git(source, "init", "--quiet");
    await git(source, "fetch", "--quiet", "--depth=1", corgiRemote(), commit);
    await git(source, "checkout", "--quiet", "--detach", "FETCH_HEAD");
    console.log(`Using Corgi ${selected.version}.`);
    await prepare(checkout, source, install, test);
    await publish(checkout);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}

async function main() {
  const opts = options(process.argv.slice(2));
  if (opts.help) {
    console.log(
      "Usage: ./scripts/release-plugin [--test] [--dry-run]\n\nPublishes committed HEAD from a temporary checkout. Keeps the existing Corgi pin;\n--test uses the latest test Corgi when available, and publishes a separate plugin.\nCorgi's publisher invokes this script automatically with its release context.",
    );
    return;
  }
  if (opts.dryRun) {
    console.log(
      `Check committed HEAD → regenerate animations → keep or update installer pin → push ${opts.test ? "test and publish its HTTP repository" : "main"} only if changed.\nNo remote changes performed.`,
    );
    instructions(opts.test, process.env.CORGI_TEST_BASE_URL ?? "https://corgi.computer/test");
    return;
  }
  switch (process.env.CORGI_RELEASE_PHASE) {
    case "prepare": {
      const source = process.env.CORGI_RELEASE_SOURCE,
        out = process.env.CORGI_RELEASE_DIR;
      if (!source || !out) throw Error("Missing Corgi release source/artifacts.");
      await prepare(root, source, await readFile(join(out, "install.sh"), "utf8"), opts.test);
      return;
    }
    case "publish":
      await publish(root);
      return;
    case undefined:
      await standalone(opts.test);
      return;
    default:
      throw Error("Unknown Corgi release phase.");
  }
}
if (import.meta.main)
  main().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
