
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/colorhalftone/effect.wgsl
struct _vgsl_78d360fe__Params {
  dotRadius: f32,
  angC: f32,
  angM: f32,
  angY: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_78d360fe__Params;

const _vgsl_78d360fe__PI: f32 = 3.14159265;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // Physical aspect, not the output canvas aspect: the dots stay circular when
  // a 9:16 video is previewed on a 16:9 stage.
  let ar = params.videoSize.x / max(params.videoSize.y, 1.0);
  let p = vec2f(v.x * ar, v.y);
  // dotRadius scales the halftone cell, so larger values mean physically
  // larger dots (and fewer of them), matching the "dot radius" label.
  let freq = mix(70.0, 10.0, clamp(params.dotRadius, 0.0, 1.0));
  let ink = _vgsl_17688d6e__sampleVideo(src, samp, v).rgb;
  // Subtractive print: white paper, dots grow with ink. Standard CMY screen
  // angles are 15 / 75 / 0 degrees; the UI stores turns.
  let dotC = _vgsl_8e3019cf__halftoneDot(p, params.angC * _vgsl_78d360fe__PI, freq, 1.0 - ink.r);
  let dotM = _vgsl_8e3019cf__halftoneDot(p, params.angM * _vgsl_78d360fe__PI, freq, 1.0 - ink.g);
  let dotY = _vgsl_8e3019cf__halftoneDot(p, params.angY * _vgsl_78d360fe__PI, freq, 1.0 - ink.b);
  let paper = vec3f(1.0);
  let inkc = vec3f(0.0, 0.95, 1.0);
  let inkm = vec3f(1.0, 0.0, 0.9);
  let inky = vec3f(1.0, 0.9, 0.0);
  var col = paper * (1.0 - dotY) + inky * dotY;
  col = col * (1.0 - dotM) + inkm * dotM;
  col = col * (1.0 - dotC) + inkc * dotC;
  return vec4f(col, 1.0);
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

       
     

 

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.


 

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
 

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
 fn _vgsl_8e3019cf__halftoneDot(p: vec2f, angle: f32, freq: f32, ink: f32) -> f32 {
  let c = cos(angle);
  let s = sin(angle);
  let g = mat2x2(c, s, -s, c) * p * freq;
  let lattice = fract(g + 0.5) - 0.5;
  let d = length(lattice);
  return step(d, sqrt(max(ink, 0.0) / 3.14159265));
}

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
 

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
 

// Stable random offset per cell row, driven by an integer tick.
 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
 

 

 

 

 

 

 
