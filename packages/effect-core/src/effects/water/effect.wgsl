import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  amp: f32,
  freq: f32,
  speed: f32,
  swirl: f32,
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
  let t = params.time * params.speed;
  // Layered sine ripples plus a slow center swirl.
  let d = vec2f(
    sin(v.y * params.freq * 6.28318 + sin(t * 1.7) * 2.0) + sin(v.y * params.freq * 3.7 - t * 2.3) * 0.5,
    sin(v.x * params.freq * 1.3 + t * 1.9) * 0.7 + sin(v.x * params.freq * 2.9 - t) * 0.5
  );
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let p = vec2f((v.x - 0.5) * ar, v.y - 0.5);
  let a = sin(t * 0.62) * params.swirl * 0.25;
  let c = cos(a);
  let s = sin(a);
  let q = vec2f(p.x * c - p.y * s, p.x * s + p.y * c);
  return sampleVideo(src, samp, v + d * params.amp + (q - p));
}
