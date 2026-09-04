
struct VgpuFullscreenVertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};
@vertex fn vgpu_fullscreen_vs(@builtin(vertex_index) vi: u32) -> VgpuFullscreenVertexOut {
  var pos = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  var uv = array<vec2f, 3>(vec2f(0.0, 1.0), vec2f(2.0, 1.0), vec2f(0.0, -1.0));
  var out: VgpuFullscreenVertexOut;
  out.position = vec4f(pos[vi], 0.0, 1.0);
  out.uv = uv[vi];
  return out;
}
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/distort0r/effect.wgsl
struct _vgsl_55925c05__Params {
  time: f32,
  amplitude: f32,
  freq: f32,
  speed: f32,
  velocity: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_55925c05__Params;

// perlin2d sigma ~0.3; remap to [-1, 1] here.
fn _vgsl_55925c05__np(p: vec2f) -> vec2f {
  return vec2f(_vgsl_bbb85e49__perlin2d(p), _vgsl_bbb85e49__perlin2d(p + vec2f(57.3, 21.7))) * 3.3;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let t = params.time * params.speed;
  let n = _vgsl_55925c05__np(v * params.freq + vec2f(t * params.velocity * 0.7, t));
  return _vgsl_35d1d59a__sampleVideo(src, samp, v + n * params.amplitude * 0.08);
}

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/shared/video.wgsl
// Pure helpers: no @group/@binding. Entry shaders own resources.

fn _vgsl_35d1d59a__containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
  let canvasSafe = max(canvas, vec2f(1.0));
  let videoSafe = max(video, vec2f(1.0));
  let canvasAspect = canvasSafe.x / canvasSafe.y;
  let videoAspect = videoSafe.x / videoSafe.y;
  var scale = vec2f(1.0);
  if (canvasAspect > videoAspect) {
    scale.x = videoAspect / canvasAspect;
  } else {
    scale.y = canvasAspect / videoAspect;
  }
  return (uv - vec2f(0.5)) / scale + vec2f(0.5);
}

fn _vgsl_35d1d59a__sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}









// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/noise/perlin/index.wgsl
// Improved Perlin noise (Perlin 2002: quintic fade + cube-edge gradient set) in 2D/3D, plus the
// amplitude-normalized FBM that wraps each one.
//
// Numeric contract -- the published field *is* the API here, so treat every constant below as
// frozen (locked by tests/perlin.test.ts):
//   * range is a guaranteed open (-1, 1), never clipped. The trilinear/quintic blend is a convex
//     combination of the corner dot products, so |value| <= max_i |g_i . d_i|; the raw suprema are
//     1/sqrt(2) = 0.7071067812 (2D, attained at f = (0.5, 0.5)) and 1.0363538112 (3D), and the
//     normalizers below are strictly *below* 1/sup, so the bound is a proof rather than an
//     observation. Do not "fix" them toward the folkloric 2.2x of webgl-noise's cnoise: that
//     value provably exceeds 1 and forces every consumer to clamp.
//   * typical amplitude is much smaller than the bound (sigma ~= 0.305 in 2D, 0.260 in 3D):
//     consumers should `remap`, not `saturate`.
//   * exactly 0 at every integer lattice point (all corner offsets are zero vectors there, and
//     fade(0) = 0), which is the highest-value regression signal for a fade or corner-offset bug.
//
// Determinism contract, inherited from ../internal/gradient.wgsl: no lookup tables, no
// sin/cos/sqrt/inverseSqrt/pow, integer pcg hashing only -- so *which* gradient a cell gets is
// bit-identical on every backend and reproducible by the f32-exact TS reference in
// tests/perlin.test.ts.
//
// Reference (algorithm only, no code copied): Ken Perlin, "Improving Noise", SIGGRAPH 2002.
          

// 1 / 0.7071067812 = 1.41421356..., truncated *downward* so the range stays strictly inside
// (-1, 1): max |perlin2d| = 0.99996.
const _vgsl_bbb85e49__perlinNormalize2: f32 = 1.4142;
// 1 / 1.0363538112 = 0.96491..., with ~1% margin against residual error in the numeric sup search:
// max |perlin3d| = 0.99956.


fn _vgsl_bbb85e49__perlin2d(position: vec2f) -> f32 {
  let base = floor(position);
  // vec2i(floor(p)) -- never vec2i(p): truncation toward zero would collapse the cells on both
  // sides of the origin into one, which is a visible seam for negative coordinates.
  let cell = vec2i(base);
  let f = position - base;
  let u = _vgsl_a03dd8cd__noiseFade2(f);
  let d00 = _vgsl_a03dd8cd__gradDot2(_vgsl_a03dd8cd__gradIndex2(cell), f);
  let d10 = _vgsl_a03dd8cd__gradDot2(_vgsl_a03dd8cd__gradIndex2(cell + vec2i(1, 0)), f - vec2f(1.0, 0.0));
  let d01 = _vgsl_a03dd8cd__gradDot2(_vgsl_a03dd8cd__gradIndex2(cell + vec2i(0, 1)), f - vec2f(0.0, 1.0));
  let d11 = _vgsl_a03dd8cd__gradDot2(_vgsl_a03dd8cd__gradIndex2(cell + vec2i(1, 1)), f - vec2f(1.0, 1.0));
  return _vgsl_bbb85e49__perlinNormalize2 * mix(mix(d00, d10, u.x), mix(d01, d11, u.x), u.y);
}



// Fractal Brownian motion, amplitude-normalized: `sum / weight` with `weight` the sum of the
// amplitudes. That division is what keeps the (-1, 1) guarantee alive across octaves, because
// |sum| <= weight by construction.
//
// Both clamps are silent and deliberate:
//   * `octaves` in [1, 16] bounds the loop -- a dynamic count coming from a uniform could
//     otherwise hang the GPU;
//   * `gain` in [0, 1] keeps `weight` equal to the sum of |amplitude|, which the range proof needs
//     (a negative gain would cancel terms in `weight` while still adding magnitude to `sum`).
// `weight >= 1` always (the first amplitude is 1), so the division is never by zero.
//
// Free invariant, asserted by the tests: fbmPerlin2d(p, 1, lacunarity, gain) == perlin2d(p) exactly.


// Cost model: one perlin3d is 8 pcg3d hashes, so a 6-octave call is 48 -- prefer fbmPerlin2d when
// the third axis only carries animation.


// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/noise/internal/gradient.wgsl
// Shared, table-free gradient core for the gradient-noise families (perlin/, simplex/).
//
// Private module: it is intentionally absent from this package's `package.json` exports, so the
// only way in is a relative import from a sibling noise module
// (`import { gradDot3 } from "../internal/gradient.wgsl";`). The declarations still carry `export`
// because the resolver keys its import graph off that literal token
// (packages/wgsl/src/runtime/parser.ts) -- `export` here means "importable by a relative sibling",
// not "public API".
//
// Determinism contract (locked by tests/noise-gradient.test.ts):
//   * no `array<...>` anywhere: permutation/gradient tables cost shader text in every consumer and
//     backends expand or spill them anyway, buying nothing over a few `select`s.
//   * no `sin`/`cos`/`sqrt`/`inverseSqrt`/`pow` anywhere: their accuracy is implementation-defined
//     (WGSL allows several ulp), so an angle-based gradient would drift per driver and make golden
//     tests flaky. Everything below is `+ - * select` plus the exactly specified u32 hash ops, so
//     *which* gradient a cell gets is bit-identical on every backend.
//
// References (algorithms, no code copied): Perlin 2002 "Improving Noise" (quintic fade, 12
// cube-edge gradients), Perlin 2001 / Gustavson "Simplex noise demystified".
      

// 1 / sqrt(2), spelled as a literal because `sqrt` is banned above.
const _vgsl_a03dd8cd__noiseInvSqrt2: f32 = 0.7071067811865476;

// Gradient selector: pcg2d/pcg3d over the bit pattern of the integer cell (same idiom as
// voronoi2d/voronoi3d), giving a 2^32-cell period instead of the folklore period-289 float hash.
fn _vgsl_a03dd8cd__gradIndex2(cell: vec2i) -> u32 { return _vgsl_9a0b5690__pcg2d(bitcast<vec2u>(cell)).x & 7u; }

// 12 gradients out of 32 bits: bias is 4/2^32 ~= 1e-9.


// 8 unit gradients. index 0..3 -> (1,0) (-1,0) (0,1) (0,-1);  4..7 -> (+-1,+-1)/sqrt(2).
// Unit length keeps the 2D field's amplitude bound closed-form (raw sup |perlin2d| = 1/sqrt(2)).
fn _vgsl_a03dd8cd__gradDot2(index: u32, d: vec2f) -> f32 {
  let axis = select(d.x, d.y, (index & 2u) != 0u);
  let axisDot = select(axis, -axis, (index & 1u) != 0u);
  let sx = select(d.x, -d.x, (index & 1u) != 0u);
  let sy = select(d.y, -d.y, (index & 2u) != 0u);
  return select(axisDot, _vgsl_a03dd8cd__noiseInvSqrt2 * (sx + sy), index >= 4u);
}

// Perlin's 12 cube-edge gradients (+-1,+-1,0) (+-1,0,+-1) (0,+-1,+-1), length sqrt(2): the dot
// product costs one add plus two negations, no multiplies.
// index/4 selects the component pair: 0 -> (x,y), 1 -> (x,z), 2 -> (y,z); bits 0/1 are the signs.


// Quintic fade 6t^5 - 15t^4 + 10t^3 (Perlin 2002): zero first *and* second derivative at the cell
// boundaries, so lattice seams stay invisible in derivatives (normals) too.
fn _vgsl_a03dd8cd__noiseFade2(t: vec2f) -> vec2f { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }


// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector


fn _vgsl_9a0b5690__pcg2d(value: vec2u) -> vec2u {
  // 2D multi-output variant cross-mixes with the LCG multiplier instead of pcg3d's y*z pattern.
  var hashed = value * 1664525u + 1013904223u;
  hashed.x = hashed.x + hashed.y * 1664525u;
  hashed.y = hashed.y + hashed.x * 1664525u;
  hashed = hashed ^ (hashed >> vec2u(16u));
  hashed.x = hashed.x + hashed.y * 1664525u;
  hashed.y = hashed.y + hashed.x * 1664525u;
  hashed = hashed ^ (hashed >> vec2u(16u));
  return hashed;
}










