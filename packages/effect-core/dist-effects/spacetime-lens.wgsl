
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/spacetime-lens/effect.wgsl
// Spacetime lens, inspired by the 2D black-hole lensing in
// MolecularSadism/msg_shaders (Apache-2.0), itself based on Eric Bruneton's
// black hole shader (BSD-3). Simplified single-pass deflection + echo ring.
      

struct _vgsl_1a1c768e__Params {
  time: f32,
  radius: f32,
  strength: f32,
  echo: f32,
  swirl: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_1a1c768e__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let ar = params.videoSize.x / max(params.videoSize.y, 1.0);
  let p = vec2f((v.x - 0.5) * ar, v.y - 0.5);
  let r = length(p);
  let rs = max(params.radius, 0.01);

  // Deflection ~ rs^2 / b: strong magnification, soft 1/r falloff.
  let defl = (rs * rs * params.strength) / max(r, rs * 0.3);
  // Tangential swirl tightens toward the hole.
  let ang = atan2(p.y, p.x) + params.swirl * (rs * rs) / max(r * r + rs * rs, 1e-4) * 0.75 + params.time * 0.18;
  let dir = vec2f(cos(ang), sin(ang)) * max(r - defl, 0.001);
  let sampleUv = dir / vec2f(ar, 1.0) + 0.5;
  var col = _vgsl_17688d6e__sampleVideo(src, samp, sampleUv).rgb;

  // Photon ring: inside the shadow the far side is reflected in.
  let echoR = (rs * rs) / max(r, rs * 0.4);
  let echoDir = vec2f(cos(ang + 3.14159), sin(ang + 3.14159)) * echoR;
  let echoUv = echoDir / vec2f(ar, 1.0) + 0.5;
  let inside = 1.0 - smoothstep(rs * 0.8, rs * 1.3, r);
  col = mix(col, _vgsl_17688d6e__sampleVideo(src, samp, echoUv).rgb, inside * params.echo);

  // Spectral ring glow.
  let pulse = 0.6 + 0.4 * sin(params.time * 1.7);
  col += vec3f(0.45, 0.28, 0.65) * exp(-abs(r - rs) * 14.0) * params.echo * 0.6 * pulse;
  return vec4f(min(col, vec3f(2.0)), 1.0);
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
 

 
