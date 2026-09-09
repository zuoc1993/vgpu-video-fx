import { containUv, sampleVideo } from "../shared/video.wgsl";
import { lumOf } from "../shared/f0r.wgsl";

struct Params {
  width: f32,
  strength: f32,
  threshold: f32,
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
  // ponytail: strip-max smear stands in for a real sort network (single-pass
  // cost ceiling); per-strip brightest row pulled across the strip.
  let wpx = max(mix(4.0, 48.0, params.width), 2.0);
  let strip = floor(v.x * params.videoSize.x / wpx);
  let cx = (strip + 0.5) * wpx / max(params.videoSize.x, 1.0);
  var bestLum = -1.0;
  var bestCol = vec3f(0.0);
  for (var i = 0u; i < 8u; i += 1u) {
    let yy = (f32(i) + 0.5) / 8.0;
    let c = sampleVideo(src, samp, vec2f(cx, yy)).rgb;
    let l = lumOf(c);
    if (l > bestLum) {
      bestLum = l;
      bestCol = c;
    }
  }
  let streak = step(params.threshold, bestLum) * params.strength;
  let col = sampleVideo(src, samp, v).rgb;
  return vec4f(mix(col, bestCol, streak), 1.0);
}
