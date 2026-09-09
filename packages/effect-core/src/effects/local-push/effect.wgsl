import { containUv, sampleVideo, zoomAtAspect } from "../shared/video.wgsl";

struct Params {
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
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let center = vec2f(params.centerX, params.centerY);
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  let pulse = 0.5 + 0.5 * sin(params.time * params.speed * 2.2);
  let zoom = 1.0 + params.zoom * params.intensity * (0.25 + 0.9 * pulse);
  var vuv = containUv(uv, params.resolution, params.videoSize);
  let fromCenter = vuv - center;
  let radialP = vec2f(fromCenter.x * aspect, fromCenter.y);
  let radialLen = length(radialP);
  let radialDir = vec2f(radialP.x / aspect, radialP.y) / max(radialLen, 1e-5);
  vuv = zoomAtAspect(vuv + radialDir * radialLen * params.distortion * 0.45 * pulse, zoom, center, aspect);

  let split = params.chromatic * params.intensity * (0.008 + 0.028 * pulse);
  var color = vec3f(0.0);
  let blurAmt = 0.22 * params.intensity * (0.25 + 0.75 * pulse);
  for (var i = 0; i < 10; i += 1) {
    let k = f32(i) / 9.0;
    let tap = vuv - radialDir * k * blurAmt;
    let r = sampleVideo(src, samp, tap + radialDir * split).r;
    let g = sampleVideo(src, samp, tap).g;
    let b = sampleVideo(src, samp, tap - radialDir * split).b;
    color += vec3f(r, g, b);
  }
  color /= 10.0;

  var bloom = vec3f(0.0);
  let radius = 0.008 * params.glow;
  for (var i = 0; i < 6; i += 1) {
    let a = f32(i) * 1.0472;
    bloom += max(sampleVideo(src, samp, vuv + vec2f(cos(a), sin(a)) * radius).rgb - vec3f(0.55), vec3f(0.0));
  }
  color += bloom / 6.0 * params.glow * 1.8;
  return vec4f(color, 1.0);
}
