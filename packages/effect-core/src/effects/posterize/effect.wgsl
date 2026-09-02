import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  levels: f32,
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
  // frei0r semantics: low levels = few bands = harsh quantization.
  let bands = 2.0 + floor(clamp(params.levels, 0.0, 1.0) * 254.0);
  let inv = 1.0 / bands;
  let col = floor(sampleVideo(src, samp, v).rgb * bands + 0.5) * inv;
  return vec4f(col, 1.0);
}
