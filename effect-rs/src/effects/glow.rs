//! glow: 8-tap ring halo (port of effects/glow).

use crate::effect::{Effect, EffectMeta};
use crate::frame::to_u8;
use crate::math::{contain_uv, in_bounds, smoothstep};
use crate::params::{get, param, ParamDef, ParamValues};
use crate::sampler::sample_video;
use crate::{FrameContext, FrameView, FrameViewMut};

pub struct GlowEffect;

static PARAMS: [ParamDef; 3] = [
    param("blur", "光晕半径", 1.0, 24.0, 0.5, 9.0),
    param("amount", "光强", 0.0, 2.0, 0.05, 1.1),
    param("threshold", "提亮阈值", 0.0, 1.0, 0.01, 0.08),
];

const DIR: [[f32; 2]; 8] = [
    [1.0, 0.0],
    [0.7071, 0.7071],
    [0.0, 1.0],
    [-0.7071, 0.7071],
    [-1.0, 0.0],
    [-0.7071, -0.7071],
    [0.0, -1.0],
    [0.7071, -0.7071],
];

impl Effect for GlowEffect {
    fn meta(&self) -> EffectMeta {
        EffectMeta {
            id: "glow",
            name: "Glow",
            category: "风格化",
            description: "frei0r glow 复刻（单 pass 近似）：八向采样光环叠加提亮。",
            params: &PARAMS,
        }
    }

    fn render(&self, src: FrameView<'_>, dst: &mut FrameViewMut<'_>, values: &ParamValues, ctx: &FrameContext) {
        let blur = get(values, &PARAMS, "blur");
        let amount = get(values, &PARAMS, "amount");
        let threshold = get(values, &PARAMS, "threshold");
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
                let base = sample_video(src, vuv);
                let r = blur / ctx.resolution[0];
                let mut acc = [0.0f32; 3];
                for d in DIR {
                    let tap = sample_video(src, [vuv[0] + d[0] * r, vuv[1] + d[1] * r]);
                    acc[0] += tap[0];
                    acc[1] += tap[1];
                    acc[2] += tap[2];
                }
                acc[0] /= 8.0;
                acc[1] /= 8.0;
                acc[2] /= 8.0;
                let lit = smoothstep(threshold, threshold + 0.5, base[0].max(base[1]).max(base[2]));
                let glow = (0.7 + 0.3 * lit) * amount;
                let i = x as usize * 4;
                row[i] = to_u8(base[0] + acc[0] * glow);
                row[i + 1] = to_u8(base[1] + acc[1] * glow);
                row[i + 2] = to_u8(base[2] + acc[2] * glow);
                row[i + 3] = 255;
            }
        }
    }
}
