import { hash2 } from "@vgpu/wgsl-std/hash";
import { containUv, directionalBlur, zoomAtAspect } from "../shared/video.wgsl";

struct Params {
  time: f32,
  intensity: f32,
  speed: f32,
  punch: f32,
  blur: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let cell = floor(params.time * params.speed * 20.0);
  let n = hash2(vec2f(cell, 3.3)) - vec2f(0.5);
  let hit = pow(abs(sin(params.time * params.speed * 6.4)), 1.6);
  let offset = n * 0.1 * params.intensity;
  // The punch zoom must also cover the translation; otherwise the shake
  // exposes black borders on the opposite side.
  let zoom = max(1.0 + abs(n.x) * 0.22 * params.punch * params.intensity * hit,
                 1.0 + length(offset) * 1.5);
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  var vuv = containUv(uv, params.resolution, params.videoSize);
  vuv = zoomAtAspect(vuv + offset, zoom, vec2f(0.5), aspect);
  let dir = normalize(vec2f(0.85, -0.55) + n * 0.35) * params.blur * params.intensity * (0.02 + 0.09 * hit);
  return vec4f(directionalBlur(src, samp, vuv, dir), 1.0);
}
