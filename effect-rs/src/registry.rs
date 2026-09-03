//! Effect catalog, mirroring effect-core's registry.

use crate::effect::{Effect, EffectMeta};
use crate::effects;

static NONE: effects::none::NoneEffect = effects::none::NoneEffect;
static POSTERIZE: effects::posterize::PosterizeEffect = effects::posterize::PosterizeEffect;
static RGBSPLIT0R: effects::rgbsplit0r::RgbSplit0rEffect = effects::rgbsplit0r::RgbSplit0rEffect;
static GLITCH: effects::glitch::GlitchEffect = effects::glitch::GlitchEffect;
static GLOW: effects::glow::GlowEffect = effects::glow::GlowEffect;

static CATALOG: [&dyn Effect; 5] = [&NONE, &POSTERIZE, &RGBSPLIT0R, &GLITCH, &GLOW];

/// Ported subset of the TS catalog (same ids as the TS registry).
pub fn catalog() -> &'static [&'static dyn Effect] {
    &CATALOG
}

pub fn get(id: &str) -> Option<&'static dyn Effect> {
    catalog().iter().copied().find(|e| e.id() == id)
}

pub fn catalog_meta() -> Vec<EffectMeta> {
    catalog().iter().map(|e| e.meta()).collect()
}
