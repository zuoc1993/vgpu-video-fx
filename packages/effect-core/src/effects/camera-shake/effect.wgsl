import { hash2 } from "@vgpu/wgsl-std/hash";
import { containUv, rotateUvAspect, sampleVideo, zoomAtAspect } from "../shared/video.wgsl";

struct Params {
  time: f32,
  intensity: f32,
  speed: f32,
  frequency: f32,
  rotation: f32,
  zoom: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let cell = floor(params.time * params.speed * params.frequency);
  let frac = fract(params.time * params.speed * params.frequency);
  let n = hash2(vec2f(cell, 17.3));
  let n2 = hash2(vec2f(cell + 1.0, 9.1));
  let jitter = mix(n, n2, frac) - vec2f(0.5);
  let rn = hash2(vec2f(cell, 5.7));
  let rn2 = hash2(vec2f(cell + 1.0, 5.7));
  let rotJitter = mix(rn, rn2, frac) - vec2f(0.5);

  let aspect = params.videoSize.x / max(params.videoSize.y, 1.0);
  let offset = jitter * 0.055 * params.intensity;
  let angle = rotJitter.x * 0.06 * params.rotation * params.intensity;
  // Zoom-to-hide-border: the translation is only visible as shake when the
  // enlarged frame still covers the output rectangle.
  let zoom = 1.0 + params.zoom * params.intensity + abs(jitter.x) * 0.08 * params.intensity;
  var vuv = containUv(uv, params.resolution, params.videoSize);
  vuv = rotateUvAspect(vuv, angle, vec2f(0.5), aspect);
  vuv = zoomAtAspect(vuv, zoom, vec2f(0.5), aspect) + offset;
  return sampleVideo(src, samp, vuv);
}
