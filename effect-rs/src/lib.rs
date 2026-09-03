//! effect-rs: CPU port of the effect-core WGSL catalog.
//!
//! Frames are RGBA8, top-left row order, matching WebGPU texture uploads.
//! Sampling reproduces the WGSL pipeline: rgba8unorm texels are read as
//! u8/255 f32, filtered bilinearly at texel centers, and written back with
//! clamp + round.

pub mod context;
pub mod effect;
pub mod effects;
pub mod engine;
pub mod frame;
pub mod math;
pub mod params;
pub mod registry;
pub mod sampler;

#[cfg(feature = "python")]
mod python;
#[cfg(feature = "wasm")]
mod wasm;

pub use context::{FrameContext, Timing};
pub use effect::{Effect, EffectError, EffectMeta, Result};
pub use engine::{render_batch, render_frame};
pub use frame::{Frame, FrameView, FrameViewMut};
pub use params::{defaults_from, resolve, ParamDef, ParamValues};
pub use registry::{catalog, catalog_meta, get};
