import { containUv, sampleVideo, sampleVideoClamp } from "../shared/video.wgsl";

struct Params {
  amount: f32,
  scale: f32,
  mode: f32,
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
  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  let p = vec2f((v.x - 0.5) * aspect, v.y - 0.5);
  let r = length(p);
  // mode=1 (default) is Defish: sample outward, then clamp at the frame edge
  // so removing a fisheye does not leave a black vignette. mode=0 is the
  // original Fish/barrel direction, where black outside is expected.
  let dir = select(-1.0, 1.0, params.mode > 0.5);
  let curve = 1.0 + dir * params.amount * (r * r * 1.1);
  let q = p * curve * params.scale;
  let sampled = q / vec2f(aspect, 1.0) + 0.5;
  if (params.mode > 0.5) {
    return sampleVideoClamp(src, samp, sampled);
  }
  return sampleVideo(src, samp, sampled);
}
