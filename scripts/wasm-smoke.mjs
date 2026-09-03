// Node smoke test for the wasm binding (no browser needed).
import fs from "node:fs";
import init, { catalog, defaults, render } from "../effect-rs/pkg/effect_rs.js";

const wasmBytes = fs.readFileSync("./effect-rs/pkg/effect_rs_bg.wasm"); // cwd = repo root
await init(wasmBytes);

const meta = catalog();
console.log("wasm catalog:", meta.map((e) => e.id).join(","));

const w = 320;
const h = 180;
const src = new Uint8Array(w * h * 4);
for (let y = 0; y < h; y += 1) {
  for (let x = 0; x < w; x += 1) {
    const i = (y * w + x) * 4;
    src[i] = (x * 255) / w;
    src[i + 1] = (y * 255) / h;
    src[i + 2] = ((x + y) * 255) / (w + h);
    src[i + 3] = 255;
  }
}
const none = render("none", null, 0, 0, 0, 0, src, w, h, w, h);
console.log("none copies:", none.length === src.length && none.every((v, i) => v === src[i]));
const glitch = render("glitch", { intensity: 0.7, speed: 1.4, slices: 28, rgbSplit: 1, block: 0.8, scanline: 0.35 }, 0.5, 0.02, 0.5, 3, src, w, h, w, h);
const diff = glitch.reduce((acc, v, i) => acc + (v !== src[i] ? 1 : 0), 0);
console.log("glitch out len:", glitch.length, "changed pixels:", diff);
console.log("defaults glitch:", JSON.stringify(defaults("glitch")));
// letterbox: out smaller than src (containUv path)
const letter = render("glitch", null, 0.5, 0, 0.5, 3, src, w, h, 320, 120);
console.log("letterbox out len:", letter.length, "expect", 320 * 120 * 4);
