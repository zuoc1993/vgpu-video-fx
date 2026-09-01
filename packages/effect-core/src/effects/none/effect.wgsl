import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  return sampleVideo(src, samp, containUv(uv, params.resolution, params.videoSize));
}
