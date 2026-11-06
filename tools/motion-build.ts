#!/usr/bin/env bun
//! Builds the Omarchy plugin's copy of Corgi's animations. ENTRY is the
//! plugin's own module, which imports Corgi's as `@corgi/NAME` (src/NAME.ts).
//! It and each module it reaches become one ES module apiece in OUT_DIR,
//! which Qt's QML engine loads. Imports resolve with package.json's browser
//! stand-ins, as on the landing page, and the pinned TypeScript compiles each
//! file down to ES2016, which that engine runs. The plugin imports the
//! entry's .mjs.
//!
//!   bun tools/motion-build.ts CORGI_SOURCE ENTRY OUT_DIR
import { mkdirSync, readdirSync, rmSync } from "node:fs";
import { basename, extname, join, resolve } from "node:path";

/** Each module's file in OUT_DIR. */
const fileName = (path: string) => basename(path, extname(path)) + ".mjs";

export async function build(corgi: string, entryPath: string, out: string) {
  const root = resolve(corgi);
  const tooling = await import(join(root, "scripts/tooling.ts"));
  /** `@corgi/NAME` is Corgi's src/NAME.ts, wherever the importer is. */
  const alias: Bun.BunPlugin = {
    name: "corgi-alias",
    setup(build) {
      build.onResolve({ filter: /^@corgi\// }, args => ({
        path: join(root, "src", args.path.slice(7) + ".ts"),
      }));
    },
  };
  /** Where a module's file says it came from: its path in Corgi, else its name. */
  const origin = (path: string) => (path.startsWith(root + "/") ? path.slice(root.length + 1) : basename(path));

  const entry = resolve(entryPath),
    dir = resolve(out);
  // Bun heads each file with its path from here; those are rewritten below.
  process.chdir(root);
  // The modules the entry reaches, and where each of their imports resolves.
  const graph = await Bun.build({
    entrypoints: [entry],
    target: "browser",
    metafile: true,
    plugins: [alias],
  });
  const inputs = Object.entries(graph.metafile!.inputs).map(([path, input]) => ({
      path: resolve(path),
      imports: new Map(input.imports.map(i => [i.original!, fileName(i.path)])),
    })),
    names = new Set(inputs.map(input => fileName(input.path)));
  if (names.size !== inputs.length) throw Error("Two modules would share a file name");
  const importsOf = new Map(inputs.map(input => [input.path, input.imports]));
  // The typecheck's TypeScript, so it's already at hand.
  const [compiler] = await tooling.packages("typecheck", {
      typescript: "6.0.3",
    }),
    ts: typeof import("typescript") = (await import(join(compiler, "lib", "typescript.js"))).default,
    compilerOptions = {
      target: ts.ScriptTarget.ES2016,
      module: ts.ModuleKind.ESNext,
      useDefineForClassFields: false,
    };

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
        name: "omarchy-motion",
        setup(build) {
          build.onResolve({ filter: /.*/ }, args => {
            const name = importsOf.get(args.importer)?.get(args.path);
            return name ? { path: "./" + name, external: true } : undefined;
          });
          build.onLoad({ filter: /\.ts$/ }, async args => ({
            loader: "js",
            contents: ts.transpileModule(await Bun.file(args.path).text(), {
              fileName: args.path,
              compilerOptions,
            }).outputText,
          }));
        },
      },
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
  const [corgi, entry, dir] = process.argv.slice(2);
  if (!corgi || !entry || !dir) {
    console.error("Usage: bun tools/motion-build.ts CORGI_SOURCE ENTRY OUT_DIR");
    process.exit(2);
  }
  await build(corgi, entry, dir);
}
