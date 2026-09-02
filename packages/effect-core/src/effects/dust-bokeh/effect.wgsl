// Floating bokeh dust, inspired by charbelmalo/PrismaticShadersPack dust
// particles (MIT). Procedural soft discs instead of an atlas texture.
import { containUv, sampleVideo } from "../shared/video.wgsl";
import { hash1 } from "@vgpu/wgsl-std/hash";

struct Params {
  time: f32,
  count: f32,
  size: f32,
  focus: f32,
  opacity: f32,
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
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let n = max(floor(params.count), 4.0);
  var dust = 0.0;
  var tint = 0.0;
  for (var i = 0u; i < 24u; i += 1u) {
    let f = f32(i);
    if (f >= n) {
      break;
    }
    // Base position drifts slowly; depth per particle controls both scale and
    // blur radius (pre-computed-atlas analogue: sigma = radius*blur).
    let depth = hash1(f * 7.31);
    let drift = vec2f(hash1(f * 13.7 + 1.0), hash1(f * 19.3 + 2.0)) - 0.5;
    var pos = vec2f(hash1(f * 3.3), hash1(f * 5.1)) + drift * 0.2 * params.time;
    pos = vec2f(fract(pos.x), fract(pos.y));
    // Correct the screen-space offset by aspect so distance reads square.
    let p = vec2f((v.x - pos.x) * ar, v.y - pos.y);
    let r = length(p);
    let bokeh = mix(params.size * 0.02, params.size * 0.05, depth);
    let focusDist = abs(depth - params.focus);
    let sigma = bokeh * (0.4 + focusDist * 1.6);
    let a = exp(-(r * r) / max(sigma * sigma, 1e-5)) * (0.16 - focusDist * 0.1);
    dust += a;
    tint += (0.9 + 0.2 * hash1(f * 29.5 + 3.0)) * a;
  }
  let col = sampleVideo(src, samp, v).rgb;
  // Dust is additive and slightly warm.
  return vec4f(col + dust * params.opacity * 0.35 * tint, 1.0);
}
