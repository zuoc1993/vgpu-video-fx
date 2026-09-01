import { hash2 } from "@vgpu/wgsl-std/hash";
import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  intensity: f32,
  speed: f32,
  frequency: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let cell = floor(params.time * params.speed * params.frequency);
  let n = hash2(vec2f(cell, 17.3));
  let n2 = hash2(vec2f(cell + 1.0, 9.1));
  let frac = fract(params.time * params.speed * params.frequency);
  let jitter = mix(n, n2, frac) - vec2f(0.5);
  let offset = jitter * 0.055 * params.intensity;
  let vuv = containUv(uv, params.resolution, params.videoSize) + offset;
  return sampleVideo(src, samp, vuv);
}
