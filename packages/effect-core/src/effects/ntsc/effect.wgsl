import { containUv } from "../shared/video.wgsl";
import { hash1 } from "@vgpu/wgsl-std/hash";
import { hueRotate } from "../shared/f0r.wgsl";

struct Params {
  noise: f32,
  scanlines: f32,
  burst: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

fn sampleAt(uv: vec2f) -> vec3f {
  return textureSampleLevel(src, samp, vec2f(fract(uv.x), clamp(uv.y, 0.0, 1.0)), 0.0).rgb;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // 4:2:0-ish chroma sampling: R / B read ~3px off from G.
  let line = floor(v.y * params.resolution.y);
  let off = 3.0 / params.resolution.x;
  var col = sampleAt(v);
  col.r = mix(col.r, sampleAt(v + vec2f(off, 0.0)).r, params.burst);
  col.b = mix(col.b, sampleAt(v - vec2f(off, 0.0)).b, params.burst);
  // Rolling NTSC color burst shimmer per line.
  let phase = hash1(f32(line)) * 0.35 + v.x * 6.2831853;
  col = hueRotate(col, params.burst * 0.22 * phase);
  // Additive signal noise + dark scanline comb.
  let nz = (hash1(v.x * 671.0 + v.y * 419.0) - 0.5) * params.noise * 0.5;
  col = vec3f(clamp(col.r + nz, 0.0, 1.0), clamp(col.g + nz, 0.0, 1.0), clamp(col.b + nz, 0.0, 1.0));
  let dark = step(0.5, fract(line * 0.5)) * params.scanlines * 0.3;
  col *= 1.0 - dark;
  return vec4f(col, 1.0);
}
