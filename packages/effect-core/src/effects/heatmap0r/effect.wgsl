import { containUv, sampleVideo } from "../shared/video.wgsl";
import { lumOf, hueRotate } from "../shared/f0r.wgsl";

struct Params {
  hueShift: f32,
  greyPoint: f32,
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
  let l = lumOf(sampleVideo(src, samp, v).rgb);
  let g = clamp(params.greyPoint, 0.01, 0.99);
  // Black -> violet -> magenta -> yellow, grey point moves the violet stop.
  let c0 = vec3f(0.02, 0.0, 0.14);
  let c1 = vec3f(0.27, 0.0, 0.5);
  let c2 = vec3f(1.0, 1.0, 0.05);
  var col = mix(c0, c1, smoothstep(0.0, g, l));
  col = mix(col, c2, smoothstep(g, 1.0, l));
  col = hueRotate(col, params.hueShift);
  return vec4f(col, 1.0);
}
