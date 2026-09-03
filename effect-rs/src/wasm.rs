//! wasm-bindgen bindings (feature "wasm"): wasm-pack -> npm package with .d.ts.

use crate::context::Timing;
use crate::engine::render_frame;
use crate::frame::Frame;
use crate::params::ParamValues;
use crate::registry;
use serde::ser::Serialize;
use wasm_bindgen::prelude::*;

fn err_js(e: impl std::fmt::Display) -> JsValue {
    JsValue::from_str(&e.to_string())
}

/// Serialize to a plain JS object (default to_value produces JS `Map`s,
/// which look empty to Object.keys/spread).
fn to_js_object<T: Serialize>(v: &T) -> Result<JsValue, serde_wasm_bindgen::Error> {
    v.serialize(&serde_wasm_bindgen::Serializer::new().serialize_maps_as_objects(true))
}

/// Catalog metadata (same JSON shape as the TS EffectDefinition minus shader).
#[wasm_bindgen(js_name = catalog)]
pub fn catalog() -> Result<JsValue, JsValue> {
    to_js_object(&registry::catalog_meta()).map_err(err_js)
}

/// Default param values for an effect: {key: number}.
#[wasm_bindgen(js_name = defaults)]
pub fn defaults(effect: &str) -> Result<JsValue, JsValue> {
    let fx = registry::get(effect).ok_or_else(|| JsValue::from_str(&format!("Unknown effect: {effect}")))?;
    to_js_object(&crate::params::defaults_from(fx.params())).map_err(err_js)
}

/// Render one frame. `params` is a plain JS object {key: number} (or
/// null/undefined for defaults). src/out sizes are separate so the wasm path
/// can reproduce containUv letterboxing when the canvas differs from the video.
#[wasm_bindgen(js_name = render)]
#[allow(clippy::too_many_arguments)]
pub fn render(
    effect: &str,
    params: JsValue,
    time: f32,
    delta_time: f32,
    video_time: f32,
    video_duration: f32,
    src: &[u8],
    src_w: u32,
    src_h: u32,
    out_w: u32,
    out_h: u32,
) -> Result<Vec<u8>, JsValue> {
    let values: ParamValues = if params.is_null() || params.is_undefined() {
        ParamValues::new()
    } else {
        serde_wasm_bindgen::from_value(params).map_err(err_js)?
    };
    let fx = registry::get(effect).ok_or_else(|| JsValue::from_str(&format!("Unknown effect: {effect}")))?;
    let frame = Frame::from_bytes(src_w, src_h, src).map_err(err_js)?;
    let timing = Timing {
        time,
        delta_time,
        video_time,
        video_duration,
    };
    let out = render_frame(fx, &values, &frame, out_w, out_h, timing).map_err(err_js)?;
    Ok(out.data)
}
