
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/retro-quantize/effect.wgsl
// Retro quantization, concept from MolecularSadism/msg_shaders (Apache-2.0):
// Oklab nearest-palette match + Bayer dither (Björn Ottosson's Oklab mapping).
     
     

struct _vgsl_e7f77062__Params {
  colors: f32,
  dither: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_e7f77062__Params;

// Oklab expects linear-light RGB; the texture sample and palette entries are
// sRGB-encoded, so decode first. Matching in gamma space skews shadows badly.
fn _vgsl_e7f77062__srgbToLinear(c: vec3f) -> vec3f {
  let lo = c / 12.92;
  let hi = pow((c + vec3f(0.055)) / 1.055, vec3f(2.4));
  return select(hi, lo, c <= vec3f(0.04045));
}

// Oklab (relative D65), Björn Ottosson, still MIT/public math.
fn _vgsl_e7f77062__toOklab(c: vec3f) -> vec3f {
  let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(l, 1.0 / 3.0);
  let m_ = pow(m, 1.0 / 3.0);
  let s_ = pow(s, 1.0 / 3.0);
  return vec3f(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  );
}

// Deterministic retro palettes: 2 = mono, 4 = magenta-yellow vapors,
// 8 = RGB cube, 16 = RGB cube + 8 grays.
fn _vgsl_e7f77062__paletteCount(sel: f32) -> i32 {
  return i32(select(select(select(2.0, 4.0, sel > 0.5), 8.0, sel > 1.5), 16.0, sel > 2.5));
}

fn _vgsl_e7f77062__paletteColor(i: i32, count: i32) -> vec3f {
  if (count == 2) {
    return select(vec3f(0.0), vec3f(1.0), i == 1);
  }
  if (count == 4) {
    let pal = array<vec3f, 4>(
      vec3f(0.06, 0.04, 0.10),
      vec3f(0.98, 0.92, 0.29),
      vec3f(0.75, 0.42, 1.0),
      vec3f(0.95, 0.95, 0.95),
    );
    return pal[i];
  }
  if (count == 8) {
    // RGB cube
    return vec3f(
      f32((i >> 2) & 1),
      f32((i >> 1) & 1),
      f32(i & 1),
    );
  }
  if (i < 8) {
    let g = f32(i) / 7.0;
    return vec3f(g);
  }
  let j = i - 8;
  return vec3f(
    f32((j >> 2) & 1),
    f32((j >> 1) & 1),
    f32(j & 1),
  );
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  var c = textureSampleLevel(src, samp, v, 0.0).rgb;
  // Dither in RGB space before the lab match, offsets per pixel.
  let dthr = (_vgsl_8e3019cf__bayer4(vec2u(floor(v * params.videoSize))) - 0.5) * params.dither * 0.3;
  let q = c + vec3f(dthr);
  let lab = _vgsl_e7f77062__toOklab(_vgsl_e7f77062__srgbToLinear(clamp(q, vec3f(0.0), vec3f(1.0))));
  let count = _vgsl_e7f77062__paletteCount(params.colors);
  var best = 1e10;
  var bestCol = vec3f(0.0);
  for (var i = 0; i < 16; i += 1) {
    if (i >= count) {
      break;
    }
    let cand = _vgsl_e7f77062__paletteColor(i, count);
    let dl = _vgsl_e7f77062__toOklab(_vgsl_e7f77062__srgbToLinear(cand)) - lab;
    let dist = dot(dl, dl);
    if (dist < best) {
      best = dist;
      bestCol = cand;
    }
  }
  return vec4f(bestCol, 1.0);
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
 

 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     

 

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.


 

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
 fn _vgsl_8e3019cf__bayer4(coords: vec2u) -> f32 {
  const M = array<f32, 16>(
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0,
  );
  let idx = coords.y % 4u * 4u + coords.x % 4u;
  return (M[idx] + 0.5) / 16.0;
}

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
 

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
 

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
 

// Stable random offset per cell row, driven by an integer tick.
 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
 

 

 

 

 

 

 
