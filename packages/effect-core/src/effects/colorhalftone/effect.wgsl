import { containUv, sampleVideo } from "../shared/video.wgsl";
import { halftoneDot } from "../shared/f0r.wgsl";

struct Params {
  dotRadius: f32,
  angC: f32,
  angM: f32,
  angY: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

const PI: f32 = 3.14159265;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // Physical aspect, not the output canvas aspect: the dots stay circular when
  // a 9:16 video is previewed on a 16:9 stage.
  let ar = params.videoSize.x / max(params.videoSize.y, 1.0);
  let p = vec2f(v.x * ar, v.y);
  // dotRadius scales the halftone cell, so larger values mean physically
  // larger dots (and fewer of them), matching the "dot radius" label.
  let freq = mix(70.0, 10.0, clamp(params.dotRadius, 0.0, 1.0));
  let ink = sampleVideo(src, samp, v).rgb;
  // Subtractive print: white paper, dots grow with ink. Standard CMY screen
  // angles are 15 / 75 / 0 degrees; the UI stores turns.
  let dotC = halftoneDot(p, params.angC * PI, freq, 1.0 - ink.r);
  let dotM = halftoneDot(p, params.angM * PI, freq, 1.0 - ink.g);
  let dotY = halftoneDot(p, params.angY * PI, freq, 1.0 - ink.b);
  let paper = vec3f(1.0);
  let inkc = vec3f(0.0, 0.95, 1.0);
  let inkm = vec3f(1.0, 0.0, 0.9);
  let inky = vec3f(1.0, 0.9, 0.0);
  var col = paper * (1.0 - dotY) + inky * dotY;
  col = col * (1.0 - dotM) + inkm * dotM;
  col = col * (1.0 - dotC) + inkc * dotC;
  return vec4f(col, 1.0);
}
