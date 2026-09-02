import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  amount: f32,
  radius: f32,
  softness: f32,
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
  let d = length(p) * 2.0;
  let inner = params.radius * (1.0 - params.softness);
  let fade = smoothstep(inner, params.radius, d);
  let dim = 1.0 - fade * params.amount;
  return vec4f(sampleVideo(src, samp, v).rgb * dim, 1.0);
}
