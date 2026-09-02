// Perlin dissolve: content burns away through a fBm threshold field with a
// glowing rim. Own implementation on top of @vgpu/wgsl-std fBm.
import { containUv, sampleVideo } from "../shared/video.wgsl";
import { fbmPerlin2d } from "@vgpu/wgsl-std/noise/perlin";

struct Params {
  time: f32,
  speed: f32,
  scale: f32,
  edgeGlow: f32,
  invert: f32,
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
  let t = clamp(fract(params.time * params.speed * 0.5), 0.0, 1.0);
  let n = fbmPerlin2d(v * params.scale + vec2f(0.0, -t * 4.0), 4, 2.0, 0.55);
  let f = n * 0.5 + 0.5; // fBm sigma ~0.3 -> 0..1-ish, keep sharp edge = midgate
  var mask = step(f, t);
  if (params.invert > 0.5) {
    mask = 1.0 - mask;
  }
  let col = sampleVideo(src, samp, v).rgb;
  // Burning rim: band around the threshold line.
  let rim = 1.0 - abs(smoothstep(t - 0.06, t + 0.06, f) - 0.5) * 2.0;
  let edge = smoothstep(0.02, 0.2, rim) * params.edgeGlow;
  let out = col * mask + vec3f(1.0, 0.45, 0.18) * edge * 0.9;
  return vec4f(out, 1.0);
}
