//! Effect parameter definitions, mirroring effect-core's ParamDef.

use serde::Serialize;

pub type ParamValues = std::collections::HashMap<String, f32>;

#[derive(Clone, Copy, Debug, Serialize)]
pub struct ParamDef {
    pub key: &'static str,
    pub label: &'static str,
    #[serde(rename = "type")]
    pub kind: &'static str,
    /// f64 keeps catalog JSON clean (no f32 rounding noise in the UI).
    pub min: f64,
    pub max: f64,
    pub step: f64,
    pub default: f64,
}

pub const fn param(key: &'static str, label: &'static str, min: f64, max: f64, step: f64, default: f64) -> ParamDef {
    ParamDef {
        key,
        label,
        kind: "range",
        min,
        max,
        step,
        default,
    }
}

pub fn defaults_from(params: &[ParamDef]) -> ParamValues {
    params.iter().map(|p| (p.key.to_string(), p.default as f32)).collect()
}

/// Defaults overlaid with user values (same merge as effect-core's draw()).
pub fn resolve(params: &[ParamDef], values: &ParamValues) -> ParamValues {
    let mut out = defaults_from(params);
    for (key, value) in values {
        if params.iter().any(|p| p.key == key.as_str()) && value.is_finite() {
            out.insert(key.clone(), *value);
        }
    }
    out
}

/// Read a resolved value; `values` comes from `resolve` so the key is
/// always present, but fall back to the default defensively.
#[inline]
pub fn get(values: &ParamValues, params: &[ParamDef], key: &str) -> f32 {
    values.get(key).copied().unwrap_or_else(|| {
        params.iter().find(|p| p.key == key).map(|p| p.default as f32).unwrap_or(0.0)
    })
}
