import { containUv, easeInOutCubic, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  videoTime: f32,
  startScale: f32,
  endScale: f32,
  duration: f32,
  looping: f32,
  centerX: f32,
  centerY: f32,
  drift: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let dur = max(params.duration, 0.05);
  var x = params.videoTime / dur;
  if (params.looping > 0.5) {
    // Ping-pong: loop mode should not snap from endScale back to startScale.
    x = 1.0 - abs(2.0 * fract(x) - 1.0);
  } else {
    x = clamp(x, 0.0, 1.0);
  }
  let scale = mix(params.startScale, params.endScale, easeInOutCubic(x));
  let center = vec2f(params.centerX, params.centerY) + vec2f(params.drift * (x - 0.5), 0.0);
  let vuv = (containUv(uv, params.resolution, params.videoSize) - center) / scale + center;
  return sampleVideo(src, samp, vuv);
}
