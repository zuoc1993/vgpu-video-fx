//! posterize: frei0r-style band quantization (port of effects/posterize).

use crate::effect::{Effect, EffectMeta};
use crate::frame::to_u8;
use crate::math::contain_uv;
use crate::params::{get, param, ParamDef, ParamValues};
use crate::sampler::sample_video;
use crate::{FrameContext, FrameView, FrameViewMut};

pub struct PosterizeEffect;

static PARAMS: [ParamDef; 1] = [param("levels", "量化级数", 0.01, 1.0, 0.01, 0.02)];

#[inline]
fn quantize(v: f32, bands: f32, inv: f32) -> u8 {
    to_u8((v * bands + 0.5).floor() * inv)
}

impl Effect for PosterizeEffect {
    fn meta(&self) -> EffectMeta {
        EffectMeta {
            id: "posterize",
            name: "Posterize",
            category: "风格化",
            description: "frei0r posterize 复刻：色阶量化海报化，值越低越猛。",
            params: &PARAMS,
        }
    }

    fn render(&self, src: FrameView<'_>, dst: &mut FrameViewMut<'_>, values: &ParamValues, ctx: &FrameContext) {
        let levels = get(values, &PARAMS, "levels");
        // frei0r semantics: low levels = few bands = harsh quantization.
        let bands = 2.0 + (levels.clamp(0.0, 1.0) * 254.0).floor();
        let inv = 1.0 / bands;

        // Same-size fast path: uv maps to texel centers, so this is a pure
        // per-pixel map over contiguous bytes — branch-free and shaped for
        // LLVM auto-vectorization (chunks_exact(4)).
        if src.width == dst.width && src.height == dst.height {
            for (d, s) in dst.data.chunks_exact_mut(4).zip(src.data.chunks_exact(4)) {
                d[0] = quantize(s[0] as f32 / 255.0, bands, inv);
                d[1] = quantize(s[1] as f32 / 255.0, bands, inv);
                d[2] = quantize(s[2] as f32 / 255.0, bands, inv);
                d[3] = 255;
            }
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
                row[i] = quantize(c[0], bands, inv);
                row[i + 1] = quantize(c[1], bands, inv);
                row[i + 2] = quantize(c[2], bands, inv);
                row[i + 3] = 255;
            }
        }
    }
}
