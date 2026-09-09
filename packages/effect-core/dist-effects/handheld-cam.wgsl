
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/handheld-cam/effect.wgsl
struct _vgsl_e4636a57__Params {
  time: f32,
  intensity: f32,
  speed: f32,
  zoom: f32,
  sway: f32,
  glow: f32,
  blur: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_e4636a57__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let t = params.time * params.speed;
  let whip = pow(abs(sin(t * 1.35)), 2.4);
  let breath = 1.0 + params.zoom * (0.35 + 0.85 * whip) * params.intensity;
  let angle = sin(t * 1.13) * 0.05 * params.sway * params.intensity;
  let drift = vec2f(sin(t * 2.4), cos(t * 1.7)) * 0.03 * params.sway * params.intensity;
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  var p = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  p = _vgsl_17688d6e__zoomAtAspect(p, breath, vec2f(0.5) + drift, aspect);
  p = _vgsl_17688d6e__rotateUvAspect(p, angle, vec2f(0.5), aspect);

  let vel = vec2f(cos(t * 1.6), sin(t * 1.15) * 0.65) * params.blur * params.intensity * (0.012 + 0.07 * whip);
  var color = _vgsl_17688d6e__directionalBlur(src, samp, p, vel);
  var bloom = vec3f(0.0);
  let radius = 0.006 * params.glow;
  for (var i = 0; i < 8; i += 1) {
    let a = f32(i) * 0.785398;
    bloom += max(_vgsl_17688d6e__sampleVideo(src, samp, p + vec2f(cos(a), sin(a)) * radius).rgb - vec3f(0.62), vec3f(0.0));
  }
  color += bloom / 8.0 * params.glow * 1.6;
  return vec4f(color, 1.0);
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
 fn _vgsl_17688d6e__sampleVideoClamp(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  return textureSampleLevel(src, samp, clamp(uv, vec2f(0.0), vec2f(1.0)), 0.0);
}

 

// Aspect-corrected rotation: uv is video UV, aspect = videoWidth / videoHeight.
 fn _vgsl_17688d6e__rotateUvAspect(uv: vec2f, angle: f32, center: vec2f, aspect: f32) -> vec2f {
  let c = cos(angle);
  let s = sin(angle);
  let p = (uv - center) * vec2f(aspect, 1.0);
  return center + vec2f(p.x * c - p.y * s, p.x * s + p.y * c) / vec2f(aspect, 1.0);
}

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
