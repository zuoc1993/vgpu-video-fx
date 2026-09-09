
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/pixs0r/effect.wgsl
struct _vgsl_68d12023__Params {
  time: f32,
  intensity: f32,
  blockHeight: f32,
  columns: f32,
  speed: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_68d12023__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let tick = floor(params.time * params.speed * 10.0);
  // blockHeight = 0 selects the original pixs0r random-block mode.
  var bhPx = params.blockHeight;
  if (bhPx < 1.0) {
    bhPx = mix(2.0, 64.0, _vgsl_aa51502b__hash1(tick * 0.37 + 4.2));
  }
  bhPx = max(bhPx, 2.0);
  let row = floor(v.y * params.videoSize.y / bhPx);
  let h = _vgsl_aa51502b__hash3(vec3f(f32(row), tick, 0.0));

  var w = v;
  if (h.x < params.intensity * 0.5) {
    // Row slices glide sideways; occasionally a full row strips out.
    w.x = fract(w.x + (h.y - 0.5) * 0.22 * params.intensity);
  }
  // A second, independent grid shifts columns so the tear is not purely 1-D.
  let col = floor(v.x * params.videoSize.x / bhPx);
  let hc = _vgsl_aa51502b__hash3(vec3f(f32(col), tick, 7.0));
  if (hc.x < params.columns * 0.5) {
    w.x = fract(w.x + (hc.y - 0.5) * 0.12 * params.columns);
  }

  let c = textureSampleLevel(src, samp, vec2f(w.x, clamp(w.y, 0.0, 1.0)), 0.0).rgb;
  var result = c;
  if (h.z < params.intensity * 0.03) {
    result = result.brg; // rare hue flip slice
  }
  return vec4f(result, 1.0);
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
 

 

// Aspect-corrected rotation: uv is video UV, aspect = videoWidth / videoHeight.
 

// Aspect-corrected zoom: a circular magnification in pixel space, not an
// ellipse in UV space (which is what naive (uv-center)/zoom does on non-square video).
 

 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
 fn _vgsl_aa51502b__hashU32(value: u32) -> u32 {
  var hashed = value;
  hashed = (hashed ^ (hashed >> 16u)) * 0x7feb352du;
  hashed = (hashed ^ (hashed >> 15u)) * 0x846ca68bu;
  hashed = hashed ^ (hashed >> 16u);
  return hashed;
}

 

 fn _vgsl_aa51502b__pcg3d(value: vec3u) -> vec3u {
  var hashed = value * 1664525u + 1013904223u;
  hashed.x = hashed.x + hashed.y * hashed.z;
  hashed.y = hashed.y + hashed.z * hashed.x;
  hashed.z = hashed.z + hashed.x * hashed.y;
  hashed = hashed ^ (hashed >> vec3u(16u));
  hashed.x = hashed.x + hashed.y * hashed.z;
  hashed.y = hashed.y + hashed.z * hashed.x;
  hashed.z = hashed.z + hashed.x * hashed.y;
  hashed = hashed ^ (hashed >> vec3u(16u));
  return hashed;
}

 fn _vgsl_aa51502b__unitFloat(hash: u32) -> f32 {
  return f32(hash >> 8u) * (1.0 / 16777216.0);
}

 fn _vgsl_aa51502b__hash1(seed: f32) -> f32 {
  return _vgsl_aa51502b__unitFloat(_vgsl_aa51502b__hashU32(bitcast<u32>(seed)));
}

 

 fn _vgsl_aa51502b__hash3(seed: vec3f) -> vec3f {
  let hashed = _vgsl_aa51502b__pcg3d(bitcast<vec3u>(seed));
  return vec3f(_vgsl_aa51502b__unitFloat(hashed.x), _vgsl_aa51502b__unitFloat(hashed.y), _vgsl_aa51502b__unitFloat(hashed.z));
}
