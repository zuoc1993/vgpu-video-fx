import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(fileURLToPath(new URL(".", import.meta.url)), "..");
const effectsDir = path.join(root, "packages/effect-core/src/effects");

function* wgslFiles(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* wgslFiles(full);
    else if (entry.name.endsWith(".wgsl")) yield full;
  }
}

const entries = [...wgslFiles(effectsDir)];
if (entries.length === 0) throw new Error("no .wgsl files");

let failed = 0;
for (const file of entries) {
  const result = spawnSync("npx", ["vgpu", "check", file, "--require-validation"], {
    cwd: root,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    failed += 1;
    console.error(`FAIL ${path.relative(root, file)}`);
    console.error(result.stdout);
    console.error(result.stderr);
  } else {
    console.log(`OK   ${path.relative(root, file)}`);
  }
}

if (failed) process.exit(1);
