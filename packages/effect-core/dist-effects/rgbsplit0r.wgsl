
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/rgbsplit0r/effect.wgsl
struct _vgsl_38c30709__Params {
  vertical: f32,
  horizontal: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_38c30709__Params;

fn _vgsl_38c30709__channel(uv: vec2f, axis: f32) -> vec3f {
  // frei0r semantics: 0.5 is the neutral point, 1.0 maximal offset.
  let full = (axis - 0.5) * 0.12;
  let uv2 = vec2f(uv.x + full, uv.y - full);
  return textureSampleLevel(src, samp, vec2f(fract(uv2.x), clamp(uv2.y, 0.0, 1.0)), 0.0).xyz;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let r = _vgsl_38c30709__channel(v, params.horizontal).r;
  let b = _vgsl_38c30709__channel(v, params.vertical).b;
  let g = _vgsl_38c30709__channel(v, 0.5).g;
  return vec4f(r, g, b, 1.0);
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

 

 

 

 

 
