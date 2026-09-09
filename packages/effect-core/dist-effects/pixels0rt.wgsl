
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/pixels0rt/effect.wgsl
struct _vgsl_20961bf2__Params {
  width: f32,
  strength: f32,
  threshold: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_20961bf2__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // ponytail: strip-max smear stands in for a real sort network (single-pass
  // cost ceiling); per-strip brightest row pulled across the strip.
  let wpx = max(mix(4.0, 48.0, params.width), 2.0);
  let strip = floor(v.x * params.videoSize.x / wpx);
  let cx = (strip + 0.5) * wpx / max(params.videoSize.x, 1.0);
  var bestLum = -1.0;
  var bestCol = vec3f(0.0);
  for (var i = 0u; i < 8u; i += 1u) {
    let yy = (f32(i) + 0.5) / 8.0;
    let c = _vgsl_17688d6e__sampleVideo(src, samp, vec2f(cx, yy)).rgb;
    let l = _vgsl_8e3019cf__lumOf(c);
    if (l > bestLum) {
      bestLum = l;
      bestCol = c;
    }
  }
  let streak = step(params.threshold, bestLum) * params.strength;
  let col = _vgsl_17688d6e__sampleVideo(src, samp, v).rgb;
  return vec4f(mix(col, bestCol, streak), 1.0);
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
 

 fn _vgsl_17688d6e__sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}

// Edge-clamped source sample for convolution/blur kernels: a uniform frame must
// not grow a false white border, and blur halos must not eat the video edges.
 

 

// Aspect-corrected rotation: uv is video UV, aspect = videoWidth / videoHeight.
 

// Aspect-corrected zoom: a circular magnification in pixel space, not an
// ellipse in UV space (which is what naive (uv-center)/zoom does on non-square video).
 

 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     

 fn _vgsl_8e3019cf__lumOf(c: vec3f) -> f32 {
  return dot(c, vec3f(0.2126, 0.7152, 0.0722));
}

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.


 

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
 

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
 

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
 

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
 

// Stable random offset per cell row, driven by an integer tick.
 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
 

 

 

 

 

 

 
