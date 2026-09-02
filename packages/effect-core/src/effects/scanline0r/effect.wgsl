import { containUv } from "../shared/video.wgsl";

struct Params {
  strength: f32,
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
  let half = 0.5 / params.resolution.x;
  let phase = fract(v.y * params.resolution.y * 0.5);
  let line = step(0.5, phase); // alternate rows
  var col = sampleAt(v);
  // CRT aperture grille on line rows: R/B read half a pixel off.
  col.r = mix(col.r, sampleAt(v + vec2f(half, 0.0)).r, line);
  col.b = mix(col.b, sampleAt(v - vec2f(half, 0.0)).b, line);
  col *= 1.0 - params.strength * 0.55 * line;
  return vec4f(col, 1.0);
}
