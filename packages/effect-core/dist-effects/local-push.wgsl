
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/local-push/effect.wgsl
struct _vgsl_0390fd74__Params {
  time: f32,
  intensity: f32,
  speed: f32,
  zoom: f32,
  glow: f32,
  chromatic: f32,
  distortion: f32,
  centerX: f32,
  centerY: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_0390fd74__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let center = vec2f(params.centerX, params.centerY);
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  let pulse = 0.5 + 0.5 * sin(params.time * params.speed * 2.2);
  let zoom = 1.0 + params.zoom * params.intensity * (0.25 + 0.9 * pulse);
  var vuv = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  let fromCenter = vuv - center;
  let radialP = vec2f(fromCenter.x * aspect, fromCenter.y);
  let radialLen = length(radialP);
  let radialDir = vec2f(radialP.x / aspect, radialP.y) / max(radialLen, 1e-5);
  vuv = _vgsl_17688d6e__zoomAtAspect(vuv + radialDir * radialLen * params.distortion * 0.45 * pulse, zoom, center, aspect);

  let split = params.chromatic * params.intensity * (0.008 + 0.028 * pulse);
  var color = vec3f(0.0);
  let blurAmt = 0.22 * params.intensity * (0.25 + 0.75 * pulse);
  for (var i = 0; i < 10; i += 1) {
    let k = f32(i) / 9.0;
    let tap = vuv - radialDir * k * blurAmt;
    let r = _vgsl_17688d6e__sampleVideo(src, samp, tap + radialDir * split).r;
    let g = _vgsl_17688d6e__sampleVideo(src, samp, tap).g;
    let b = _vgsl_17688d6e__sampleVideo(src, samp, tap - radialDir * split).b;
    color += vec3f(r, g, b);
  }
  color /= 10.0;

  var bloom = vec3f(0.0);
  let radius = 0.008 * params.glow;
  for (var i = 0; i < 6; i += 1) {
    let a = f32(i) * 1.0472;
    bloom += max(_vgsl_17688d6e__sampleVideo(src, samp, vuv + vec2f(cos(a), sin(a)) * radius).rgb - vec3f(0.55), vec3f(0.0));
  }
  color += bloom / 6.0 * params.glow * 1.8;
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
 

 

// Aspect-corrected rotation: uv is video UV, aspect = videoWidth / videoHeight.
 

// Aspect-corrected zoom: a circular magnification in pixel space, not an
// ellipse in UV space (which is what naive (uv-center)/zoom does on non-square video).
 fn _vgsl_17688d6e__zoomAtAspect(uv: vec2f, zoom: f32, center: vec2f, aspect: f32) -> vec2f {
  let p = (uv - center) * vec2f(aspect, 1.0);
  return center + p / max(zoom, 0.01) / vec2f(aspect, 1.0);
}

 
