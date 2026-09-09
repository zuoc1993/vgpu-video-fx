
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/screen-shake/effect.wgsl
struct _vgsl_0c66bf17__Params {
  time: f32,
  intensity: f32,
  speed: f32,
  punch: f32,
  blur: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_0c66bf17__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let cell = floor(params.time * params.speed * 20.0);
  let n = _vgsl_aa51502b__hash2(vec2f(cell, 3.3)) - vec2f(0.5);
  let hit = pow(abs(sin(params.time * params.speed * 6.4)), 1.6);
  let offset = n * 0.1 * params.intensity;
  // The punch zoom must also cover the translation; otherwise the shake
  // exposes black borders on the opposite side.
  let zoom = max(1.0 + abs(n.x) * 0.22 * params.punch * params.intensity * hit,
                 1.0 + length(offset) * 1.5);
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  var vuv = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  vuv = _vgsl_17688d6e__zoomAtAspect(vuv + offset, zoom, vec2f(0.5), aspect);
  let dir = normalize(vec2f(0.85, -0.55) + n * 0.35) * params.blur * params.intensity * (0.02 + 0.09 * hit);
  return vec4f(_vgsl_17688d6e__directionalBlur(src, samp, vuv, dir), 1.0);
}

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

 

 fn _vgsl_aa51502b__hash2(seed: vec2f) -> vec2f {
  let hashed = _vgsl_aa51502b__pcg2d(bitcast<vec2u>(seed));
  return vec2f(_vgsl_aa51502b__unitFloat(hashed.x), _vgsl_aa51502b__unitFloat(hashed.y));
}

 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/video.wgsl
// Pure helpers: no @group/@binding. Entry shaders own resources.

 fn _vgsl_17688d6e__containScale(canvas: vec2f, video: vec2f) -> vec2f {
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
  return scale;
}

 fn _vgsl_17688d6e__containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
  let scale = _vgsl_17688d6e__containScale(canvas, video);
  return (uv - vec2f(0.5)) / scale + vec2f(0.5);
}

// Step in video UV that corresponds to one output pixel, after containUv.
// Use this for source-space kernels (Sobel/emboss/glow) instead of 1/resolution,
// otherwise preview and offscreen renders diverge when the canvas aspect differs.
 

 

// Edge-clamped source sample for convolution/blur kernels: a uniform frame must
// not grow a false white border, and blur halos must not eat the video edges.
 fn _vgsl_17688d6e__sampleVideoClamp(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  return textureSampleLevel(src, samp, clamp(uv, vec2f(0.0), vec2f(1.0)), 0.0);
}

 

// Aspect-corrected rotation: uv is video UV, aspect = videoWidth / videoHeight.
 

// Aspect-corrected zoom: a circular magnification in pixel space, not an
// ellipse in UV space (which is what naive (uv-center)/zoom does on non-square video).
 fn _vgsl_17688d6e__zoomAtAspect(uv: vec2f, zoom: f32, center: vec2f, aspect: f32) -> vec2f {
  let p = (uv - center) * vec2f(aspect, 1.0);
  return center + p / max(zoom, 0.01) / vec2f(aspect, 1.0);
}

 fn _vgsl_17688d6e__directionalBlur(src: texture_2d<f32>, samp: sampler, uv: vec2f, dir: vec2f) -> vec3f {
  var acc = vec3f(0.0);
  for (var i = 0; i < 9; i += 1) {
    let k = (f32(i) / 8.0 - 0.5) * 2.0;
    acc += _vgsl_17688d6e__sampleVideoClamp(src, samp, uv + dir * k).rgb;
  }
  return acc / 9.0;
}
