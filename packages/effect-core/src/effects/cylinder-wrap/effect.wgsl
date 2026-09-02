import { containUv, easeInOutCubic, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  videoTime: f32,
  radius: f32,
  depth: f32,
  scale: f32,
  speed: f32,
  panels: f32,
  gap: f32,
  corner: f32,
  duration: f32,
  dir: f32,
  inner: f32,
  innerScale: f32,
  looping: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

const TWO_PI: f32 = 6.2831853;

// Rounded-box SDF, < 0 inside. p centered half-extents, r in the same units.
fn rbox(p: vec2f, r: f32) -> f32 {
  let q = abs(p) - vec2f(1.0 - r, 1.0 - r);
  return length(max(q, vec2f(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - r;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let dur = max(params.duration, 0.05);
  var t = params.videoTime / dur;
  if (params.looping > 0.5) {
    t = fract(t);
  } else {
    t = clamp(t, 0.0, 1.0);
  }

  // Cycle: flat | curl-in | drum spin | push to fullscreen | flat
  var ce = 0.0; // curl amount: 0 flat, 1 drum
  if (t < 0.30) {
    // base flat
  } else if (t < 0.40) {
    ce = easeInOutCubic((t - 0.30) / 0.10);
  } else if (t < 0.70) {
    ce = 1.0;
  } else if (t < 0.82) {
    // push-in: accelerated uncurl toward fullscreen
    let p = (t - 0.70) / 0.12;
    ce = 1.0 - p * p;
  } else {
    ce = 0.0;
  }

  // Centered half-extent coords in the video's own aspect space; shrink onto the stage while curled.
  var q = (containUv(uv, params.resolution, params.videoSize) - vec2f(0.5)) * 2.0;
  q = q / mix(1.0, params.scale, ce);

  // Rounded stage corners: only while curled, radius grows with curl.
  let cr = params.corner * ce;
  if (cr > 0.0 && rbox(q, cr) > 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }

  // One drum for both views. "Inner" is the same drum (same panels/slits/spin)
  // with the vertical arch inverted: outside, receding sides compress the
  // frame vertically; inside the drum, the wall is everywhere equidistant so
  // the sides expand vertically (you are looking out at the surrounding wall).
  let drumR = params.radius * mix(1.0, params.innerScale, params.inner);
  let R = max(mix(10000.0, drumR, ce), 0.05);
  if (abs(q.x) > R) {
    return vec4f(0.0, 0.0, 0.0, 1.0); // beyond silhouette = black stage
  }
  let a = R * asin(clamp(q.x / R, -1.0, 1.0)); // arc along drum, half-extent units

  // Recess depth: 0 at the center silhouette, grows toward the edges.
  let z = R * (1.0 - cos(a / R));
  // Outside: edges recede (compressed like orthographic); inside: edges stay
  // equidistant so they open up (amplified like a wall around the camera).
  let vz = 1.0 + z * params.depth;
  var vy = q.y * vz;
  if (params.inner > 0.5) {
    vy = q.y / vz;
  }
  if (abs(vy) > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let v = vy * 0.5 + 0.5;

  // Content rate: full video copy per panel at full curl, identity at flat.
  let K = mix(0.5, params.panels / (TWO_PI * R), ce);
  var u = fract(a * K + params.videoTime * params.speed * ce * params.dir + 0.5);

  if (ce > 0.0) {
    // Black slits on copy boundaries (gap width grows with curl).
    let gapW = params.gap * ce * 0.5;
    let d = min(u, 1.0 - u);
    if (d < gapW) {
      return vec4f(0.0, 0.0, 0.0, 1.0);
    }
    u = fract(u * 1.0 / (1.0 - params.gap * ce));
  }

  return sampleVideo(src, samp, vec2f(u, v));
}
