import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  amount: f32,
  scale: f32,
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
  let p = v - 0.5;
  let r = length(p);
  let curve = 1.0 - params.amount * (r * r * 1.1);
  let sampled = v - 0.5 + p * curve * params.scale;
  return sampleVideo(src, samp, sampled + 0.5);
}
