//! none: passthrough with letterbox fit (port of effects/none).

use crate::effect::{Effect, EffectMeta};
use crate::frame::to_u8;
use crate::math::contain_uv;
use crate::params::{ParamDef, ParamValues};
use crate::sampler::sample_video;
use crate::{FrameContext, FrameView, FrameViewMut};

pub struct NoneEffect;

static PARAMS: [ParamDef; 0] = [];

impl Effect for NoneEffect {
    fn meta(&self) -> EffectMeta {
        EffectMeta {
            id: "none",
            name: "原片",
            category: "基础",
            description: "不处理，只按画布比例完整显示视频。",
            params: &PARAMS,
        }
    }

    fn render(&self, src: FrameView<'_>, dst: &mut FrameViewMut<'_>, _values: &ParamValues, ctx: &FrameContext) {
        // Same-size frames sample texel centers exactly (contain_uv identity +
        // bilinear at fx=fy=0), so a straight copy matches the GPU result.
        if src.width == dst.width && src.height == dst.height {
            dst.data.copy_from_slice(src.data);
            return;
        }
        let dw = dst.width;
        let dh = dst.height;
        for y in 0..dh {
            let v = (y as f32 + 0.5) / dh as f32;
            let row = dst.row(y);
            for x in 0..dw {
                let u = (x as f32 + 0.5) / dw as f32;
                let vuv = contain_uv([u, v], ctx.resolution, ctx.video_size);
                let c = sample_video(src, vuv);
                let i = x as usize * 4;
                row[i] = to_u8(c[0]);
                row[i + 1] = to_u8(c[1]);
                row[i + 2] = to_u8(c[2]);
                row[i + 3] = to_u8(c[3]);
            }
        }
    }
}
