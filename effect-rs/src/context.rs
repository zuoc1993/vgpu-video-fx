//! Per-frame uniforms, mirroring effect-core's FrameContext.

#[derive(Clone, Copy, Debug, Default)]
pub struct Timing {
    pub time: f32,
    pub delta_time: f32,
    pub video_time: f32,
    pub video_duration: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct FrameContext {
    pub time: f32,
    pub delta_time: f32,
    pub video_time: f32,
    pub video_duration: f32,
    /// Output (destination) size in pixels.
    pub resolution: [f32; 2],
    /// 1 / resolution.
    pub texel: [f32; 2],
    /// Input (source video) size in pixels.
    pub video_size: [f32; 2],
}

impl FrameContext {
    pub fn new(out_width: u32, out_height: u32, src_width: u32, src_height: u32, timing: Timing) -> Self {
        FrameContext {
            time: timing.time,
            delta_time: timing.delta_time,
            video_time: timing.video_time,
            video_duration: timing.video_duration,
            resolution: [out_width as f32, out_height as f32],
            texel: [1.0 / out_width as f32, 1.0 / out_height as f32],
            video_size: [src_width as f32, src_height as f32],
        }
    }
}
