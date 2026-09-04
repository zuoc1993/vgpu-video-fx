
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/spacetime-lens/effect.wgsl
// Spacetime lens, inspired by the 2D black-hole lensing in
// MolecularSadism/msg_shaders (Apache-2.0), itself based on Eric Bruneton's
// black hole shader (BSD-3). Simplified single-pass deflection + echo ring.
      

struct _vgsl_09610e51__Params {
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
@group(0) @binding(2) var<uniform> params: _vgsl_09610e51__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let p = vec2f((v.x - 0.5) * ar, v.y - 0.5);
  let r = length(p);
  let rs = max(params.radius, 0.01);

  // Deflection ~ rs^2 / b: strong magnification, soft 1/r falloff.
  let defl = (rs * rs * params.strength) / max(r, rs * 0.3);
  // Tangential swirl tightens toward the hole.
  let ang = atan2(p.y, p.x) + params.swirl * (rs * rs) / max(r * r + rs * rs, 1e-4) * 0.75;
  let dir = vec2f(cos(ang), sin(ang)) * max(r - defl, 0.001);
  let sampleUv = dir / vec2f(ar, 1.0) + 0.5;
  var col = _vgsl_35d1d59a__sampleVideo(src, samp, sampleUv).rgb;

  // Photon ring: inside the shadow the far side is reflected in.
  let echoR = (rs * rs) / max(r, rs * 0.4);
  let echoDir = vec2f(cos(ang + 3.14159), sin(ang + 3.14159)) * echoR;
  let echoUv = echoDir / vec2f(ar, 1.0) + 0.5;
  let inside = 1.0 - smoothstep(rs * 0.8, rs * 1.3, r);
  col = mix(col, _vgsl_35d1d59a__sampleVideo(src, samp, echoUv).rgb, inside * params.echo);

  // Spectral ring glow.
  col += vec3f(0.45, 0.28, 0.65) * exp(-abs(r - rs) * 14.0) * params.echo * 0.6;
  return vec4f(min(col, vec3f(2.0)), 1.0);
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








