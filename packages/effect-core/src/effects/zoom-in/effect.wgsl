import { containUv, easeInOutCubic, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  videoTime: f32,
  startScale: f32,
  endScale: f32,
  duration: f32,
  looping: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let dur = max(params.duration, 0.05);
  var t = params.videoTime / dur;
  if (params.looping > 0.5) {
    t = fract(t);
  } else {
    t = clamp(t, 0.0, 1.0);
  }
  let scale = mix(params.startScale, params.endScale, easeInOutCubic(t));
  let vuv = (containUv(uv, params.resolution, params.videoSize) - vec2f(0.5)) / scale + vec2f(0.5);
  return sampleVideo(src, samp, vuv);
}
