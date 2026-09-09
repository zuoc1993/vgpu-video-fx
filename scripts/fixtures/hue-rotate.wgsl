// Test-only shader: exposes shared/f0r.wgsl hueRotate without any other
// effect pipeline or clamping so scripts/check-effect-regressions.mjs can
// verify the matrix orientation directly.
import { hueRotate } from "../../packages/effect-core/src/effects/shared/f0r.wgsl";

struct Params {
  amount: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let c = textureSampleLevel(src, samp, uv, 0.0).rgb;
  return vec4f(hueRotate(c, params.amount), 1.0);
}
