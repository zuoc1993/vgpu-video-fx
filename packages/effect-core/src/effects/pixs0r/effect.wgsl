import { containUv } from "../shared/video.wgsl";
import { hash1, hash3 } from "@vgpu/wgsl-std/hash";

struct Params {
  time: f32,
  intensity: f32,
  blockHeight: f32,
  columns: f32,
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
  let tick = floor(params.time * params.speed * 10.0);
  // blockHeight = 0 selects the original pixs0r random-block mode.
  var bhPx = params.blockHeight;
  if (bhPx < 1.0) {
    bhPx = mix(2.0, 64.0, hash1(tick * 0.37 + 4.2));
  }
  bhPx = max(bhPx, 2.0);
  let row = floor(v.y * params.videoSize.y / bhPx);
  let h = hash3(vec3f(f32(row), tick, 0.0));

  var w = v;
  if (h.x < params.intensity * 0.5) {
    // Row slices glide sideways; occasionally a full row strips out.
    w.x = fract(w.x + (h.y - 0.5) * 0.22 * params.intensity);
  }
  // A second, independent grid shifts columns so the tear is not purely 1-D.
  let col = floor(v.x * params.videoSize.x / bhPx);
  let hc = hash3(vec3f(f32(col), tick, 7.0));
  if (hc.x < params.columns * 0.5) {
    w.x = fract(w.x + (hc.y - 0.5) * 0.12 * params.columns);
  }

  let c = textureSampleLevel(src, samp, vec2f(w.x, clamp(w.y, 0.0, 1.0)), 0.0).rgb;
  var result = c;
  if (h.z < params.intensity * 0.03) {
    result = result.brg; // rare hue flip slice
  }
  return vec4f(result, 1.0);
}
