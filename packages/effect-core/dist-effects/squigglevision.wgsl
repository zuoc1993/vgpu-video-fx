
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/squigglevision/effect.wgsl
struct _vgsl_dcd02091__Params {
  time: f32,
  strength: f32,
  fps: f32,
  scale: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_dcd02091__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let tick = floor(params.time * params.fps);
  let n = _vgsl_8e3019cf__vnoise2(v * params.scale + vec2f(tick * 0.113, tick * 0.071));
  return _vgsl_17688d6e__sampleVideo(src, samp, v + n * params.strength * 0.02);
}

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/video.wgsl
// Pure helpers: no @group/@binding. Entry shaders own resources.

 fn _vgsl_17688d6e__containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
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

 fn _vgsl_17688d6e__sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}

 

 

 

 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     

 

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.
fn _vgsl_8e3019cf__cornerNoise(cell: vec2i) -> vec2f {
  let q = _vgsl_aa51502b__pcg2d(bitcast<vec2u>(cell));
  return vec2f(_vgsl_aa51502b__unitFloat(q.x), _vgsl_aa51502b__unitFloat(q.y)) * 2.0 - 1.0;
}

 fn _vgsl_8e3019cf__vnoise2(p: vec2f) -> vec2f {
  let i = floor(p);
  let f = p - i;
  let u = f * f * (3.0 - 2.0 * f);
  let ic = vec2i(i);
  let a = _vgsl_8e3019cf__cornerNoise(ic);
  let b = _vgsl_8e3019cf__cornerNoise(ic + vec2i(1, 0));
  let c = _vgsl_8e3019cf__cornerNoise(ic + vec2i(0, 1));
  let d = _vgsl_8e3019cf__cornerNoise(ic + vec2i(1, 1));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
 

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
 

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
 

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
 

// Stable random offset per cell row, driven by an integer tick.
 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
 

 fn _vgsl_aa51502b__pcg2d(value: vec2u) -> vec2u {
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

 

 fn _vgsl_aa51502b__unitFloat(hash: u32) -> f32 {
  return f32(hash >> 8u) * (1.0 / 16777216.0);
}

 

 

 
