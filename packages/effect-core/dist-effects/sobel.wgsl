
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/sobel/effect.wgsl
struct _vgsl_e1293247__Params {
  threshold: f32,
  gain: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_e1293247__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let texel = 1.0 / max(params.resolution, vec2f(1.0));
  let e = _vgsl_8e3019cf__sobelMag(src, samp, v, texel);
  let edge = smoothstep(params.threshold, params.threshold + 0.15, clamp(e * params.gain * 0.5, 0.0, 1.0));
  return vec4f(vec3f(edge), 1.0);
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

       
     

 fn _vgsl_8e3019cf__lumOf(c: vec3f) -> f32 {
  return dot(c, vec3f(0.2126, 0.7152, 0.0722));
}

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.


 

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
 

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
 

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
 fn _vgsl_8e3019cf__sobelMag(src: texture_2d<f32>, samp: sampler, uv: vec2f, texel: vec2f) -> f32 {
  var l = array<f32, 9>();
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let idx = (dy + 1) * 3 + (dx + 1);
      l[idx] = _vgsl_8e3019cf__lumOf(_vgsl_17688d6e__sampleVideo(src, samp, uv + vec2f(f32(dx), f32(dy)) * texel).rgb);
    }
  }
  let gx = (l[2] + 2.0 * l[5] + l[8]) - (l[0] + 2.0 * l[3] + l[6]);
  let gy = (l[6] + 2.0 * l[7] + l[8]) - (l[0] + 2.0 * l[1] + l[2]);
  return sqrt(gx * gx + gy * gy);
}

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
 

// Stable random offset per cell row, driven by an integer tick.
 

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
 

 

 

 

 

 

 
