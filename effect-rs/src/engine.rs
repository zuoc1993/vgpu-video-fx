//! Stateless render entry points.

use crate::context::{FrameContext, Timing};
use crate::effect::{Effect, EffectError, Result};
use crate::frame::Frame;
use crate::params::{resolve, ParamValues};

pub fn render_frame(
    effect: &dyn Effect,
    values: &ParamValues,
    src: &Frame,
    out_width: u32,
    out_height: u32,
    timing: Timing,
) -> Result<Frame> {
    if src.width < 1 || src.height < 1 || out_width < 1 || out_height < 1 {
        return Err(EffectError::new("invalid frame size".into()));
    }
    if src.data.len() < src.width as usize * src.height as usize * 4 {
        return Err(EffectError::new("RGBA buffer too small".into()));
    }
    let resolved = resolve(effect.params(), values);
    let ctx = FrameContext::new(out_width, out_height, src.width, src.height, timing);
    let mut dst = Frame::new(out_width, out_height);
    effect.render(src.view(), &mut dst.view_mut(), &resolved, &ctx);
    Ok(dst)
}

/// Render a batch of same-sized frames. Output size matches input size,
/// mirroring effect-core's renderBatch (time/deltaTime derive from `times`).
pub fn render_batch(
    effect: &dyn Effect,
    values: &ParamValues,
    frames: &[Frame],
    times: &[f32],
    video_duration: f32,
) -> Result<Vec<Frame>> {
    if frames.len() != times.len() {
        return Err(EffectError::new(format!(
            "frames/times length mismatch: {} vs {}",
            frames.len(),
            times.len()
        )));
    }
    if frames.is_empty() {
        return Ok(Vec::new());
    }
    let (w, h) = (frames[0].width, frames[0].height);
    for f in frames {
        if f.width != w || f.height != h {
            return Err(EffectError::new("render_batch: mixed frame sizes".into()));
        }
    }
    let timings: Vec<Timing> = times
        .iter()
        .enumerate()
        .map(|(i, &t)| Timing {
            time: t,
            delta_time: if i == 0 { 0.0 } else { t - times[i - 1] },
            video_time: t,
            video_duration,
        })
        .collect();

    #[cfg(feature = "rayon")]
    {
        use rayon::prelude::*;
        frames
            .par_iter()
            .zip(timings.par_iter())
            .map(|(f, t)| render_frame(effect, values, f, w, h, *t))
            .collect()
    }
    #[cfg(not(feature = "rayon"))]
    {
        frames
            .iter()
            .zip(timings.iter())
            .map(|(f, t)| render_frame(effect, values, f, w, h, *t))
            .collect()
    }
}
