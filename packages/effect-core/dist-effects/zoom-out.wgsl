
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/zoom-in/effect.wgsl
struct _vgsl_6f969955__Params {
  time: f32,
  videoTime: f32,
  startScale: f32,
  endScale: f32,
  duration: f32,
  looping: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_6f969955__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let dur = max(params.duration, 0.05);
  var t = params.videoTime / dur;
  if (params.looping > 0.5) {
    t = fract(t);
  } else {
    t = clamp(t, 0.0, 1.0);
  }
  let scale = mix(params.startScale, params.endScale, _vgsl_17688d6e__easeInOutCubic(t));
  let vuv = (_vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize) - vec2f(0.5)) / scale + vec2f(0.5);
  return _vgsl_17688d6e__sampleVideo(src, samp, vuv);
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

 fn _vgsl_17688d6e__easeInOutCubic(t: f32) -> f32 {
  let x = clamp(t, 0.0, 1.0);
  if (x < 0.5) {
    return 4.0 * x * x * x;
  }
  let u = -2.0 * x + 2.0;
  return 1.0 - u * u * u / 2.0;
}

 

 

 
