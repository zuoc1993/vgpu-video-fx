#!/usr/bin/env node
/**
 * Export the effect catalog as backend-agnostic artifacts for the Python
 * wgpu-py renderer (docs/wgpu-py-backend.md):
 *
 *   packages/effect-core/dist-effects/{id}.wgsl    the exact WGSL vgpu feeds the GPU:
 *                                                  vgpu-flattened imports + the fullscreen
 *                                                  vertex stage vgpu injects at runtime
 *   packages/effect-core/dist-effects/effects.json manifest: param metadata + defaults,
 *                                                  authoritative uniform layout (vgpu
 *                                                  reflection) + per-field value mapping
 *
 * The Python side parses nothing: layout offsets come from vgpu's own
 * reflection, and the (values, ctx) -> uniform-field mapping is resolved here
 * by evaluating each effect's uniforms() against sentinel inputs.
 *
 *   npm run export:effects                        regenerate artifacts
 *   node scripts/export-effects.mjs --dry         validate everything, write nothing
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { register } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = join(ROOT, "packages", "effect-core", "dist-effects");
const DRY = process.argv.includes("--dry");

// Must be registered before importing the TS catalog (it pulls in *.wgsl).
register(new URL("./wgsl-export-loader.mjs", import.meta.url));

const { reflectSource } = await import("@vgpu/wgsl/runtime");
const registry = await import("../packages/effect-core/src/effects/registry.ts");
const catalog = registry.catalog;
if (!Array.isArray(catalog) || catalog.length === 0) {
  throw new Error("effect-core registry catalog is empty or not exported");
}

// Byte-identical to the vertex stage vgpu's effect() prepends when the source
// has no @vertex entry (node_modules/vgpu/dist/effect.js fullscreenSource).
const VERTEX_STAGE = `
struct VgpuFullscreenVertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};
@vertex fn vgpu_fullscreen_vs(@builtin(vertex_index) vi: u32) -> VgpuFullscreenVertexOut {
  var pos = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  var uv = array<vec2f, 3>(vec2f(0.0, 1.0), vec2f(2.0, 1.0), vec2f(0.0, -1.0));
  var out: VgpuFullscreenVertexOut;
  out.position = vec4f(pos[vi], 0.0, 1.0);
  out.uv = uv[vi];
  return out;
}
`;

const EXPECTED_BINDINGS = { src: ["texture", 0], samp: ["sampler", 1], params: ["buffer", 2] };
const SCALAR_KIND = { f32: "f32", i32: "i32", u32: "u32" };

function fieldKind(effectId, fieldName, type) {
  if (type.kind === "scalar") {
    const k = SCALAR_KIND[type.name];
    if (k) return k;
  } else if (type.kind === "vector") {
    const s = SCALAR_KIND[type.element?.name];
    if (s) return `vec${type.width}${s[0]}`;
  }
  throw new Error(
    `${effectId}: uniform field '${fieldName}' has unsupported type ${JSON.stringify(type)}; ` +
      "extend fieldKind() in scripts/export-effects.mjs and the packer in bmf-demo/vgpu_fx_gpu.py",
  );
}

// --- (values, ctx) -> uniform field mapping, detected with sentinel inputs ---

const PARAM_SENT_BASE = 2001; // param i gets 2001 + 2*i
const CTX_SCALAR_SENT = { time: 101, deltaTime: 102, videoTime: 103, videoDuration: 104 };
const CTX_VEC_SENT = { resolution: [1111, 1112], texel: [1121, 1122], videoSize: [1131, 1132] };

function sentinelInputs(def, videoDuration) {
  const values = {};
  def.params.forEach((p, i) => {
    values[p.key] = PARAM_SENT_BASE + 2 * i;
  });
  return {
    values,
    ctx: {
      time: CTX_SCALAR_SENT.time,
      deltaTime: CTX_SCALAR_SENT.deltaTime,
      videoTime: CTX_SCALAR_SENT.videoTime,
      videoDuration,
      resolution: [...CTX_VEC_SENT.resolution],
      texel: [...CTX_VEC_SENT.texel],
      videoSize: [...CTX_VEC_SENT.videoSize],
    },
  };
}

function isSeq(v) {
  return Array.isArray(v) || ArrayBuffer.isView(v);
}

function sameVal(a, b) {
  if (isSeq(a) || isSeq(b)) {
    if (!isSeq(a) || !isSeq(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i += 1) if (a[i] !== b[i]) return false;
    return true;
  }
  return a === b;
}

/**
 * Evaluates uniforms() twice — videoDuration = sentinel and 0 — and matches
 * every uniform field against the sentinels. The only conditional expression
 * in the catalog today is `videoDuration > 0 ? videoTime : time`, which shows
 * up as videoTime-sentinel in run A and time-sentinel in run B. Anything else
 * fails loudly so a new effect with real logic cannot silently mis-export.
 */
function detectMapping(def, fields) {
  const runA = sentinelInputs(def, CTX_SCALAR_SENT.videoDuration);
  const runB = sentinelInputs(def, 0);
  const outA = def.uniforms(runA.values, runA.ctx).params ?? {};
  const outB = def.uniforms(runB.values, runB.ctx).params ?? {};
  const mapping = {};
  for (const field of fields) {
    const { name } = field;
    const vA = outA[name];
    const vB = outB[name];
    if (vA === undefined && vB === undefined) {
      mapping[name] = ["zero"];
      continue;
    }
    let hit = null;
    def.params.forEach((p, i) => {
      const s = PARAM_SENT_BASE + 2 * i;
      if (!hit && sameVal(vA, s) && sameVal(vB, s)) hit = ["param", p.key];
    });
    if (!hit) {
      for (const [k, s] of Object.entries(CTX_SCALAR_SENT)) {
        if (k === "videoDuration") continue;
        if (sameVal(vA, s) && sameVal(vB, s)) {
          hit = ["ctx", k];
          break;
        }
      }
    }
    if (!hit && vA === CTX_SCALAR_SENT.videoDuration && vB === 0) hit = ["ctx", "videoDuration"];
    if (!hit && vA === CTX_SCALAR_SENT.videoTime && vB === CTX_SCALAR_SENT.time) hit = ["ctx", "videoTimeOrTime"];
    if (!hit) {
      for (const [k, s] of Object.entries(CTX_VEC_SENT)) {
        if (sameVal(vA, s) && sameVal(vB, s)) {
          hit = ["ctx", k];
          break;
        }
      }
    }
    if (!hit) {
      throw new Error(
        `${def.id}: cannot auto-map uniform field '${name}' ` +
          `(sentinel outputs ${JSON.stringify(vA)} / ${JSON.stringify(vB)}); ` +
          "the effect's uniforms() has logic this exporter does not know — extend detectMapping()",
      );
    }
    mapping[name] = hit;
  }
  return mapping;
}

function exportEffect(def) {
  const source = def.shader?.wgsl;
  if (typeof source !== "string" || !source) {
    throw new Error(`${def.id}: def.shader.wgsl missing — the wgsl export loader did not run`);
  }
  const wgsl = VERTEX_STAGE + source;
  const ref = reflectSource(wgsl, `${def.id}.wgsl`);

  const vertexEntries = ref.entryPoints.filter((e) => e.stage === "vertex");
  if (vertexEntries.length !== 1 || vertexEntries[0].name !== "vgpu_fullscreen_vs") {
    throw new Error(`${def.id}: unexpected vertex entries ${JSON.stringify(vertexEntries)}; exporter assumes fragment-only effects`);
  }
  if (!ref.entryPoints.some((e) => e.stage === "fragment" && e.name === "fs_main")) {
    throw new Error(`${def.id}: no @fragment fs_main entry point`);
  }
  for (const [name, [kind, binding]] of Object.entries(EXPECTED_BINDINGS)) {
    const b = ref.bindings.find((x) => x.name === name);
    if (!b || b.kind !== kind || b.group !== 0 || b.binding !== binding) {
      throw new Error(`${def.id}: binding '${name}' expected group0/binding${binding}/${kind}, got ${JSON.stringify(b)}`);
    }
  }

  const paramsBinding = ref.bindings.find((x) => x.name === "params");
  const layout = paramsBinding.layout;
  if (!layout?.members || !Number.isInteger(layout.size) || layout.size <= 0 || layout.size % 4 !== 0) {
    throw new Error(`${def.id}: params has no static uniform layout (${JSON.stringify(layout?.size)})`);
  }
  const fields = layout.members.map((m) => ({ name: m.name, offset: m.offset, kind: fieldKind(def.id, m.name, m.type) }));

  return {
    wgsl,
    entry: {
      id: def.id,
      name: def.name,
      category: def.category,
      description: def.description,
      params: def.params,
      defaults: Object.fromEntries(def.params.map((p) => [p.key, p.default])),
      wgsl: `${def.id}.wgsl`,
      uniformSize: layout.size,
      fields,
      mapping: detectMapping(def, fields),
    },
  };
}

const entries = [];
const files = new Map();
for (const def of catalog) {
  const { wgsl, entry } = exportEffect(def);
  entries.push(entry);
  files.set(entry.wgsl, wgsl);
  console.log(
    `${DRY ? "[dry] " : ""}${entry.id.padEnd(16)} uniform ${String(entry.uniformSize).padStart(3)}B, ` +
      `${entry.fields.length} fields, ${Object.keys(entry.mapping).length} mapped`,
  );
}

const manifest = {
  version: 1,
  generator: "scripts/export-effects.mjs",
  vertexEntry: "vgpu_fullscreen_vs",
  fragmentEntry: "fs_main",
  format: "rgba8unorm",
  clearColor: [0, 0, 0, 1],
  effects: entries,
};

if (DRY) {
  console.log(`[dry] ${entries.length} effects validated; nothing written`);
} else {
  mkdirSync(OUT_DIR, { recursive: true });
  for (const [name, text] of files) writeFileSync(join(OUT_DIR, name), text);
  writeFileSync(join(OUT_DIR, "effects.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`wrote ${files.size} shaders + effects.json (${entries.length} effects) -> ${OUT_DIR}`);
}
