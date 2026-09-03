//! PyO3 bindings (feature "python"): effect_rs module for bmf-demo.

use crate::context::Timing;
use crate::engine::{render_batch as engine_render_batch, render_frame};
use crate::frame::Frame;
use crate::params::ParamValues;
use crate::registry;
use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use pyo3::types::{PyBytes, PyDict, PyList};
use std::collections::HashMap;

fn py_err(e: crate::EffectError) -> PyErr {
    PyValueError::new_err(e.to_string())
}

impl From<crate::EffectError> for PyErr {
    fn from(e: crate::EffectError) -> Self {
        py_err(e)
    }
}

fn fx_by_id(effect: &str) -> PyResult<&'static dyn crate::Effect> {
    registry::get(effect).ok_or_else(|| PyValueError::new_err(format!("unknown effect: {effect}")))
}

/// Catalog as a list of dicts: [{id, name, category, description, params:[...]}].
#[pyfunction]
fn catalog(py: Python<'_>) -> PyResult<Py<PyList>> {
    let list = PyList::empty(py);
    for e in registry::catalog() {
        let m = e.meta();
        let d = PyDict::new(py);
        d.set_item("id", m.id)?;
        d.set_item("name", m.name)?;
        d.set_item("category", m.category)?;
        d.set_item("description", m.description)?;
        let pl = PyList::empty(py);
        for p in m.params {
            let pd = PyDict::new(py);
            pd.set_item("key", p.key)?;
            pd.set_item("label", p.label)?;
            pd.set_item("type", p.kind)?;
            pd.set_item("min", p.min)?;
            pd.set_item("max", p.max)?;
            pd.set_item("step", p.step)?;
            pd.set_item("default", p.default)?;
            pl.append(pd)?;
        }
        d.set_item("params", pl)?;
        list.append(d)?;
    }
    Ok(list.unbind())
}

/// Render one frame. `rgba` borrows the bytes object zero-copy.
/// Returns RGBA8 bytes of the same size.
#[pyfunction]
#[pyo3(signature = (effect, width, height, rgba, time=0.0, params=None, video_duration=0.0))]
fn render(
    py: Python<'_>,
    effect: &str,
    width: u32,
    height: u32,
    rgba: &[u8],
    time: f32,
    params: Option<HashMap<String, f32>>,
    video_duration: f32,
) -> PyResult<Py<PyBytes>> {
    let src = Frame::from_bytes(width, height, rgba).map_err(py_err)?;
    let fx = fx_by_id(effect)?;
    let values: ParamValues = params.unwrap_or_default();
    let timing = Timing {
        time,
        delta_time: 0.0,
        video_time: time,
        video_duration,
    };
    let out = py.allow_threads(|| render_frame(fx, &values, &src, width, height, timing))?;
    Ok(PyBytes::new(py, &out.data).unbind())
}

/// Render `len(times)` same-sized frames concatenated in `pixels`.
/// Returns the concatenated RGBA8 outputs.
#[pyfunction]
#[pyo3(signature = (effect, width, height, pixels, times, params=None, video_duration=0.0))]
fn render_batch(
    py: Python<'_>,
    effect: &str,
    width: u32,
    height: u32,
    pixels: &[u8],
    times: Vec<f32>,
    params: Option<HashMap<String, f32>>,
    video_duration: f32,
) -> PyResult<Py<PyBytes>> {
    let n = times.len();
    let stride = width as usize * height as usize * 4;
    if n == 0 || stride == 0 {
        return Ok(PyBytes::new(py, b"").unbind());
    }
    if pixels.len() < stride * n {
        return Err(PyValueError::new_err(format!(
            "pixels buffer too small: {} < {stride} * {n}",
            pixels.len()
        )));
    }
    let fx = fx_by_id(effect)?;
    let values: ParamValues = params.unwrap_or_default();
    let frames: Vec<Frame> = (0..n)
        .map(|i| Frame::from_bytes(width, height, &pixels[i * stride..(i + 1) * stride]))
        .collect::<crate::Result<_>>()
        .map_err(py_err)?;
    let out =
        py.allow_threads(|| engine_render_batch(fx, &values, &frames, &times, video_duration))?;
    let mut packed = Vec::with_capacity(stride * n);
    for f in &out {
        packed.extend_from_slice(&f.data);
    }
    Ok(PyBytes::new(py, &packed).unbind())
}

#[pymodule]
fn effect_rs(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(catalog, m)?)?;
    m.add_function(wrap_pyfunction!(render, m)?)?;
    m.add_function(wrap_pyfunction!(render_batch, m)?)?;
    Ok(())
}
