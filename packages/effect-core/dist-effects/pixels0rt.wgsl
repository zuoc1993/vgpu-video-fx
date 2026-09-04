
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/pixels0rt/effect.wgsl
struct _vgsl_df624b96__Params {
  width: f32,
  strength: f32,
  threshold: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_df624b96__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // ponytail: strip-max smear stands in for a real sort network (single-pass
  // cost ceiling); per-strip brightest row pulled across the strip.
  let wpx = max(mix(4.0, 48.0, params.width), 2.0);
  let strip = floor(v.x * params.resolution.x / wpx);
  let cx = (strip + 0.5) * wpx / params.resolution.x;
  var bestLum = -1.0;
  var bestCol = vec3f(0.0);
  for (var i = 0u; i < 8u; i += 1u) {
    let yy = (f32(i) + 0.5) / 8.0;
    let c = _vgsl_35d1d59a__sampleVideo(src, samp, vec2f(cx, yy)).rgb;
    let l = _vgsl_95d6fc5a__lumOf(c);
    if (l > bestLum) {
      bestLum = l;
      bestCol = c;
    }
  }
  let streak = step(params.threshold, bestLum) * params.strength;
  let col = _vgsl_35d1d59a__sampleVideo(src, samp, v).rgb;
  return vec4f(mix(col, bestCol, streak), 1.0);
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

fn _vgsl_35d1d59a__sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}









// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     

fn _vgsl_95d6fc5a__lumOf(c: vec3f) -> f32 {
  return dot(c, vec3f(0.2126, 0.7152, 0.0722));
}

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.




// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.


// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.


// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.


// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.


// Stable random offset per cell row, driven by an integer tick.


// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector













