import { containUv, sampleVideo } from "../shared/video.wgsl";
import { hueRotate, sobelMag } from "../shared/f0r.wgsl";

struct Params {
  threshold: f32,
  intensity: f32,
  hueShift: f32,
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
  let e = sobelMag(src, samp, v, texel);
  let glow = smoothstep(params.threshold, params.threshold + 0.3, e) * params.intensity;
  let tint = hueRotate(vec3f(1.0, 0.55, 0.25), params.hueShift);
  let col = sampleVideo(src, samp, v).rgb;
  return vec4f(col + glow * tint * 0.9, 1.0);
}
