import { containUv, sampleVideo, sampleVideoClamp } from "../shared/video.wgsl";

struct Params {
  blur: f32,
  amount: f32,
  threshold: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

const DIR = array<vec2f, 8>(
  vec2f(1.0, 0.0), vec2f(0.7071, 0.7071), vec2f(0.0, 1.0), vec2f(-0.7071, 0.7071),
  vec2f(-1.0, 0.0), vec2f(-0.7071, -0.7071), vec2f(0.0, -1.0), vec2f(0.7071, -0.7071),
);

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // Single-pass 8-tap ring stands in for a real blur. Radius is a pixel
  // vector, otherwise the halo is elliptical on non-square frames/canvas.
  let base = sampleVideo(src, samp, v).rgb;
  let r = vec2f(params.blur) / max(params.resolution, vec2f(1.0));
  var acc = vec3f(0.0);
  for (var i = 0u; i < 8u; i += 1u) {
    acc += sampleVideoClamp(src, samp, v + DIR[i] * r).rgb;
  }
  acc = acc / 8.0;
  // Threshold is a real bright-pass on the blurred signal, so dark areas no
  // longer glow just because they are adjacent to the light.
  let glow = max(acc - vec3f(params.threshold), vec3f(0.0)) * params.amount;
  return vec4f(base + glow, 1.0);
}
