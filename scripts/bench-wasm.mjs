// Benchmark the wasm binding at several resolutions (no canvas overhead).
import fs from "node:fs";
import init, { render } from "../effect-rs/pkg/effect_rs.js";

const wasmBytes = fs.readFileSync("./effect-rs/pkg/effect_rs_bg.wasm");
await init(wasmBytes);

const SIZES = [
  [1664, 1080],
  [1280, 720],
  [960, 540],
  [720, 405],
];
const EFFECTS = ["none", "posterize", "rgbsplit0r", "glitch", "glow"];
const FRAMES = 5;

function makeFrame(w, h) {
  const src = new Uint8Array(w * h * 4);
  for (let i = 0; i < src.length; i += 4) {
    src[i] = (i * 7) & 255;
    src[i + 1] = (i * 13) & 255;
    src[i + 2] = (i * 31) & 255;
    src[i + 3] = 255;
  }
  return src;
}

for (const [w, h] of SIZES) {
  const src = makeFrame(w, h);
  for (const fx of EFFECTS) {
    render(fx, null, 0.5, 0, 0.5, 3, src, w, h, w, h); // warmup
    const t0 = performance.now();
    for (let i = 0; i < FRAMES; i += 1) render(fx, null, 0.5, 0, 0.5, 3, src, w, h, w, h);
    const ms = (performance.now() - t0) / FRAMES;
    console.log(`${w}x${h} ${fx.padEnd(12)} ${ms.toFixed(1)} ms/frame  (${(1000 / ms).toFixed(0)} fps)`);
  }
  console.log("");
}
