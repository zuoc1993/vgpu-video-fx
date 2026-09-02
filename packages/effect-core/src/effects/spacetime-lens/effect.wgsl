// Spacetime lens, inspired by the 2D black-hole lensing in
// MolecularSadism/msg_shaders (Apache-2.0), itself based on Eric Bruneton's
// black hole shader (BSD-3). Simplified single-pass deflection + echo ring.
import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  radius: f32,
  strength: f32,
  echo: f32,
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
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let p = vec2f((v.x - 0.5) * ar, v.y - 0.5);
  let r = length(p);
  let rs = max(params.radius, 0.01);

  // Deflection ~ rs^2 / b: strong magnification, soft 1/r falloff.
  let defl = (rs * rs * params.strength) / max(r, rs * 0.3);
  // Tangential swirl tightens toward the hole.
  let ang = atan2(p.y, p.x) + params.swirl * (rs * rs) / max(r * r + rs * rs, 1e-4) * 0.75;
  let dir = vec2f(cos(ang), sin(ang)) * max(r - defl, 0.001);
  let sampleUv = dir / vec2f(ar, 1.0) + 0.5;
  var col = sampleVideo(src, samp, sampleUv).rgb;

  // Photon ring: inside the shadow the far side is reflected in.
  let echoR = (rs * rs) / max(r, rs * 0.4);
  let echoDir = vec2f(cos(ang + 3.14159), sin(ang + 3.14159)) * echoR;
  let echoUv = echoDir / vec2f(ar, 1.0) + 0.5;
  let inside = 1.0 - smoothstep(rs * 0.8, rs * 1.3, r);
  col = mix(col, sampleVideo(src, samp, echoUv).rgb, inside * params.echo);

  // Spectral ring glow.
  col += vec3f(0.45, 0.28, 0.65) * exp(-abs(r - rs) * 14.0) * params.echo * 0.6;
  return vec4f(min(col, vec3f(2.0)), 1.0);
}
