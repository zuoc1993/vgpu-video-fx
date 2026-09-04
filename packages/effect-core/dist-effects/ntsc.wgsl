
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/ntsc/effect.wgsl
struct _vgsl_71be2916__Params {
  noise: f32,
  scanlines: f32,
  burst: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_71be2916__Params;

fn _vgsl_71be2916__sampleAt(uv: vec2f) -> vec3f {
  return textureSampleLevel(src, samp, vec2f(fract(uv.x), clamp(uv.y, 0.0, 1.0)), 0.0).rgb;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // 4:2:0-ish chroma sampling: R / B read ~3px off from G.
  let line = floor(v.y * params.resolution.y);
  let off = 3.0 / params.resolution.x;
  var col = _vgsl_71be2916__sampleAt(v);
  col.r = mix(col.r, _vgsl_71be2916__sampleAt(v + vec2f(off, 0.0)).r, params.burst);
  col.b = mix(col.b, _vgsl_71be2916__sampleAt(v - vec2f(off, 0.0)).b, params.burst);
  // Rolling NTSC color burst shimmer per line.
  let phase = _vgsl_9a0b5690__hash1(f32(line)) * 0.35 + v.x * 6.2831853;
  col = _vgsl_95d6fc5a__hueRotate(col, params.burst * 0.22 * phase);
  // Additive signal noise + dark scanline comb.
  let nz = (_vgsl_9a0b5690__hash1(v.x * 671.0 + v.y * 419.0) - 0.5) * params.noise * 0.5;
  col = vec3f(clamp(col.r + nz, 0.0, 1.0), clamp(col.g + nz, 0.0, 1.0), clamp(col.b + nz, 0.0, 1.0));
  let dark = step(0.5, fract(line * 0.5)) * params.scanlines * 0.3;
  col *= 1.0 - dark;
  return vec4f(col, 1.0);
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











// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
fn _vgsl_9a0b5690__hashU32(value: u32) -> u32 {
  var hashed = value;
  hashed = (hashed ^ (hashed >> 16u)) * 0x7feb352du;
  hashed = (hashed ^ (hashed >> 15u)) * 0x846ca68bu;
  hashed = hashed ^ (hashed >> 16u);
  return hashed;
}





fn _vgsl_9a0b5690__unitFloat(hash: u32) -> f32 {
  return f32(hash >> 8u) * (1.0 / 16777216.0);
}

fn _vgsl_9a0b5690__hash1(seed: f32) -> f32 {
  return _vgsl_9a0b5690__unitFloat(_vgsl_9a0b5690__hashU32(bitcast<u32>(seed)));
}





// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     



// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.




// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.


// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.


// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.


// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
fn _vgsl_95d6fc5a__hueRotate(c: vec3f, t: f32) -> vec3f {
  let a = t * 6.2831853;
  let ca = cos(a);
  let sa = sin(a);
  let m = mat3x3(
    0.299 + 0.701 * ca + 0.168 * sa, 0.587 - 0.587 * ca + 0.330 * sa, 0.114 - 0.114 * ca - 0.497 * sa,
    0.299 - 0.299 * ca - 0.328 * sa, 0.587 + 0.413 * ca + 0.035 * sa, 0.114 - 0.114 * ca + 0.292 * sa,
    0.299 - 0.300 * ca + 1.250 * sa, 0.587 - 0.588 * ca - 1.050 * sa, 0.114 + 0.886 * ca - 0.203 * sa,
  );
  return m * c;
}

// Stable random offset per cell row, driven by an integer tick.

