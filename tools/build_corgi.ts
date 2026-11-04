#!/usr/bin/env bun
//! Builds the plugin's copy of Corgi's animations from a Corgi checkout.
//! tools/motion.ts imports Corgi's modules as `@corgi/NAME` (the checkout's
//! src/NAME.ts). It and each module it reaches become one ES module apiece in
//! OUT_DIR, which Qt's QML engine loads. Imports resolve with the checkout's
//! package.json browser stand-ins, as on Corgi's landing page, and the
//! checkout's pinned TypeScript compiles each file down to ES2016, which that
//! engine runs. Corgi's modules must stay free of BigInt literals and `Intl`,
//! which it lacks.
//!
//!   bun tools/build_corgi.ts --corgi CHECKOUT [OUT_DIR]
//!
//! OUT_DIR defaults to the corgi/ folder next to the manifest's Widget.qml.
import { mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { parseArgs } from "node:util";

const plugin = join(import.meta.dir, "..");

/** Each module's file in OUT_DIR. */
const fileName = (path: string) => basename(path, extname(path)) + ".mjs";

/** The TypeScript the checkout's typecheck pins, installed by its tooling. */
async function typescript(corgi: string): Promise<any> {
  const pin = /\btypescript: "([^"]+)"/.exec(readFileSync(join(corgi, "typecheck.ts"), "utf8"));
  if (!pin) throw Error("No TypeScript pin in " + join(corgi, "typecheck.ts"));
  const tooling = await import(join(corgi, "scripts", "tooling.ts"));
  const [compiler] = await tooling.packages("typecheck", { typescript: pin[1] });
  return (await import(join(compiler, "lib", "typescript.js"))).default;
}

export async function build(corgi: string, entryPath: string, out: string) {
  const root = resolve(corgi),
    entry = resolve(entryPath),
    dir = resolve(out);
  /** `@corgi/NAME` is the checkout's src/NAME.ts, wherever the importer is. */
  const alias: Bun.BunPlugin = {
    name: "corgi-alias",
    setup(build) {
      build.onResolve({ filter: /^@corgi\// }, args => ({ path: join(root, "src", args.path.slice(7) + ".ts") }));
    },
  };
  /** Where a module's file says it came from: its path in Corgi, else its name. */
  const origin = (path: string) => (path.startsWith(root + "/") ? path.slice(root.length + 1) : basename(path));

  const ts = await typescript(root),
    compilerOptions = { target: ts.ScriptTarget.ES2016, module: ts.ModuleKind.ESNext, useDefineForClassFields: false };
  // Bun heads each file with its path from here; those are rewritten below.
  process.chdir(root);
  // The modules the entry reaches, and where each of their imports resolves.
  const graph = await Bun.build({ entrypoints: [entry], target: "browser", metafile: true, plugins: [alias] });
  const inputs = Object.entries(graph.metafile!.inputs).map(([path, input]) => ({
      path: resolve(path),
      imports: new Map(input.imports.map(i => [i.original!, fileName(i.path)])),
    })),
    names = new Set(inputs.map(input => fileName(input.path)));
  if (names.size !== inputs.length) throw Error("Two modules would share a file name");
  const importsOf = new Map(inputs.map(input => [input.path, input.imports]));

  // Every module its own entry point, importing the others' files.
  mkdirSync(dir, { recursive: true });
  for (const name of readdirSync(dir)) if (name.endsWith(".mjs")) rmSync(join(dir, name));
  await Bun.build({
    entrypoints: inputs.map(input => input.path),
    target: "browser",
    outdir: dir,
    naming: "[name].mjs",
    plugins: [
      {
        name: "externalize",
        setup(build) {
          build.onResolve({ filter: /.*/ }, args => {
            const name = importsOf.get(args.importer)?.get(args.path);
            return name ? { path: "./" + name, external: true } : undefined;
          });
          build.onLoad({ filter: /\.ts$/ }, async args => ({
            loader: "js",
            contents: ts.transpileModule(await Bun.file(args.path).text(), { fileName: args.path, compilerOptions })
              .outputText,
          }));
        },
      },
      // After the externalizing plugin, which claims the imports between modules.
      alias,
    ],
  });
  // Each file's heading names its module the same on every machine.
  for (const input of inputs) {
    const file = join(dir, fileName(input.path)),
      text = await Bun.file(file).text();
    await Bun.write(file, text.replace(/^\/\/ .*/, "// " + origin(input.path)));
  }
}

if (import.meta.main) {
  const { values, positionals } = parseArgs({
    args: Bun.argv.slice(2),
    options: { corgi: { type: "string" } },
    allowPositionals: true,
  });
  if (!values.corgi || positionals.length > 1) {
    console.error("Usage: bun tools/build_corgi.ts --corgi CHECKOUT [OUT_DIR]");
    process.exit(2);
  }
  const manifest = JSON.parse(readFileSync(join(plugin, "manifest.json"), "utf8")),
    out = positionals[0] ?? join(plugin, dirname(manifest.entryPoints.barWidget), "corgi");
  await build(values.corgi, join(plugin, "tools", "motion.ts"), out);
}
