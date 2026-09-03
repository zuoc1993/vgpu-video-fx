//! Unit tests for the WGSL-parity helpers and effect smoke tests.

use effect_rs::context::Timing;
use effect_rs::engine::render_frame;
use effect_rs::frame::Frame;
use effect_rs::math::{contain_uv, hash2, pcg2d, wgsl_fract};
use effect_rs::params::{defaults_from, ParamValues};
use effect_rs::registry::{catalog, get};
use effect_rs::sampler::sample_linear;

fn approx(a: f32, b: f32, eps: f32) -> bool {
    (a - b).abs() <= eps
}

// ---- hash vectors: cross-checked against a JS implementation of pcg2d ----

#[test]
fn pcg2d_matches_reference_vectors() {
    assert_eq!(pcg2d([0, 0]), [417_608_103, 90_043_601]);
    assert_eq!(pcg2d([123_456_789, 987_654_321]), [3_082_568_863, 1_742_963_564]);
}

#[test]
fn hash2_matches_reference_vectors() {
    let cases: [([f32; 2], [f32; 2]); 5] = [
        ([0.0, 0.0], [0.097_231_924_533_844, 0.020_964_860_916_137_695]),
        ([1.0, 2.0], [0.351_435_065_269_470_2, 0.547_439_098_358_154_3]),
        ([0.5, -3.25], [0.172_977_387_905_120_85, 0.010_116_755_962_371_826]),
        ([12_345.678, 0.001], [0.452_759_563_922_882_1, 0.522_179_603_576_660_2]),
        ([44.0, 0.7], [0.356_149_554_252_624_5, 0.341_187_298_297_882_1]),
    ];
    for (seed, want) in cases {
        let got = hash2(seed);
        assert!(approx(got[0], want[0], 1e-9), "hash2({seed:?}) x: {} vs {}", got[0], want[0]);
        assert!(approx(got[1], want[1], 1e-9), "hash2({seed:?}) y: {} vs {}", got[1], want[1]);
    }
}

// ---- wgsl_fract: differs from f32::fract for negatives ----

#[test]
fn wgsl_fract_is_always_nonnegative() {
    assert!(approx(wgsl_fract(1.3), 0.3, 1e-7));
    assert!(approx(wgsl_fract(-0.3), 0.7, 1e-7));
    assert!(approx(wgsl_fract(2.0), 0.0, 1e-7));
}

// ---- contain_uv: three aspect regimes ----

#[test]
fn contain_uv_aspect_cases() {
    // equal aspect: identity
    let p = contain_uv([0.25, 0.75], [1920.0, 1080.0], [1920.0, 1080.0]);
    assert!(approx(p[0], 0.25, 1e-6) && approx(p[1], 0.75, 1e-6));
    // canvas wider than video: horizontal letterbox; the canvas edge at
    // x=0 lies outside the fit content, so it maps below 0.
    let p = contain_uv([0.0, 0.5], [1600.0, 900.0], [800.0, 800.0]);
    assert!(p[0] < 0.0 && p[1] == 0.5);
    // canvas taller than video: vertical letterbox
    let p = contain_uv([0.5, 0.0], [800.0, 800.0], [1600.0, 900.0]);
    assert!(p[0] == 0.5 && p[1] < 0.0);
    // center stays put in both regimes
    let p = contain_uv([0.5, 0.5], [1600.0, 900.0], [800.0, 800.0]);
    assert!(approx(p[0], 0.5, 1e-6) && approx(p[1], 0.5, 1e-6));
}

// ---- sampler: bilinear midpoint / edge clamp ----

#[test]
fn sampler_midpoint_returns_texel() {
    let mut f = Frame::new(2, 2);
    for (i, px) in f.data.chunks_exact_mut(4).enumerate() {
        px[0] = (i * 64) as u8;
        px[1] = 128;
        px[2] = 200;
        px[3] = 255;
    }
    let s = f.view();
    let c = sample_linear(s, [0.25, 0.25]);
    assert!(approx(c[0], 0.0, 1e-6));
    let c = sample_linear(s, [0.75, 0.25]);
    assert!(approx(c[0], 64.0 / 255.0, 1e-6));
    // halfway between texels: exact average
    let c = sample_linear(s, [0.5, 0.25]);
    assert!(approx(c[0], 32.0 / 255.0, 1e-6));
    // out-of-range clamps to border texel (y < 0 -> row 0)
    let c = sample_linear(s, [0.25, -1.0]);
    assert!(approx(c[0], 0.0, 1e-6));
    // beyond far edge clamps to last texel (x > 1 -> col 1)
    let c = sample_linear(s, [2.0, 0.25]);
    assert!(approx(c[0], 64.0 / 255.0, 1e-6));
}

// ---- effect smoke: every catalog entry renders deterministically ----

#[test]
fn catalog_has_expected_ids() {
    let ids: Vec<&str> = catalog().iter().map(|e| e.id()).collect();
    assert_eq!(ids, ["none", "posterize", "rgbsplit0r", "glitch", "glow"]);
}

#[test]
fn every_effect_renders_smoke() {
    let w = 64;
    let h = 48;
    let mut src = Frame::new(w, h);
    for (i, px) in src.data.chunks_exact_mut(4).enumerate() {
        px[0] = (i * 7 % 251) as u8;
        px[1] = (i * 13 % 251) as u8;
        px[2] = (i * 31 % 251) as u8;
        px[3] = 255;
    }
    for fx in catalog() {
        let values = defaults_from(fx.params());
        let timing = Timing {
            time: 1.25,
            delta_time: 0.04,
            video_time: 1.25,
            video_duration: 3.0,
        };
        let out = render_frame(*fx, &values, &src, w, h, timing).expect(fx.id());
        assert_eq!(out.width, w);
        assert_eq!(out.height, h);
        // alpha stays 255 for every pixel
        assert!(out.data.chunks_exact(4).all(|p| p[3] == 255), "alpha for {}", fx.id());
    }
}

#[test]
fn none_copies_same_size_frames() {
    let mut src = Frame::new(8, 6);
    src.data.iter_mut().enumerate().for_each(|(i, v)| *v = (i % 256) as u8);
    let fx = get("none").unwrap();
    let out = render_frame(fx, &ParamValues::new(), &src, 8, 6, Timing::default()).unwrap();
    assert_eq!(out.data, src.data);
}

#[test]
fn glitch_is_deterministic() {
    let mut src = Frame::new(32, 32);
    for (i, px) in src.data.chunks_exact_mut(4).enumerate() {
        px[0] = (i * 3) as u8;
        px[1] = (i * 5) as u8;
        px[2] = (i * 11) as u8;
        px[3] = 255;
    }
    let fx = get("glitch").unwrap();
    let values = defaults_from(fx.params());
    let timing = Timing {
        time: 0.5,
        ..Timing::default()
    };
    let a = render_frame(fx, &values, &src, 32, 32, timing).unwrap();
    let b = render_frame(fx, &values, &src, 32, 32, timing).unwrap();
    assert_eq!(a.data, b.data);
}

#[test]
fn unknown_effect_errors() {
    assert!(get("no-such-effect").is_none());
}

#[test]
fn batch_mixed_sizes_error() {
    let fx = get("none").unwrap();
    let f1 = Frame::new(4, 4);
    let f2 = Frame::new(8, 8);
    let err = effect_rs::engine::render_batch(fx, &ParamValues::new(), &[f1, f2], &[0.0, 1.0], 0.0);
    assert!(err.is_err());
}
