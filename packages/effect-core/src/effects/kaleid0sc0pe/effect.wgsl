import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  segs: f32,
  zoom: f32,
  speed: f32,
  twist: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let p = vec2f((v.x - 0.5) * ar, v.y - 0.5) / max(params.zoom, 0.1);
  let r = length(p);
  let n = max(floor(params.segs), 3.0);
  let sector = 6.2831853 / n;
  // Mirror each sector; twist bends the seams radially, time rotates the drum.
  let ang = atan2(p.y, p.x) + params.time * params.speed * 0.8 + r * params.twist * 3.0;
  let a = ang - floor(ang / sector) * sector;
  let reflected = sector * 0.5 - abs(a - sector * 0.5);
  let q = vec2f(cos(reflected), sin(reflected)) * r;
  return sampleVideo(src, samp, q / vec2f(ar, 1.0) * params.zoom + 0.5);
}
