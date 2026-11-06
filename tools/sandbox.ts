#!/usr/bin/env bun
//! Hosts Corgi's Omarchy plugin for an Omarchy VM (such as Try Omarchy on a
//! Mac): Linux builds signed with a throwaway key no real installation trusts,
//! their manifests and channel, and the plugin as a git repository pinning
//! them, for `omarchy plugin add`. The plugin is its own repository
//! (tals/corgi-omarchy); CORGI_SOURCE selects the Corgi checkout to build.
//! Its working tree is served as it is, with a pinned
//! installer of the sandbox's own. Everything is served from this machine
//! over its tailnet only. The builds go to the release bucket under sandbox/,
//! apart from releases and channels, when this machine publishes releases
//! (~/.config/corgi/release.json); otherwise they're served with the plugin.
//!
//!   bun tools/sandbox.ts          build and pin a release, then serve
//!   bun tools/sandbox.ts build    build a release and pin it; the VM
//!                                         takes it with `omarchy plugin update`
//!   bun tools/sandbox.ts channel  build a release for Corgi's own updater
//!                                         only; the pin stays, and the VM takes it
//!                                         with `corgi update` or within the hour
//!   bun tools/sandbox.ts plugin   republish the plugin checkout with the same pin
//!   bun tools/sandbox.ts serve    serve what's built
//!   bun tools/sandbox.ts stop     stop serving
//!
//! CORGI_OMARCHY_PUBLISH=1 uses permanent public downloads, and writes the
//! pinned installer into the plugin checkout, to commit and push from there.
//!
//! Everything else lives in the common Git directory, under omarchy-sandbox/.
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve, sep } from "node:path";
import { homedir } from "node:os";
import { spawn } from "node:child_process";

const source = resolve(import.meta.dir, "..");
const repo = resolve(process.env.CORGI_SOURCE ?? join(source, "../corgi"));
const { installer, loadCredentials, targets, timestampVersion } = await import(join(repo, "scripts/release.ts"));
const port = 8443;
/** Where the static server listens; Tailscale proxies HTTPS to it, as only root may serve a folder directly. */
const local_port = 18443;
const plugin_id = "corgi.computer";
const publishing = process.env.CORGI_OMARCHY_PUBLISH === "1";
/** The bucket prefix the builds go under. */
const prefix = publishing ? "omarchy" : "sandbox";

function run(argv: string[], cwd = repo): string {
  const p = Bun.spawnSync(argv, { cwd, stdout: "pipe", stderr: "pipe" });
  if (!p.success) throw Error(`${argv.join(" ")} failed:\n${p.stderr.toString()}${p.stdout.toString()}`);
  return p.stdout.toString().trim();
}
const git = (args: string[], cwd = repo) => run(["git", ...args], cwd);
/** The Linux builds to make: the VM's alone (Try Omarchy is arm64) unless
 * $CORGI_OMARCHY_TARGETS lists others; every Linux one when publishing. */
const built = (
  process.env.CORGI_OMARCHY_TARGETS ?? (publishing ? "linux-x86_64,linux-aarch64" : "linux-aarch64")
).split(",");
/** The plugin's files that stay at its top level, outside its QML's folder. */
const top_level = new Set(["manifest.json", "README.md", "LICENSE", "HACKING.md", ".gitignore"]);

const common = resolve(repo, git(["rev-parse", "--git-common-dir"])),
  state = join(common, publishing ? "omarchy-publish" : "omarchy-sandbox"),
  site = join(state, "site"),
  work = join(state, "plugin"),
  bare = join(site, `${plugin_id}.git`);

function base(): string {
  const self = JSON.parse(run(["tailscale", "status", "--json"])).Self;
  return `https://${String(self.DNSName).replace(/\.$/, "")}:${port}`;
}

/** The release bucket's sandbox/ prefix, or null on a machine that doesn't publish releases. */
async function bucket() {
  const path = process.env.CORGI_RELEASE_CONFIG ?? join(homedir(), ".config", "corgi", "release.json");
  if (!existsSync(path)) return null;
  const config = JSON.parse(readFileSync(path, "utf8")),
    s3 = new Bun.S3Client({
      endpoint: config.endpoint,
      region: config.region,
      bucket: config.bucket,
      ...(await loadCredentials(config)),
    }),
    url = `${String(config.publicBaseUrl).replace(/\/+$/, "")}/${prefix}`;
  return {
    url,
    async put(key: string, bytes: Uint8Array, type: string, cache = "public, max-age=31536000, immutable") {
      console.log(`Uploading ${url}/${key}…`);
      const signed = s3.file(`${prefix}/${key}`).presign({ method: "PUT", expiresIn: 3600 }),
        headers = { "Content-Type": type, "Cache-Control": cache },
        response = await fetch(signed, { method: "PUT", body: bytes, headers });
      if (!response.ok) throw Error(`Uploading ${key}: ${response.status} ${await response.text()}`);
      // Cloudflare compresses text, so only an uncompressed answer's length can be compared.
      const served = await fetch(`${url}/${key}`, {
        method: "HEAD",
        headers: { "Accept-Encoding": "identity" },
      });
      if (!served.ok || Number(served.headers.get("content-length")) !== bytes.length)
        throw Error(`${url}/${key} isn't served`);
    },
    remove: (key: string) => s3.file(`${prefix}/${key}`).delete(),
  };
}

/** The throwaway signing key, made on first use. */
function key() {
  const path = join(state, "key.pem");
  if (!existsSync(path)) {
    mkdirSync(state, { recursive: true });
    const { privateKey } = generateKeyPairSync("ed25519");
    writeFileSync(path, privateKey.export({ type: "pkcs8", format: "pem" }), {
      mode: 0o600,
    });
  }
  const privateKey = createPrivateKey(readFileSync(path)),
    publicKey = Buffer.from(createPublicKey(privateKey).export({ type: "spki", format: "der" }))
      .subarray(-32)
      .toString("hex");
  return { privateKey, publicKey };
}

/** The release the served plugin pins, if any. */
function pinned(): string | null {
  const path = join(publishing ? source : work, "install.sh");
  return existsSync(path) ? (/^version='([^']+)'$/m.exec(readFileSync(path, "utf8"))?.[1] ?? null) : null;
}

/** Builds Linux Corgi as a sandbox release and moves the channel to it, and
 * pins it in the plugin when `pinning`. */
async function build(pinning: boolean): Promise<string> {
  const store = await bucket();
  if (publishing && !store) throw Error("Public Omarchy packages require a release bucket");
  const { privateKey, publicKey } = key(),
    url = store?.url ?? base(),
    commit = git(["rev-parse", "HEAD"]),
    version = timestampVersion(commit),
    dir = join(site, "releases", version),
    abi = /^export const abi = "([^"]+)";$/m.exec(readFileSync(join(repo, "src/updates.ts"), "utf8"))![1],
    // The installer refuses, by checksum, what isn't built.
    binaries: Record<string, { sha256: string; size: number }> = Object.fromEntries(
      targets.map(t => [t.name, { sha256: "0".repeat(64), size: 1 }]),
    );
  mkdirSync(dir, { recursive: true });
  for (const t of targets.filter(t => built.includes(t.name))) {
    const binary = join(dir, `corgi-${t.name}`);
    console.log(`Building Corgi ${version} for ${t.name}…`);
    run([
      "bun",
      "build.ts",
      "--target",
      t.bun,
      "--release-version",
      version,
      "--release-commit",
      commit,
      "--update-url",
      url,
      "--update-public-key",
      publicKey,
      "--outfile",
      binary,
    ]);
    rmSync(`${binary}.build.json`, { force: true });
    rmSync(`${binary}.sha256`, { force: true });
    const bytes = readFileSync(binary),
      target = {
        sha256: createHash("sha256").update(bytes).digest("hex"),
        size: bytes.length,
      },
      payload = JSON.stringify({
        schema_version: 1,
        version,
        commit,
        update_abi: abi,
        targets: {
          [t.name]: {
            url: `${url}/releases/${version}/corgi-${t.name}`,
            ...target,
          },
        },
      });
    binaries[t.name] = target;
    const manifest = JSON.stringify({
      payload,
      signature: sign(null, Buffer.from(payload), privateKey).toString("hex"),
    });
    writeFileSync(join(dir, t.manifest), manifest);
    await store?.put(`releases/${version}/corgi-${t.name}`, bytes, "application/octet-stream");
    await store?.put(`releases/${version}/${t.manifest}`, Buffer.from(manifest), "application/json");
    // Corgi in a plugin follows its channel too, whichever of the two is newer.
    mkdirSync(join(site, dirname(t.channel)), { recursive: true });
    writeFileSync(join(site, t.channel), manifest);
    await store?.put(t.channel, Buffer.from(manifest), "application/json", "no-cache, max-age=0");
  }
  if (pinning) await pin(installer(url, version, binaries), version);
  if (publishing) return version;
  // The VM only ever needs the pinned release, the channel's, and the one before it.
  const keep = pinned();
  for (const old of readdirSync(join(site, "releases"))
    .sort()
    .slice(0, -2)
    .filter(v => v !== keep)) {
    rmSync(join(site, "releases", old), { recursive: true, force: true });
    for (const t of targets)
      for (const name of [`corgi-${t.name}`, t.manifest]) await store?.remove(`releases/${old}/${name}`);
  }
  return version;
}

/** Commits the plugin checkout's working tree with `script` as its pinned
 * installer, and publishes it for dumb-HTTP clones. Publishing only writes
 * the installer into the checkout. */
async function pin(script: string, version: string) {
  if (!existsSync(join(source, "manifest.json")))
    throw Error(`No plugin checkout at ${source}; set CORGI_OMARCHY_PLUGIN`);
  if (publishing) {
    writeFileSync(join(source, "install.sh"), script, { mode: 0o755 });
    return;
  }
  if (!existsSync(join(work, ".git"))) {
    mkdirSync(work, { recursive: true });
    git(["init", "-q", "-b", "main"], work);
  }
  for (const entry of readdirSync(work)) if (entry !== ".git") rmSync(join(work, entry), { recursive: true });
  // What's tracked, and what's new but not ignored, uncommitted edits and all,
  // but the harness, tools and README images. The QML and what it loads go in
  // a folder named for their content, as the plugin keeps them (its
  // tools/rehash), whether or not the checkout has renamed it yet: the shell
  // keeps compiled QML by path for as long as it runs, so only a path it has
  // never loaded brings new code.
  const manifest = JSON.parse(readFileSync(join(source, "manifest.json"), "utf8")),
    entries: Record<string, string> = manifest.entryPoints ?? {},
    within = dirname(Object.values(entries)[0] ?? "Widget.qml"),
    prefix = within === "." ? "" : `${within}/`,
    files = git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], source)
      .split("\0")
      .filter(
        path =>
          path &&
          path !== "install.sh" &&
          !path.startsWith("test/") &&
          !path.startsWith("tools/") &&
          !path.startsWith("assets/") &&
          existsSync(join(source, path)),
      ),
    isCode = (path: string) => (prefix ? path.startsWith(prefix) : !top_level.has(path)),
    code = files
      .filter(isCode)
      .map(path => path.slice(prefix.length))
      .sort(),
    hash = createHash("sha256");
  for (const path of code)
    hash
      .update(path)
      .update("\0")
      .update(readFileSync(join(source, prefix + path)));
  const folder = `qml-${hash.digest("hex").slice(0, 12)}`;
  for (const path of files) {
    const dest = join(work, isCode(path) ? join(folder, path.slice(prefix.length)) : path);
    mkdirSync(dirname(dest), { recursive: true });
    cpSync(join(source, path), dest);
  }
  for (const [kind, entry] of Object.entries(entries))
    manifest.entryPoints[kind] = `${folder}/${entry.slice(prefix.length)}`;
  writeFileSync(join(work, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  writeFileSync(join(work, "install.sh"), script, { mode: 0o755 });
  git(["add", "-A"], work);
  if (!git(["status", "--porcelain"], work)) return;
  git(
    ["-c", "user.name=Corgi sandbox", "-c", "user.email=sandbox@corgi.invalid", "commit", "-qm", `Pin ${version}`],
    work,
  );
  if (!existsSync(bare)) {
    git(["init", "-q", "--bare", "-b", "main", bare]);
  }
  git(["remote", git(["remote"], work).split("\n").includes("origin") ? "set-url" : "add", "origin", bare], work);
  git(["push", "-q", "origin", "main"], work);
  // One pack, so a dumb-HTTP clone makes few requests.
  git(["--git-dir", bare, "repack", "-a", "-d", "-q"]);
  git(["--git-dir", bare, "update-server-info"]);
}

/** Answers files under the site, and nothing else. */
function http() {
  Bun.serve({
    hostname: "127.0.0.1",
    port: local_port,
    async fetch(request) {
      const path = resolve(site, "." + decodeURIComponent(new URL(request.url).pathname));
      if (!path.startsWith(site + sep)) return new Response("Not found", { status: 404 });
      const file = Bun.file(path);
      return (await file.exists()) ? new Response(file) : new Response("Not found", { status: 404 });
    },
  });
}

async function serve() {
  const up = await fetch(`http://127.0.0.1:${local_port}/`).then(
    () => true,
    () => false,
  );
  if (!up) {
    spawn(process.execPath, [import.meta.path, "__http"], {
      detached: true,
      stdio: "ignore",
    }).unref();
    await Bun.sleep(500);
  }
  run(["tailscale", "serve", "--bg", `--https=${port}`, `http://127.0.0.1:${local_port}`]);
  const url = base();
  console.log(`Serving ${site} at ${url}, on the tailnet only.

In the Omarchy VM:
  curl -fsS ${url}/${plugin_id}.git/HEAD        # reachable?
  omarchy plugin add ${url}/${plugin_id}.git --enable

Then click the corgi in the bar. Here, then:
  bun tools/sandbox.ts plugin    after editing ${source}
  bun tools/sandbox.ts build     to pin a new Corgi
and in the VM:
  omarchy plugin update ${plugin_id}
Or, for Corgi updating itself with the plugin left alone:
  bun tools/sandbox.ts channel   here, and \`corgi update\` in the VM`);
}

switch (process.argv[2] ?? "") {
  case "":
    console.log(`Pinned ${await build(true)}.`);
    await serve();
    break;
  case "build":
    console.log(`Pinned ${await build(true)}. In the VM: omarchy plugin update ${plugin_id}`);
    break;
  case "channel":
    console.log(`Published ${await build(false)} to the channel; the pin stays. In the VM: corgi update`);
    break;
  case "plugin": {
    const script = readFileSync(join(publishing ? source : work, "install.sh"), "utf8");
    await pin(script, /^version='([^']+)'$/m.exec(script)![1]);
    console.log(`Republished the plugin. In the VM: omarchy plugin update ${plugin_id}`);
    break;
  }
  case "serve":
    await serve();
    break;
  case "__http":
    http();
    break;
  case "stop":
    run(["tailscale", "serve", `--https=${port}`, "off"]);
    Bun.spawnSync(["pkill", "-f", `${import.meta.path} __http`]);
    console.log("Stopped serving.");
    break;
  default:
    console.error("Usage: bun tools/sandbox.ts [build | channel | plugin | serve | stop]");
    process.exit(2);
}
