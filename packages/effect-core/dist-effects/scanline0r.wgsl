
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/scanline0r/effect.wgsl
struct _vgsl_8864548c__Params {
  strength: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_8864548c__Params;

fn _vgsl_8864548c__sampleAt(uv: vec2f) -> vec3f {
  return textureSampleLevel(src, samp, vec2f(fract(uv.x), clamp(uv.y, 0.0, 1.0)), 0.0).rgb;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let half = 0.5 / params.resolution.x;
  let phase = fract(v.y * params.resolution.y * 0.5);
  let line = step(0.5, phase); // alternate rows
  var col = _vgsl_8864548c__sampleAt(v);
  // CRT aperture grille on line rows: R/B read half a pixel off.
  col.r = mix(col.r, _vgsl_8864548c__sampleAt(v + vec2f(half, 0.0)).r, line);
  col.b = mix(col.b, _vgsl_8864548c__sampleAt(v - vec2f(half, 0.0)).b, line);
  col *= 1.0 - params.strength * 0.55 * line;
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

 

 

 

 

 
