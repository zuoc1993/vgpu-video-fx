import { containUv } from "../shared/video.wgsl";
import { lumOf } from "../shared/f0r.wgsl";

struct Params {
  azimuth: f32,
  elevation: f32,
  width: f32,
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
  let texel = 1.0 / max(params.resolution, vec2f(1.0));
  let az = params.azimuth * 6.2831853;
  let off = vec2f(cos(az), -sin(az)) * params.width * texel;
  let h0 = lumOf(textureSampleLevel(src, samp, v, 0.0).rgb);
  let h1 = lumOf(textureSampleLevel(src, samp, v + off, 0.0).rgb);
  let e = (h0 - h1) * (params.elevation * 12.0);
  return vec4f(vec3f(0.5 + e * 0.9), 1.0);
}
