
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/ntsc/effect.wgsl
struct _vgsl_f6e5f5a9__Params {
  time: f32,
  noise: f32,
  scanlines: f32,
  burst: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_f6e5f5a9__Params;

fn _vgsl_f6e5f5a9__sampleAt(uv: vec2f) -> vec3f {
  return _vgsl_17688d6e__sampleVideoClamp(src, samp, uv).rgb;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // 4:2:0-ish chroma sampling in source-pixel space, so the offset is stable
  // between preview and offscreen rendering.
  let line = floor(v.y * params.videoSize.y);
  let off = 3.0 / max(params.videoSize.x, 1.0);
  var col = _vgsl_f6e5f5a9__sampleAt(v);
  col.r = mix(col.r, _vgsl_f6e5f5a9__sampleAt(v + vec2f(off, 0.0)).r, params.burst);
  col.b = mix(col.b, _vgsl_f6e5f5a9__sampleAt(v - vec2f(off, 0.0)).b, params.burst);
  // Rolling NTSC color burst shimmer per line. Time drives the phase so the
  // noise is not frozen to the image.
  let phase = _vgsl_aa51502b__hash1(f32(line) + params.time * 7.0) * 0.35 + v.x * 6.2831853 + params.time * 2.0;
  col = _vgsl_8e3019cf__hueRotate(col, params.burst * 0.22 * phase);
  // Additive signal noise + dark scanline comb.
  let nz = (_vgsl_aa51502b__hash1(v.x * 671.0 + v.y * 419.0 + params.time * 37.0) - 0.5) * params.noise * 0.5;
  col = vec3f(clamp(col.r + nz, 0.0, 1.0), clamp(col.g + nz, 0.0, 1.0), clamp(col.b + nz, 0.0, 1.0));
  let dark = step(0.5, fract(line * 0.5)) * params.scanlines * 0.3;
  col *= 1.0 - dark;
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
 

 

// Edge-clamped source sample for convolution/blur kernels: a uniform frame must
// not grow a false white border, and blur halos must not eat the video edges.
 fn _vgsl_17688d6e__sampleVideoClamp(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  return textureSampleLevel(src, samp, clamp(uv, vec2f(0.0), vec2f(1.0)), 0.0);
}

 

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

 

 

 fn _vgsl_aa51502b__unitFloat(hash: u32) -> f32 {
  return f32(hash >> 8u) * (1.0 / 16777216.0);
}

 fn _vgsl_aa51502b__hash1(seed: f32) -> f32 {
  return _vgsl_aa51502b__unitFloat(_vgsl_aa51502b__hashU32(bitcast<u32>(seed)));
}

 

 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     

 

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.


 

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
 

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
 

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
 

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
 fn _vgsl_8e3019cf__hueRotate(c: vec3f, t: f32) -> vec3f {
  let a = t * 6.2831853;
  let ca = cos(a);
  let sa = sin(a);
  // WGSL matrices are column-major: pass the columns of the Rec.601 hue
  // rotation matrix. Passing its rows here transposes the rotation and breaks
  // luminance preservation (a pure red would jump from luma 0.299 to ~0.46).
  let m = mat3x3(
    0.299 + 0.701 * ca + 0.168 * sa, 0.299 - 0.299 * ca - 0.328 * sa, 0.299 - 0.300 * ca + 1.250 * sa,
    0.587 - 0.587 * ca + 0.330 * sa, 0.587 + 0.413 * ca + 0.035 * sa, 0.587 - 0.588 * ca - 1.050 * sa,
    0.114 - 0.114 * ca - 0.497 * sa, 0.114 - 0.114 * ca + 0.292 * sa, 0.114 + 0.886 * ca - 0.203 * sa,
  );
  return m * c;
}

// Stable random offset per cell row, driven by an integer tick.
 
