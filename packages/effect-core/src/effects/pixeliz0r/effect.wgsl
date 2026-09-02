import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  bw: f32,
  bh: f32,
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
  let bw = max(params.bw, 1.0 / params.videoSize.x);
  let bh = max(params.bh, 1.0 / params.videoSize.y);
  let center = floor(v / vec2f(bw, bh)) * vec2f(bw, bh) + vec2f(bw, bh) * 0.5;
  return sampleVideo(src, samp, center);
}
