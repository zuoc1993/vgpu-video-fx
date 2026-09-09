import { containUv } from "../shared/video.wgsl";
import { hash2, hash3 } from "@vgpu/wgsl-std/hash";

struct Params {
  time: f32,
  frequency: f32,
  blockHeight: f32,
  shift: f32,
  colorAmt: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

fn sampleAt(uv: vec2f) -> vec4f {
  return textureSampleLevel(src, samp, vec2f(fract(uv.x), clamp(uv.y, 0.0, 1.0)), 0.0);
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let bhPx = max(mix(4.0, max(160.0, 1.0), params.blockHeight), 1.0);
  let row = floor(v.y * params.videoSize.y / bhPx);
  let tick = floor(params.time * mix(6.0, 24.0, params.frequency));
  let h = hash3(vec3f(f32(row), tick * 3.1, 0.0));

  var w = v;
  if (h.x < params.frequency * 0.7) {
    w.x += (h.y - 0.5) * params.shift * 0.35;
  }
  let split = (h.y - 0.5) * params.colorAmt * 0.05;
  let r = sampleAt(w + vec2f(split, 0.0)).r;
  let g = sampleAt(w).g;
  let b = sampleAt(w - vec2f(split, 0.0)).b;
  var col = vec3f(r, g, b);
  if (h.y > 1.0 - params.colorAmt * 0.15) {
    col = col.brg;
  }
  if (h.z > 0.85) {
    col = col * 1.3;
  }
  return vec4f(min(col, vec3f(1.7)), 1.0);
}
