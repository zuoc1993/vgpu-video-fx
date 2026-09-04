
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/colorhalftone/effect.wgsl
struct _vgsl_9372dbdc__Params {
  dotRadius: f32,
  angC: f32,
  angM: f32,
  angY: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_9372dbdc__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let p = vec2f(v.x * ar, v.y);
  let freq = mix(10.0, 70.0, params.dotRadius);
  let ink = _vgsl_35d1d59a__sampleVideo(src, samp, v).rgb;
  // Subtractive print: white paper, dots grow with ink, CMY at 15°-apart angles.
  let dotC = _vgsl_95d6fc5a__halftoneDot(p, params.angC * 3.14159, freq, 1.0 - ink.r);
  let dotM = _vgsl_95d6fc5a__halftoneDot(p, params.angM * 3.14159 + 1.257, freq, 1.0 - ink.g);
  let dotY = _vgsl_95d6fc5a__halftoneDot(p, params.angY * 3.14159 + 2.513, freq, 1.0 - ink.b);
  let paper = vec3f(1.0);
  let inkc = vec3f(0.0, 0.95, 1.0);
  let inkm = vec3f(1.0, 0.0, 0.9);
  let inky = vec3f(1.0, 0.9, 0.0);
  var col = paper * (1.0 - dotY) + inky * dotY;
  col = col * (1.0 - dotM) + inkm * dotM;
  col = col * (1.0 - dotC) + inkc * dotC;
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

fn _vgsl_35d1d59a__sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}









// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/shared/f0r.wgsl
// Shared helpers for the frei0r-ported effects. Pure math, no resources.

       
     



// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.




// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.


// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
fn _vgsl_95d6fc5a__halftoneDot(p: vec2f, angle: f32, freq: f32, ink: f32) -> f32 {
  let c = cos(angle);
  let s = sin(angle);
  let g = mat2x2(c, s, -s, c) * p * freq;
  let lattice = fract(g + 0.5) - 0.5;
  let d = length(lattice);
  return step(d, 0.5 * sqrt(ink));
}

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.


// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.


// Stable random offset per cell row, driven by an integer tick.


// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector













