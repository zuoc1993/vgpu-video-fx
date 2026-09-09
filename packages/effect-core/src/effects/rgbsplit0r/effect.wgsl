import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  vertical: f32,
  horizontal: f32,
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
  // 0.5 is neutral. horizontal and vertical are independent axes; R moves in
  // +offset and B in -offset, so at the default (0.9, 0.9) the red and blue
  // fringes land on opposite sides instead of collapsing onto each other.
  let offset = (vec2f(params.horizontal, params.vertical) - vec2f(0.5)) * 0.12;
  let r = sampleVideo(src, samp, v + offset).r;
  let g = sampleVideo(src, samp, v).g;
  let b = sampleVideo(src, samp, v - offset).b;
  return vec4f(r, g, b, 1.0);
}
