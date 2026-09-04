
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/local-push/effect.wgsl
struct _vgsl_8223215e__Params {
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
@group(0) @binding(2) var<uniform> params: _vgsl_8223215e__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let center = vec2f(params.centerX, params.centerY);
  let pulse = 0.5 + 0.5 * sin(params.time * params.speed * 2.2);
  let zoom = 1.0 + params.zoom * params.intensity * (0.25 + 0.9 * pulse);
  var vuv = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  let fromCenter = vuv - center;
  let radial = length(fromCenter);
  vuv = _vgsl_35d1d59a__zoomAt(vuv + fromCenter * radial * params.distortion * 0.45 * pulse, zoom, center);

  let split = params.chromatic * params.intensity * (0.008 + 0.028 * pulse);
  var color = vec3f(0.0);
  let blurAmt = 0.22 * params.intensity * (0.25 + 0.75 * pulse);
  for (var i = 0; i < 10; i += 1) {
    let k = f32(i) / 9.0;
    let tap = vuv - fromCenter * k * blurAmt;
    let r = _vgsl_35d1d59a__sampleVideo(src, samp, tap + vec2f(split, 0.0)).r;
    let g = _vgsl_35d1d59a__sampleVideo(src, samp, tap).g;
    let b = _vgsl_35d1d59a__sampleVideo(src, samp, tap - vec2f(split, 0.0)).b;
    color += vec3f(r, g, b);
  }
  color /= 10.0;

  var bloom = vec3f(0.0);
  let radius = 0.008 * params.glow;
  for (var i = 0; i < 6; i += 1) {
    let a = f32(i) * 1.0472;
    bloom += max(_vgsl_35d1d59a__sampleVideo(src, samp, vuv + vec2f(cos(a), sin(a)) * radius).rgb - vec3f(0.55), vec3f(0.0));
  }
  color += bloom / 6.0 * params.glow * 1.8;
  return vec4f(color, 1.0);
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





fn _vgsl_35d1d59a__zoomAt(uv: vec2f, zoom: f32, center: vec2f) -> vec2f {
  return (uv - center) / max(zoom, 0.01) + center;
}


