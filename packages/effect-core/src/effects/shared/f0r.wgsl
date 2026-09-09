// Shared helpers for the frei0r-ported effects. Pure math, no resources.

import { pcg2d, unitFloat, hash1 } from "@vgpu/wgsl-std/hash";
import { sampleVideoClamp } from "./video.wgsl";

export fn lumOf(c: vec3f) -> f32 {
  return dot(c, vec3f(0.2126, 0.7152, 0.0722));
}

// Bilinear vector value noise in [-1, 1]. Cheap and seamless by design.
fn cornerNoise(cell: vec2i) -> vec2f {
  let q = pcg2d(bitcast<vec2u>(cell));
  return vec2f(unitFloat(q.x), unitFloat(q.y)) * 2.0 - 1.0;
}

export fn vnoise2(p: vec2f) -> vec2f {
  let i = floor(p);
  let f = p - i;
  let u = f * f * (3.0 - 2.0 * f);
  let ic = vec2i(i);
  let a = cornerNoise(ic);
  let b = cornerNoise(ic + vec2i(1, 0));
  let c = cornerNoise(ic + vec2i(0, 1));
  let d = cornerNoise(ic + vec2i(1, 1));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4x4 ordered dither threshold in [0, 1) for a pixel coordinate.
export fn bayer4(coords: vec2u) -> f32 {
  const M = array<f32, 16>(
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0,
  );
  let idx = coords.y % 4u * 4u + coords.x % 4u;
  return (M[idx] + 0.5) / 16.0;
}

// Ink-dot halftone cell for a rotated grid. Returns 1 inside the dot, 0 outside.
// ink in [0, 1] is the channel value: brighter channel -> bigger dot.
export fn halftoneDot(p: vec2f, angle: f32, freq: f32, ink: f32) -> f32 {
  let c = cos(angle);
  let s = sin(angle);
  let g = mat2x2(c, s, -s, c) * p * freq;
  let lattice = fract(g + 0.5) - 0.5;
  let d = length(lattice);
  return step(d, sqrt(max(ink, 0.0) / 3.14159265));
}

// 3x3 Sobel magnitude on luminance, in [0, ~4]. texel is one pixel in uv units.
export fn sobelMag(src: texture_2d<f32>, samp: sampler, uv: vec2f, texel: vec2f) -> f32 {
  var l = array<f32, 9>();
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let idx = (dy + 1) * 3 + (dx + 1);
      l[idx] = lumOf(sampleVideoClamp(src, samp, uv + vec2f(f32(dx), f32(dy)) * texel).rgb);
    }
  }
  let gx = (l[2] + 2.0 * l[5] + l[8]) - (l[0] + 2.0 * l[3] + l[6]);
  let gy = (l[6] + 2.0 * l[7] + l[8]) - (l[0] + 2.0 * l[1] + l[2]);
  return sqrt(gx * gx + gy * gy);
}

// Rotate hue around a fixed axis by t (in turns) with a cheap 3x3 rotation.
export fn hueRotate(c: vec3f, t: f32) -> vec3f {
  let a = t * 6.2831853;
  let ca = cos(a);
  let sa = sin(a);
  // WGSL matrices are column-major: pass the columns of the Rec.601 hue
  // rotation matrix. Passing its rows here transposes the rotation and breaks
  // luminance preservation (a pure red would jump from luma 0.299 to ~0.46).
  let m = mat3x3(
    0.299 + 0.701 * ca + 0.168 * sa, 0.299 - 0.299 * ca - 0.328 * sa, 0.299 - 0.300 * ca + 1.250 * sa,
    0.587 - 0.587 * ca + 0.330 * sa, 0.587 + 0.413 * ca + 0.035 * sa, 0.587 - 0.588 * ca - 1.050 * sa,
    0.114 - 0.114 * ca - 0.497 * sa, 0.114 - 0.114 * ca + 0.292 * sa, 0.114 + 0.886 * ca - 0.203 * sa,
  );
  return m * c;
}

// Stable random offset per cell row, driven by an integer tick.
export fn perCell(seed: vec2f, tick: f32) -> vec2f {
  return vec2f(hash1(seed.x + tick), hash1(seed.y + tick)) * 2.0 - 1.0;
}
