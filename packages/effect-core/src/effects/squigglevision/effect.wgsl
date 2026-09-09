import { containUv, sampleVideo } from "../shared/video.wgsl";
import { vnoise2 } from "../shared/f0r.wgsl";

struct Params {
  time: f32,
  strength: f32,
  fps: f32,
  scale: f32,
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
  let tick = floor(params.time * params.fps);
  let n = vnoise2(v * params.scale + vec2f(tick * 0.113, tick * 0.071));
  return sampleVideo(src, samp, v + n * params.strength * 0.05);
}
