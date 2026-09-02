import { containUv, sampleVideo } from "../shared/video.wgsl";
import { bayer4 } from "../shared/f0r.wgsl";

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
  // frei0r semantics: low levels = fewer bands, dither spreads the error.
  let bands = 2.0 + floor(clamp(params.levels, 0.0, 1.0) * 254.0);
  let coords = vec2u(floor(v * params.resolution));
  let d = bayer4(coords) - 0.5;
  var col = sampleVideo(src, samp, v).rgb * bands;
  col = floor(col + d + 0.5) / bands;
  return vec4f(col, 1.0);
}
