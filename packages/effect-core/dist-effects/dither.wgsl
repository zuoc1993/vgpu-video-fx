
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/dither/effect.wgsl
struct _vgsl_78bd44f3__Params {
  levels: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_78bd44f3__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // frei0r semantics: low levels = fewer bands, dither spreads the error.
  let bands = 2.0 + floor(clamp(params.levels, 0.0, 1.0) * 254.0);
  let coords = vec2u(floor(v * params.resolution));
  let d = _vgsl_8e3019cf__bayer4(coords) - 0.5;
  var col = _vgsl_17688d6e__sampleVideo(src, samp, v).rgb * bands;
  col = floor(col + d + 0.5) / bands;
  return vec4f(col, 1.0);
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
 

 

 

 

 

 

 
