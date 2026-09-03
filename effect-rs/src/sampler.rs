//! Bilinear sampler matching WebGPU linear filtering of rgba8unorm textures:
//! texel values are u8/255 f32, taps are fetched at clamped integer coords,
//! weights from the fractional part of uv * size - 0.5.

use crate::frame::FrameView;
use crate::math::in_bounds;

#[inline]
fn texel_f(src: FrameView<'_>, x: i32, y: i32) -> [f32; 4] {
    let cx = x.clamp(0, src.width as i32 - 1) as u32;
    let cy = y.clamp(0, src.height as i32 - 1) as u32;
    let t = src.texel(cx, cy);
    [
        t[0] as f32 / 255.0,
        t[1] as f32 / 255.0,
        t[2] as f32 / 255.0,
        t[3] as f32 / 255.0,
    ]
}

/// Linear-filtered sample at uv (any value; edges clamp to border texels).
#[inline]
pub fn sample_linear(src: FrameView<'_>, uv: [f32; 2]) -> [f32; 4] {
    let x = uv[0] * src.width as f32 - 0.5;
    let y = uv[1] * src.height as f32 - 0.5;
    let x0 = x.floor() as i32;
    let y0 = y.floor() as i32;
    let fx = x - x0 as f32;
    let fy = y - y0 as f32;

    let c00 = texel_f(src, x0, y0);
    let c10 = texel_f(src, x0 + 1, y0);
    let c01 = texel_f(src, x0, y0 + 1);
    let c11 = texel_f(src, x0 + 1, y0 + 1);

    let mut out = [0.0f32; 4];
    for i in 0..4 {
        let top = c00[i] + (c10[i] - c00[i]) * fx;
        let bot = c01[i] + (c11[i] - c01[i]) * fx;
        out[i] = top + (bot - top) * fy;
    }
    out
}

/// Port of shared/video.wgsl sampleVideo: out-of-[0,1] -> opaque black.
#[inline]
pub fn sample_video(src: FrameView<'_>, uv: [f32; 2]) -> [f32; 4] {
    if !in_bounds(uv) {
        return [0.0, 0.0, 0.0, 1.0];
    }
    sample_linear(src, uv)
}
