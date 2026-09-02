import { containUv, sampleVideo } from "../shared/video.wgsl";
import { perlin2d } from "@vgpu/wgsl-std/noise/perlin";

struct Params {
  time: f32,
  amplitude: f32,
  freq: f32,
  speed: f32,
  velocity: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

// perlin2d sigma ~0.3; remap to [-1, 1] here.
fn np(p: vec2f) -> vec2f {
  return vec2f(perlin2d(p), perlin2d(p + vec2f(57.3, 21.7))) * 3.3;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let t = params.time * params.speed;
  let n = np(v * params.freq + vec2f(t * params.velocity * 0.7, t));
  return sampleVideo(src, samp, v + n * params.amplitude * 0.08);
}
