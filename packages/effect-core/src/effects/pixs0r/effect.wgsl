import { containUv } from "../shared/video.wgsl";
import { hash2, hash3 } from "@vgpu/wgsl-std/hash";

struct Params {
  time: f32,
  intensity: f32,
  blockHeight: f32,
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
  let bhPx = max(params.blockHeight, 2.0);
  let row = floor(v.y * params.resolution.y / bhPx);
  let tick = floor(params.time * params.speed * 10.0);
  let h = hash3(vec3f(f32(row), tick, 0.0));
  var w = v;
  if (h.x < params.intensity * 0.5) {
    // Row slices glide sideways; occasionally a full row strips out.
    w.x = fract(w.x + (h.y - 0.5) * 0.22 * params.intensity);
  }
  let c = textureSampleLevel(src, samp, vec2f(w.x, clamp(w.y, 0.0, 1.0)), 0.0).rgb;
  var result = c;
  if (h.z < params.intensity * 0.03) {
    result = result.brg; // rare hue flip slice
  }
  return vec4f(result, 1.0);
}
