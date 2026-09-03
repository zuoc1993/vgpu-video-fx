//! rgbsplit0r: frei0r channel offset (port of effects/rgbsplit0r).

use crate::effect::{Effect, EffectMeta};
use crate::frame::to_u8;
use crate::math::{contain_uv, in_bounds, wgsl_fract};
use crate::params::{get, param, ParamDef, ParamValues};
use crate::sampler::sample_linear;
use crate::{FrameContext, FrameView, FrameViewMut};

pub struct RgbSplit0rEffect;

static PARAMS: [ParamDef; 2] = [
    param("vertical", "垂直分离", 0.0, 1.0, 0.01, 0.9),
    param("horizontal", "水平分离", 0.0, 1.0, 0.01, 0.9),
];

#[inline]
fn channel(src: FrameView<'_>, uv: [f32; 2], axis: f32) -> [f32; 3] {
    // frei0r semantics: 0.5 is the neutral point, 1.0 maximal offset.
    let full = (axis - 0.5) * 0.12;
    let uv2 = [uv[0] + full, uv[1] - full];
    let c = sample_linear(src, [wgsl_fract(uv2[0]), uv2[1].clamp(0.0, 1.0)]);
    [c[0], c[1], c[2]]
}

impl Effect for RgbSplit0rEffect {
    fn meta(&self) -> EffectMeta {
        EffectMeta {
            id: "rgbsplit0r",
            name: "Rgb split0r",
            category: "故障",
            description: "frei0r rgbsplit0r 复刻：RGB 通道错位，色差分离（0.5 为中性点）。",
            params: &PARAMS,
        }
    }

    fn render(&self, src: FrameView<'_>, dst: &mut FrameViewMut<'_>, values: &ParamValues, ctx: &FrameContext) {
        let horizontal = get(values, &PARAMS, "horizontal");
        let vertical = get(values, &PARAMS, "vertical");
        let dw = dst.width;
        let dh = dst.height;
        for y in 0..dh {
            let v = (y as f32 + 0.5) / dh as f32;
            let row = dst.row(y);
            for x in 0..dw {
                let u = (x as f32 + 0.5) / dw as f32;
                let vuv = contain_uv([u, v], ctx.resolution, ctx.video_size);
                if !in_bounds(vuv) {
                    let i = x as usize * 4;
                    row[i] = 0;
                    row[i + 1] = 0;
                    row[i + 2] = 0;
                    row[i + 3] = 255;
                    continue;
                }
                let r = channel(src, vuv, horizontal)[0];
                let b = channel(src, vuv, vertical)[2];
                let g = channel(src, vuv, 0.5)[1];
                let i = x as usize * 4;
                row[i] = to_u8(r);
                row[i + 1] = to_u8(g);
                row[i + 2] = to_u8(b);
                row[i + 3] = 255;
            }
        }
    }
}
