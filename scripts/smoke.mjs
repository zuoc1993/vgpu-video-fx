import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveShader } from "@vgpu/wgsl/runtime";
import { init } from "vgpu/node";
import { EffectEngine } from "../packages/effect-core/src/engine.ts";

const root = path.join(fileURLToPath(new URL(".", import.meta.url)), "..");
const effectsDir = path.join(root, "packages/effect-core/src/effects");

const cases = {
  none: {},
  "camera-shake": { intensity: 0.5, speed: 1, frequency: 12 },
  glitch: { intensity: 0.7, speed: 1, slices: 16, rgbSplit: 1, block: 0.5, scanline: 0.2 },
  "handheld-cam": { intensity: 0.7, speed: 1, zoom: 0.1, sway: 1, glow: 0.4, blur: 1 },
  "local-push": { intensity: 0.7, speed: 1, zoom: 0.4, glow: 0.4, chromatic: 0.6, distortion: 0.3, centerX: 0.5, centerY: 0.5 },
  "screen-shake": { intensity: 0.7, speed: 1, punch: 0.8, blur: 0.6 },
  "zoom-in": { startScale: 0.5, endScale: 0.7, duration: 1, looping: 1 },
  "zoom-out": { startScale: 0.7, endScale: 0.5, duration: 1, looping: 1 },
};

const ids = readdirSync(effectsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && entry.name !== "shared")
  .map((entry) => entry.name)
  .sort();

for (const id of ids) {
  if (!(id in cases)) throw new Error(`smoke missing params for ${id}`);
}

const size = 32;
const data = new Uint8Array(size * size * 4);
for (let i = 0; i < data.length; i += 4) {
  data[i] = 51;
  data[i + 1] = 153;
  data[i + 2] = 230;
  data[i + 3] = 255;
}

let gpuError;
const catalog = [];
for (const id of ids) {
  const entry = existsSync(path.join(effectsDir, id, "effect.wgsl"))
    ? path.join(effectsDir, id, "effect.wgsl")
    : path.join(effectsDir, "zoom-in", "effect.wgsl");
  const resolved = await resolveShader({ entry, validate: "require" });
  const fixed = cases[id];
  catalog.push({
    id,
    name: id,
    category: "test",
    description: "",
    params: [],
    shader: { version: 1, wgsl: resolved.wgsl },
    uniforms(_values, ctx) {
      return {
        params: {
          ...fixed,
          time: ctx.time,
          videoTime: ctx.videoTime,
          resolution: ctx.resolution,
          videoSize: ctx.videoSize,
        },
      };
    },
  });
}

const gpu = await init();
const engine = await EffectEngine.create({
  gpu,
  catalog,
  onError: (error) => {
    gpuError = error;
  },
});

const none = await engine.render({
  effect: "none",
  time: 0,
  frame: { width: size, height: size, data },
});
if (gpuError) throw gpuError;
assertNear(none.data, data, "none identity");

const batch = await engine.renderBatch({
  effect: "none",
  frames: [
    { width: size, height: size, data, time: 0 },
    { width: size, height: size, data, time: 0.1 },
    { width: size, height: size, data, time: 0.2 },
  ],
});
if (gpuError) throw gpuError;
if (batch.length !== 3) throw new Error(`batch length ${batch.length}`);
for (const frame of batch) assertNear(frame.data, data, "none batch");

for (const id of ids) {
  if (id === "none") continue;
  const out = await engine.render({
    effect: id,
    time: 0.3,
    videoTime: 0.4,
    frame: { width: size, height: size, data },
  });
  if (gpuError) throw gpuError;
  const center = (16 * size + 16) * 4;
  if (out.data[center + 3] === 0) throw new Error(`${id} wrote a transparent center`);
  console.log(`ok ${id}`);
}

console.log("ok none");
engine.dispose();
gpu.dispose();
console.log("smoke ok: EffectEngine rendered every catalog shader");

function assertNear(actual, expected, label) {
  if (actual.length < expected.length) throw new Error(`${label}: short read`);
  let max = 0;
  for (let i = 0; i < expected.length; i += 1) {
    const delta = Math.abs(actual[i] - expected[i]);
    if (delta > max) max = delta;
  }
  // Official pixelDiff note: maxByte <= 2 is driver rounding.
  if (max > 2) throw new Error(`${label}: maxByte ${max}`);
}
