//! Bit-exact ports of the WGSL helpers the effects rely on.

// ---- @vgpu/wgsl-std/hash -------------------------------------------------
// Wellons lowbias32 + pcg2d, u32 wrapping arithmetic; identical to WGSL.

#[inline]
pub fn hash_u32(value: u32) -> u32 {
    let mut h = value;
    h = (h ^ (h >> 16)).wrapping_mul(0x7feb_352d);
    h = (h ^ (h >> 15)).wrapping_mul(0x846c_a68b);
    h ^ (h >> 16)
}

#[inline]
pub fn pcg2d(value: [u32; 2]) -> [u32; 2] {
    let mut x = value[0].wrapping_mul(1664525).wrapping_add(1013904223);
    let mut y = value[1].wrapping_mul(1664525).wrapping_add(1013904223);
    x = x.wrapping_add(y.wrapping_mul(1664525));
    y = y.wrapping_add(x.wrapping_mul(1664525));
    x ^= x >> 16;
    y ^= y >> 16;
    x = x.wrapping_add(y.wrapping_mul(1664525));
    y = y.wrapping_add(x.wrapping_mul(1664525));
    x ^= x >> 16;
    y ^= y >> 16;
    [x, y]
}

#[inline]
pub fn unit_float(hash: u32) -> f32 {
    (hash >> 8) as f32 * (1.0 / 16777216.0)
}

/// hash2(seed) — bitcast f32 -> u32 per component, then pcg2d.
#[inline]
pub fn hash2(seed: [f32; 2]) -> [f32; 2] {
    let h = pcg2d([seed[0].to_bits(), seed[1].to_bits()]);
    [unit_float(h[0]), unit_float(h[1])]
}

// ---- shared/video.wgsl ----------------------------------------------------

/// Letterbox-fit uv: port of containUv.
#[inline]
pub fn contain_uv(uv: [f32; 2], canvas: [f32; 2], video: [f32; 2]) -> [f32; 2] {
    let cs = [canvas[0].max(1.0), canvas[1].max(1.0)];
    let vs = [video[0].max(1.0), video[1].max(1.0)];
    let ca = cs[0] / cs[1];
    let va = vs[0] / vs[1];
    let mut scale = [1.0f32, 1.0f32];
    if ca > va {
        scale[0] = va / ca;
    } else {
        scale[1] = ca / va;
    }
    [
        (uv[0] - 0.5) / scale[0] + 0.5,
        (uv[1] - 0.5) / scale[1] + 0.5,
    ]
}

#[inline]
pub fn in_bounds(uv: [f32; 2]) -> bool {
    uv[0] >= 0.0 && uv[0] <= 1.0 && uv[1] >= 0.0 && uv[1] <= 1.0
}

// ---- WGSL builtins with different Rust semantics ---------------------------

/// WGSL fract(x) = x - floor(x), always in [0, 1) — unlike f32::fract which
/// keeps the sign of x.
#[inline]
pub fn wgsl_fract(x: f32) -> f32 {
    x - x.floor()
}

/// WGSL step(edge, x) = if x < edge { 0 } else { 1 }.
#[inline]
pub fn step(edge: f32, x: f32) -> f32 {
    if x < edge {
        0.0
    } else {
        1.0
    }
}

/// WGSL smoothstep.
#[inline]
pub fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
pub fn mix(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
pub fn mix3(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)]
}
