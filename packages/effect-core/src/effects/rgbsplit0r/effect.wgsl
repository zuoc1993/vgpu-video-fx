import { containUv } from "../shared/video.wgsl";

struct Params {
  vertical: f32,
  horizontal: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

fn channel(uv: vec2f, axis: f32) -> vec3f {
  // frei0r semantics: 0.5 is the neutral point, 1.0 maximal offset.
  let full = (axis - 0.5) * 0.12;
  let uv2 = vec2f(uv.x + full, uv.y - full);
  return textureSampleLevel(src, samp, vec2f(fract(uv2.x), clamp(uv2.y, 0.0, 1.0)), 0.0).xyz;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let r = channel(v, params.horizontal).r;
  let b = channel(v, params.vertical).b;
  let g = channel(v, 0.5).g;
  return vec4f(r, g, b, 1.0);
}
