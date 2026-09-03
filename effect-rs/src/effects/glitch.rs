//! glitch: horizontal tearing + RGB split + hash-driven bursts
//! (direct port of effects/glitch/effect.wgsl).

use crate::effect::{Effect, EffectMeta};
use crate::frame::to_u8;
use crate::math::{contain_uv, hash2, in_bounds, mix, mix3, step, wgsl_fract};
use crate::params::{get, param, ParamDef, ParamValues};
use crate::sampler::sample_linear;
use crate::{FrameContext, FrameView, FrameViewMut};

pub struct GlitchEffect;

static PARAMS: [ParamDef; 6] = [
    param("intensity", "强度", 0.0, 1.0, 0.01, 0.7),
    param("speed", "速度", 0.2, 4.0, 0.05, 1.4),
    param("slices", "条带数", 4.0, 80.0, 1.0, 28.0),
    param("rgbSplit", "RGB 分离", 0.0, 3.0, 0.01, 1.0),
    param("block", "色块撕裂", 0.0, 2.0, 0.01, 0.8),
    param("scanline", "扫描线", 0.0, 1.0, 0.01, 0.35),
];

#[inline]
fn sample_glitch(src: FrameView<'_>, uv: [f32; 2]) -> [f32; 4] {
    sample_linear(src, [wgsl_fract(uv[0]), uv[1].clamp(0.0, 1.0)])
}

// Magenta / lemon / cyan first — matches the reference columns.
#[inline]
fn glitch_tint(h: [f32; 2]) -> [f32; 3] {
    let i = (h[0] * 6.0) as u32;
    match i {
        0 => [1.0, 0.08, 0.72],
        1 => [1.0, 0.95, 0.32],
        2 => [0.08, 0.95, 1.0],
        3 => [0.25, 1.0, 0.28],
        4 => [1.0, 0.22, 0.42],
        _ => [0.22, 0.06, 0.82],
    }
}

#[inline]
fn wash(base: [f32; 3], tint: [f32; 3], amt: f32) -> [f32; 3] {
    let t = amt.clamp(0.0, 1.0);
    mix3(
        base,
        [
            base[0] * tint[0] * 1.35 + tint[0] * 0.22,
            base[1] * tint[1] * 1.35 + tint[1] * 0.22,
            base[2] * tint[2] * 1.35 + tint[2] * 0.22,
        ],
        t,
    )
}

impl Effect for GlitchEffect {
    fn meta(&self) -> EffectMeta {
        EffectMeta {
            id: "glitch",
            name: "Glitch",
            category: "故障",
            description: "水平撕裂、RGB 错位，爆发时叠品红 / 黄 / 青等半透明竖条和色块。",
            params: &PARAMS,
        }
    }

    fn render(&self, src: FrameView<'_>, dst: &mut FrameViewMut<'_>, values: &ParamValues, ctx: &FrameContext) {
        let intensity = get(values, &PARAMS, "intensity");
        let speed = get(values, &PARAMS, "speed");
        let slices = get(values, &PARAMS, "slices");
        let rgb_split = get(values, &PARAMS, "rgbSplit");
        let block = get(values, &PARAMS, "block");
        let scanline = get(values, &PARAMS, "scanline");
        let pi = std::f32::consts::PI;
        let dw = dst.width;
        let dh = dst.height;

        for y in 0..dh {
            let v = (y as f32 + 0.5) / dh as f32;
            let row = dst.row(y);
            for x in 0..dw {
                let u = (x as f32 + 0.5) / dw as f32;
                let vuv0 = contain_uv([u, v], ctx.resolution, ctx.video_size);
                if !in_bounds(vuv0) {
                    let i = x as usize * 4;
                    row[i] = 0;
                    row[i + 1] = 0;
                    row[i + 2] = 0;
                    row[i + 3] = 255;
                    continue;
                }
                let mut vuv = vuv0;

                let tick = (ctx.time * speed * 22.0).floor();
                let burst = hash2([tick, 0.7])[0];
                let on = step(0.35, burst) * intensity;
                let cover =
                    step(0.001, on) * mix(0.4, 0.78, on.clamp(0.0, 1.0)) * (block * 0.65 + 0.35).clamp(0.0, 1.2);

                let rowi = (vuv[1] * slices.max(4.0)).floor();
                let slice_n = hash2([rowi, tick]);
                vuv[0] += (slice_n[0] - 0.5) * 0.42 * on;
                vuv[0] += (hash2([(vuv[1] * 240.0).floor(), tick])[0] - 0.5) * 0.08 * on;

                let block_n = hash2([(vuv[0] * 14.0).floor() + tick, (vuv[1] * 8.0).floor() + 4.2]);
                if block_n[0] > 1.0 - block * 0.22 * on {
                    vuv[0] += (block_n[0] - 0.5) * 0.12 * on;
                    vuv[1] += (block_n[1] - 0.5) * 0.12 * on;
                }

                let split = rgb_split * on * 0.05;
                let r = sample_glitch(src, [vuv[0] + split, vuv[1]])[0];
                let g = sample_glitch(src, [vuv[0] - split * 0.35, vuv[1] + split * 0.15])[1];
                let b = sample_glitch(src, [vuv[0] - split, vuv[1]])[2];
                let mut color = [r, g, b];
                color = mix3(color, [color[2], color[0], color[1]], 0.22 * on);

                let scan = 0.5 + 0.5 * (vuv[1] * ctx.resolution[1] * pi).sin();
                for c in &mut color {
                    *c *= 1.0 - scanline * 0.45 * scan;
                    *c *= 1.0 + 0.7 * on;
                }

                let col = (vuv[0] * 3.0).floor();
                let col_h = hash2([col + 0.37, tick]);
                color = wash(color, glitch_tint(col_h), cover);

                let rect_h = hash2([tick, 8.1]);
                let rx = rect_h[0] * 0.4;
                let ry = rect_h[1] * 0.35;
                if vuv[0] > rx
                    && vuv[0] < rx + 0.28 + rect_h[0] * 0.3
                    && vuv[1] > ry
                    && vuv[1] < ry + 0.2 + rect_h[1] * 0.25
                {
                    color = wash(
                        color,
                        glitch_tint([rect_h[0] + 0.2, rect_h[1] + 0.1]),
                        cover * 0.85,
                    );
                }

                let edge = hash2([tick, 2.2]);
                if vuv[0] > 0.86 && edge[0] > 0.35 {
                    color = wash(color, [0.2, 0.05, 0.78], cover * 0.7);
                }

                let line = (vuv[1] * 96.0).floor();
                let line_h = hash2([line, tick + 5.0]);
                if line_h[0] > 0.93 {
                    color = wash(color, glitch_tint(line_h), cover * 0.9);
                }

                for c in &mut color {
                    *c = c.min(1.7);
                }
                let i = x as usize * 4;
                row[i] = to_u8(color[0]);
                row[i + 1] = to_u8(color[1]);
                row[i + 2] = to_u8(color[2]);
                row[i + 3] = 255;
            }
        }
    }
}
