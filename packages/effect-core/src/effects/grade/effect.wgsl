// Cinematic grade: lift / gamma / gain + saturation, semantics from
// charbelmalo/PrismaticShadersPack vignette_grade (MIT).
import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  lift: f32,
  gamma: f32,
  gain: f32,
  saturation: f32,
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
  let col = sampleVideo(src, samp, v).rgb;
  // LGG (lift range -1..1 maps to -0.5..0.5, gamma 0.4..1.8, gain 0.6..1.6; gain 1.0 is neutral).
  let lifted = max(col + params.lift * 0.5, vec3f(0.0));
  let graded = pow(lifted, vec3f(1.0 / max(params.gamma, 0.2))) * params.gain;
  // Saturation around luminance.
  let lum = dot(graded, vec3f(0.2126, 0.7152, 0.0722));
  let sat = clamp(params.saturation, 0.0, 2.0);
  let out = lum + (graded - lum) * sat;
  return vec4f(clamp(out, vec3f(0.0), vec3f(1.4)), 1.0);
}
