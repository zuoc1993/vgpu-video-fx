import { containUv, directionalBlur, rotateUvAspect, sampleVideo, zoomAtAspect } from "../shared/video.wgsl";

struct Params {
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
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let t = params.time * params.speed;
  let whip = pow(abs(sin(t * 1.35)), 2.4);
  let breath = 1.0 + params.zoom * (0.35 + 0.85 * whip) * params.intensity;
  let angle = sin(t * 1.13) * 0.05 * params.sway * params.intensity;
  let drift = vec2f(sin(t * 2.4), cos(t * 1.7)) * 0.03 * params.sway * params.intensity;
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  var p = containUv(uv, params.resolution, params.videoSize);
  p = zoomAtAspect(p, breath, vec2f(0.5) + drift, aspect);
  p = rotateUvAspect(p, angle, vec2f(0.5), aspect);

  let vel = vec2f(cos(t * 1.6), sin(t * 1.15) * 0.65) * params.blur * params.intensity * (0.012 + 0.07 * whip);
  var color = directionalBlur(src, samp, p, vel);
  var bloom = vec3f(0.0);
  let radius = 0.006 * params.glow;
  for (var i = 0; i < 8; i += 1) {
    let a = f32(i) * 0.785398;
    bloom += max(sampleVideo(src, samp, p + vec2f(cos(a), sin(a)) * radius).rgb - vec3f(0.62), vec3f(0.0));
  }
  color += bloom / 8.0 * params.glow * 1.6;
  return vec4f(color, 1.0);
}
