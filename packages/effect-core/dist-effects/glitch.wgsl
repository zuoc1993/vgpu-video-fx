
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/glitch/effect.wgsl
struct _vgsl_a320306a__Params {
  time: f32,
  intensity: f32,
  speed: f32,
  slices: f32,
  rgbSplit: f32,
  block: f32,
  scanline: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_a320306a__Params;

fn _vgsl_a320306a__sampleGlitch(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  return textureSampleLevel(src, samp, vec2f(fract(uv.x), clamp(uv.y, 0.0, 1.0)), 0.0);
}

// Magenta / lemon / cyan first — matches the reference columns.
fn _vgsl_a320306a__glitchTint(h: vec2f) -> vec3f {
  let i = u32(h.x * 6.0);
  if (i == 0u) { return vec3f(1.0, 0.08, 0.72); }
  if (i == 1u) { return vec3f(1.0, 0.95, 0.32); }
  if (i == 2u) { return vec3f(0.08, 0.95, 1.0); }
  if (i == 3u) { return vec3f(0.25, 1.0, 0.28); }
  if (i == 4u) { return vec3f(1.0, 0.22, 0.42); }
  return vec3f(0.22, 0.06, 0.82);
}

fn _vgsl_a320306a__wash(base: vec3f, tint: vec3f, amt: f32) -> vec3f {
  return mix(base, base * tint * 1.35 + tint * 0.22, clamp(amt, 0.0, 1.0));
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  var vuv = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (vuv.x < 0.0 || vuv.x > 1.0 || vuv.y < 0.0 || vuv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }

  let tick = floor(params.time * params.speed * 22.0);
  let burst = _vgsl_9a0b5690__hash2(vec2f(tick, 0.7)).x;
  let on = step(0.35, burst) * params.intensity;
  let cover = step(0.001, on) * mix(0.4, 0.78, clamp(on, 0.0, 1.0)) * clamp(params.block * 0.65 + 0.35, 0.0, 1.2);

  let row = floor(vuv.y * max(params.slices, 4.0));
  let sliceN = _vgsl_9a0b5690__hash2(vec2f(row, tick));
  vuv.x += (sliceN.x - 0.5) * 0.42 * on;
  vuv.x += (_vgsl_9a0b5690__hash2(vec2f(floor(vuv.y * 240.0), tick)).x - 0.5) * 0.08 * on;

  let blockN = _vgsl_9a0b5690__hash2(floor(vuv * vec2f(14.0, 8.0)) + vec2f(tick, 4.2));
  if (blockN.x > 1.0 - params.block * 0.22 * on) {
    vuv += (blockN - vec2f(0.5)) * 0.12 * on;
  }

  let split = params.rgbSplit * on * 0.05;
  let r = _vgsl_a320306a__sampleGlitch(src, samp, vuv + vec2f(split, 0.0)).r;
  let g = _vgsl_a320306a__sampleGlitch(src, samp, vuv + vec2f(-split * 0.35, split * 0.15)).g;
  let b = _vgsl_a320306a__sampleGlitch(src, samp, vuv - vec2f(split, 0.0)).b;
  var color = vec3f(r, g, b);
  color = mix(color, color.brg, 0.22 * on);

  let scan = 0.5 + 0.5 * sin(vuv.y * params.resolution.y * 3.14159);
  color *= 1.0 - params.scanline * 0.45 * scan;
  color *= 1.0 + 0.7 * on;

  let cols = 3.0;
  let col = floor(vuv.x * cols);
  let colH = _vgsl_9a0b5690__hash2(vec2f(col + 0.37, tick));
  color = _vgsl_a320306a__wash(color, _vgsl_a320306a__glitchTint(colH), cover);

  let rectH = _vgsl_9a0b5690__hash2(vec2f(tick, 8.1));
  let rx = rectH.x * 0.4;
  let ry = rectH.y * 0.35;
  if (vuv.x > rx && vuv.x < rx + 0.28 + rectH.x * 0.3 && vuv.y > ry && vuv.y < ry + 0.2 + rectH.y * 0.25) {
    color = _vgsl_a320306a__wash(color, _vgsl_a320306a__glitchTint(rectH + vec2f(0.2, 0.1)), cover * 0.85);
  }

  let edge = _vgsl_9a0b5690__hash2(vec2f(tick, 2.2));
  if (vuv.x > 0.86 && edge.x > 0.35) {
    color = _vgsl_a320306a__wash(color, vec3f(0.2, 0.05, 0.78), cover * 0.7);
  }

  let line = floor(vuv.y * 96.0);
  let lineH = _vgsl_9a0b5690__hash2(vec2f(line, tick + 5.0));
  if (lineH.x > 0.93) {
    color = _vgsl_a320306a__wash(color, _vgsl_a320306a__glitchTint(lineH), cover * 0.9);
  }

  color = min(color, vec3f(1.7));
  return vec4f(color, 1.0);
}

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector


fn _vgsl_9a0b5690__pcg2d(value: vec2u) -> vec2u {
  // 2D multi-output variant cross-mixes with the LCG multiplier instead of pcg3d's y*z pattern.
  var hashed = value * 1664525u + 1013904223u;
  hashed.x = hashed.x + hashed.y * 1664525u;
  hashed.y = hashed.y + hashed.x * 1664525u;
  hashed = hashed ^ (hashed >> vec2u(16u));
  hashed.x = hashed.x + hashed.y * 1664525u;
  hashed.y = hashed.y + hashed.x * 1664525u;
  hashed = hashed ^ (hashed >> vec2u(16u));
  return hashed;
}



fn _vgsl_9a0b5690__unitFloat(hash: u32) -> f32 {
  return f32(hash >> 8u) * (1.0 / 16777216.0);
}



fn _vgsl_9a0b5690__hash2(seed: vec2f) -> vec2f {
  let hashed = _vgsl_9a0b5690__pcg2d(bitcast<vec2u>(seed));
  return vec2f(_vgsl_9a0b5690__unitFloat(hashed.x), _vgsl_9a0b5690__unitFloat(hashed.y));
}



// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/shared/video.wgsl
// Pure helpers: no @group/@binding. Entry shaders own resources.

fn _vgsl_35d1d59a__containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
  let canvasSafe = max(canvas, vec2f(1.0));
  let videoSafe = max(video, vec2f(1.0));
  let canvasAspect = canvasSafe.x / canvasSafe.y;
  let videoAspect = videoSafe.x / videoSafe.y;
  var scale = vec2f(1.0);
  if (canvasAspect > videoAspect) {
    scale.x = videoAspect / canvasAspect;
  } else {
    scale.y = canvasAspect / videoAspect;
  }
  return (uv - vec2f(0.5)) / scale + vec2f(0.5);
}










