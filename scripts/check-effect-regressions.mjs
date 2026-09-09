// Focused regression checks for the bugs fixed in the effect review.
// Runs on the Node/Dawn EffectEngine; cheap (small frames).
import { register } from "node:module";
import { fileURLToPath } from "node:url";
import { init } from "vgpu/node";
import { resolveShader } from "@vgpu/wgsl/runtime";

register(new URL("./wgsl-export-loader.mjs", import.meta.url));
const { EffectEngine } = await import("../packages/effect-core/src/engine.ts");

const W = 64;
const H = 48;
const gpu = await init();
const engine = await EffectEngine.create({ gpu });

function solid(r, g, b) {
  const data = new Uint8Array(W * H * 4);
  for (let i = 0; i < data.length; i += 4) {
    data[i] = r;
    data[i + 1] = g;
    data[i + 2] = b;
    data[i + 3] = 255;
  }
  return data;
}
function stepFrame() {
  const data = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y += 1) {
    for (let x = 0; x < W; x += 1) {
      const v = x < W / 2 ? 0 : 255;
      const i = (y * W + x) * 4;
      data[i] = v;
      data[i + 1] = v;
      data[i + 2] = v;
      data[i + 3] = 255;
    }
  }
  return data;
}
function rings() {
  const data = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y += 1) {
    for (let x = 0; x < W; x += 1) {
      const dx = (x + 0.5) / W - 0.5;
      const dy = (y + 0.5) / H - 0.5;
      const r = Math.hypot(dx, dy);
      const v = Math.round(255 * (0.5 + 0.5 * Math.sin(r * 80)));
      const i = (y * W + x) * 4;
      data[i] = v;
      data[i + 1] = v;
      data[i + 2] = v;
      data[i + 3] = 255;
    }
  }
  return data;
}
async function render(effect, params, data, time = 0.4, videoTime = 0.4, videoDuration = 6.7) {
  return engine.render({
    effect,
    params,
    time,
    videoTime,
    videoDuration,
    frame: { width: W, height: H, data, time },
  });
}
function meanAbsDiff(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i += 4) {
    sum += Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]);
  }
  return sum / ((a.length / 4) * 3);
}
function maxChannel(data) {
  let max = 0;
  for (let i = 0; i < data.length; i += 4) max = Math.max(max, data[i], data[i + 1], data[i + 2]);
  return max;
}
function minChannel(data) {
  let min = 255;
  for (let i = 0; i < data.length; i += 4) min = Math.min(min, data[i], data[i + 1], data[i + 2]);
  return min;
}
function assert(cond, message) {
  if (!cond) throw new Error(`regression: ${message}`);
}
function assertNear(actual, expected, tol, message) {
  assert(Math.abs(actual - expected) <= tol, `${message}: ${actual} vs ${expected} (tol ${tol})`);
}

// 1. Sobel must not draw a false white frame on a uniform image.
{
  const out = await render("sobel", { threshold: 0.12, gain: 1.4 }, solid(128, 128, 128));
  assert(maxChannel(out.data) <= 2, `sobel uniform frame has edge artifact (max ${maxChannel(out.data)})`);
}

// 2. Grade's gain=1 must be neutral.
{
  const out = await render("grade", { lift: 0, gamma: 1, gain: 1, saturation: 1 }, solid(128, 128, 128));
  for (let i = 0; i < out.data.length; i += 4) {
    assertNear(out.data[i], 128, 1, "grade neutral R");
    assertNear(out.data[i + 1], 128, 1, "grade neutral G");
    assertNear(out.data[i + 2], 128, 1, "grade neutral B");
  }
}

// 3. rgbsplit0r: R and B must move in opposite directions, not collapse.
{
  const out = await render("rgbsplit0r", { horizontal: 0.9, vertical: 0.9 }, stepFrame());
  const edge = (channel) => {
    const y = (H >> 1) * W;
    for (let x = 0; x < W; x += 1) if (out.data[(y + x) * 4 + channel] > 128) return x;
    return -1;
  };
  const r = edge(0);
  const g = edge(1);
  const b = edge(2);
  assert(r >= 0 && g >= 0 && b >= 0, "rgbsplit0r missing channel edges");
  assert(r < g && g < b, `rgbsplit0r axes collapsed: R=${r} G=${g} B=${b}`);
}

// 4. kaleid0sc0pe zoom must actually scale (it used to cancel out).
{
  const src = rings();
  const a = (await render("kaleid0sc0pe", { segs: 6, zoom: 0.5, speed: 0.25, twist: 0 }, src)).data;
  const b = (await render("kaleid0sc0pe", { segs: 6, zoom: 1.6, speed: 0.25, twist: 0 }, src)).data;
  assert(meanAbsDiff(a, b) > 20, `kaleid0sc0pe zoom has no effect (MAE ${meanAbsDiff(a, b)})`);
}

// 5. dust-bokeh must be visible at default opacity (was effectively a no-op).
{
  const out = await render("dust-bokeh", engine.defaults("dust-bokeh"), solid(128, 128, 128));
  assert(maxChannel(out.data) - 128 >= 10, `dust-bokeh invisible (max delta ${maxChannel(out.data) - 128})`);
}

// 6. dissolve default must burn away and loop without a hard reset.
{
  const white = solid(255, 255, 255);
  const start = await render("dissolve", engine.defaults("dissolve"), white, 0);
  const mid = await render("dissolve", engine.defaults("dissolve"), white, 2.0);
  const back = await render("dissolve", engine.defaults("dissolve"), white, 4.0);
  const bright = (data) => {
    let n = 0;
    for (let i = 0; i < data.length; i += 4) if (data[i] > 245) n += 1;
    return n / (W * H);
  };
  assert(bright(start.data) > 0.95, "dissolve default should start with the picture visible");
  assert(bright(mid.data) < 0.05, "dissolve default should burn the picture away at t=1");
  assert(bright(back.data) > 0.95, "dissolve loop should return smoothly, not snap to black");
}

// 7. Zoom defaults must cover the frame (no black border).
for (const id of ["zoom-in", "zoom-out"]) {
  const color = solid(180, 120, 80);
  for (const time of [0, 0.5, 1.0]) {
    const out = await render(id, engine.defaults(id), color, time, time, 6.7);
    assert(minChannel(out.data) > 0, `${id} default exposes a black border at t=${time}`);
  }
}

// 8. camera-shake's zoom-to-hide-border must cover the translation.
{
  const color = solid(180, 120, 80);
  for (const time of [0.13, 0.37, 0.71, 1.23]) {
    const out = await render("camera-shake", engine.defaults("camera-shake"), color, time, time, 6.7);
    assert(minChannel(out.data) > 0, `camera-shake exposes a black border at t=${time}`);
  }
}

// 9. hueRotate must use the column-major matrix (catches the transpose).
{
  const resolved = await resolveShader({
    entry: fileURLToPath(new URL("./fixtures/hue-rotate.wgsl", import.meta.url)),
    validate: "require",
  });
  const hueDef = {
    id: "hue-regression",
    name: "hue-regression",
    category: "test",
    description: "",
    params: [{ key: "amount", label: "amount", type: "range", min: 0, max: 1, step: 0.01, default: 0.1 }],
    shader: { version: 1, wgsl: resolved.wgsl },
    uniforms(values, ctx) {
      return { params: { amount: values.amount, resolution: ctx.resolution, videoSize: ctx.videoSize } };
    },
  };
  const hueEngine = await EffectEngine.create({ gpu, catalog: [hueDef] });
  const input = new Uint8Array([0, 217, 242, 255]); // (0, 0.85, 0.95)
  const out = await hueEngine.render({
    effect: "hue-regression",
    params: { amount: 0.1 },
    frame: { width: 1, height: 1, data: input },
  });
  // Row-major Rec.601 rotation at 0.1 turns: (0.0033, 0.9842, 0.2459).
  assertNear(out.data[0], 1, 2, "hueRotate R");
  assertNear(out.data[1], 251, 2, "hueRotate G");
  assertNear(out.data[2], 63, 2, "hueRotate B");
  hueEngine.dispose();
}

// 10. glow threshold must be a real bright-pass: dark input stays dark.
{
  const out = await render("glow", { blur: 9, amount: 1.1, threshold: 0.5 }, solid(64, 64, 64));
  assert(maxChannel(out.data) <= 70, `glow leaks into dark areas (max ${maxChannel(out.data)})`);
}

// 11. defish0r default (Defish) must not leave a black vignette.
{
  const out = await render("defish0r", engine.defaults("defish0r"), solid(180, 120, 80));
  assert(minChannel(out.data) > 0, "defish0r default exposes a black border");
}

console.log("ok effect regressions");
engine.dispose();
gpu.dispose();
