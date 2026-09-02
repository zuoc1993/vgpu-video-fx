// Film light leak: slow warm band sweep across the frame + hot corner.
// Own implementation, common film-leak aesthetic discussed across Shadertoy.
import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  intensity: f32,
  size: f32,
  speed: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let p = vec2f((v.x - 0.5) * ar, v.y - 0.5);
  let t = params.time * params.speed;
  // Rotating sweep axis; band position drifts back and forth.
  let axis = vec2f(cos(t * 0.4), sin(t * 0.4));
  let d = dot(p, axis) - sin(t * 0.7) * 0.9;
  let band = exp(-(d * d) / max(params.size * 0.35, 0.02));
  // Hot lower-right corner, e.g. shutter leak.
  let corner = exp(-length(p - vec2f(0.7, -0.5)) * 3.2) * 0.8;
  let leak = clamp(band * 0.7 + corner, 0.0, 1.0) * params.intensity;
  let warm = vec3f(1.0, 0.55, 0.25);
  var col = sampleVideo(src, samp, v).rgb;
  col = pow(col, vec3f(0.92)); // slight film highlight roll
  return vec4f(mix(col, col * warm * 1.5 + warm * 0.25, leak), 1.0);
}
