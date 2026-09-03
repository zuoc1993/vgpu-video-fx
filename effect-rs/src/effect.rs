//! Effect trait + error type.

use crate::{FrameContext, FrameView, FrameViewMut, ParamDef, ParamValues};
use serde::Serialize;
use std::fmt;

#[derive(Debug)]
pub struct EffectError(String);

impl EffectError {
    pub fn new(message: String) -> Self {
        EffectError(message)
    }
}

impl fmt::Display for EffectError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for EffectError {}

pub type Result<T> = std::result::Result<T, EffectError>;

/// Serializable metadata for UI/catalog listing (JSON shape matches
/// effect-core's EffectDefinition minus shader/uniforms).
#[derive(Clone, Debug, Serialize)]
pub struct EffectMeta {
    pub id: &'static str,
    pub name: &'static str,
    pub category: &'static str,
    pub description: &'static str,
    pub params: &'static [ParamDef],
}

pub trait Effect: Send + Sync {
    fn meta(&self) -> EffectMeta;

    /// Render one output frame. `values` is the resolved param map
    /// (`params::resolve`), `ctx` carries timing and sizes.
    fn render(&self, src: FrameView<'_>, dst: &mut FrameViewMut<'_>, values: &ParamValues, ctx: &FrameContext);

    fn id(&self) -> &'static str {
        self.meta().id
    }
    fn params(&self) -> &'static [ParamDef] {
        self.meta().params
    }
}
