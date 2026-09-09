
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/glow/effect.wgsl
struct _vgsl_02481a51__Params {
  blur: f32,
  amount: f32,
  threshold: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_02481a51__Params;

const _vgsl_02481a51__DIR = array<vec2f, 8>(
  vec2f(1.0, 0.0), vec2f(0.7071, 0.7071), vec2f(0.0, 1.0), vec2f(-0.7071, 0.7071),
  vec2f(-1.0, 0.0), vec2f(-0.7071, -0.7071), vec2f(0.0, -1.0), vec2f(0.7071, -0.7071),
);

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // Single-pass 8-tap ring stands in for a real blur. Radius is a pixel
  // vector, otherwise the halo is elliptical on non-square frames/canvas.
  let base = _vgsl_17688d6e__sampleVideo(src, samp, v).rgb;
  let r = vec2f(params.blur) / max(params.resolution, vec2f(1.0));
  var acc = vec3f(0.0);
  for (var i = 0u; i < 8u; i += 1u) {
    acc += _vgsl_17688d6e__sampleVideoClamp(src, samp, v + _vgsl_02481a51__DIR[i] * r).rgb;
  }
  acc = acc / 8.0;
  // Threshold is a real bright-pass on the blurred signal, so dark areas no
  // longer glow just because they are adjacent to the light.
  let glow = max(acc - vec3f(params.threshold), vec3f(0.0)) * params.amount;
  return vec4f(base + glow, 1.0);
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
 

// Aspect-corrected zoom: a circular magnification in pixel space, not an
// ellipse in UV space (which is what naive (uv-center)/zoom does on non-square video).
 

 
