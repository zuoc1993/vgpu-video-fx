// Spectral ghost flare, ported from charbelmalo/PrismaticShadersPack (MIT).
// https://github.com/charbelmalo/PrismaticShadersPack
import { containUv } from "../shared/video.wgsl";

struct Params {
  time: f32,
  threshold: f32,
  strength: f32,
  size: f32,
  halo: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

fn sampleVideoW(u: vec2f) -> vec3f {
  return textureSampleLevel(src, samp, vec2f(fract(u.x), clamp(u.y, 0.0, 1.0)), 0.0).rgb;
}

// Simplified Planckian locus approximation: 380-780nm -> RGB.
fn wavelengthToRgb(wl: f32) -> vec3f {
  var c = vec3f(0.0);
  if (wl < 440.0) {
    c = vec3f(-(wl - 440.0) / 60.0, 0.0, 1.0);
  } else if (wl < 490.0) {
    c = vec3f(0.0, (wl - 440.0) / 50.0, 1.0);
  } else if (wl < 510.0) {
    c = vec3f(0.0, 1.0, -(wl - 510.0) / 20.0);
  } else if (wl < 580.0) {
    c = vec3f((wl - 510.0) / 70.0, 1.0, 0.0);
  } else if (wl < 645.0) {
    c = vec3f(1.0, -(wl - 645.0) / 65.0, 0.0);
  } else {
    c = vec3f(1.0, 0.0, 0.0);
  }
  var factor = 1.0;
  if (wl < 420.0) {
    factor = 0.3 + 0.7 * (wl - 380.0) / 40.0;
  } else if (wl > 700.0) {
    factor = 0.3 + 0.7 * (780.0 - wl) / 80.0;
  }
  return c * factor;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let color = sampleVideoW(v);
  let center = vec2f(0.5);
  let dir = v - center;
  let dist = length(dir);

  let lum = dot(color, vec3f(0.2126, 0.7152, 0.0722));
  let mask = smoothstep(params.threshold - 0.1, params.threshold + 0.1, lum) * params.strength;

  // Spectral ghost samples along the light -> center axis.
  var flare = vec3f(0.0);
  for (var i = 0u; i < 6u; i += 1u) {
    let t = f32(i) / 5.0;
    let offsetScale = (0.02 + 0.08 * t) * dist * mix(1.0, params.size * 10.0, 0.5);
    let ghost1 = center + dir * 1.5 + dir * offsetScale;
    let ghost2 = center + dir * 0.7 - dir * offsetScale * 0.5;
    let rgb = wavelengthToRgb(380.0 + t * 400.0);
    flare += sampleVideoW(ghost1) * rgb * mask * 0.4;
    flare += sampleVideoW(ghost2) * rgb * mask * 0.25;
  }

  // Broad halo around bright regions.
  let haloWidth = 0.03;
  let haloColor = (sampleVideoW(v + dir * haloWidth) + sampleVideoW(v - dir * haloWidth)) * 0.5;
  let haloMask = smoothstep(params.threshold * 0.3, params.threshold, lum);
  flare += haloColor * haloMask * 0.2 * params.halo;

  // Rainbow fringing on highlights.
  let caOffset = dir * params.size * 0.003 * dist;
  var caColor = color;
  caColor.r = sampleVideoW(v + caOffset).r;
  caColor.b = sampleVideoW(v - caOffset).b;

  return vec4f(min(caColor + flare, vec3f(2.0)), 1.0);
}
