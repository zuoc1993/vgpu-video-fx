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
  var ce = 0.0;   // curl amount: 0 flat, 1 drum
  var zoom = 1.0; // push-in zoom
  if (t < 0.30) {
    // base flat
  } else if (t < 0.40) {
    ce = easeInOutCubic((t - 0.30) / 0.10);
  }
  // drum + spin 0.40-0.70
  if (t >= 0.40 && t < 0.70) {
    ce = 1.0;
  }
  if (t >= 0.70 && t < 0.82) {
    // push-in: zoom toward center while uncurling
    let p = (t - 0.70) / 0.12;
    let pe = p * p; // ease-in suction
    ce = 1.0 - pe;
    zoom = 1.0 + 0.8 * pe;
  }
  if (t >= 0.82) {
    // fullscreen after push
    ce = 0.0;
  }

  // Centered half-extent coords in the video's own aspect space; then shrink onto the stage while curled.
  var q = (containUv(uv, params.resolution, params.videoSize) - vec2f(0.5)) * 2.0;
  q = q / mix(1.0, params.scale, ce);

  // Rounded stage corners: only while curled, radius grows with curl.
  let cr = params.corner * ce;
  if (cr > 0.0 && rbox(q, cr) > 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }

  // Wrap x around a vertical-axis drum (arc-length preserved): R -> inf at ce=0 gives exact identity.
  let R = max(mix(10000.0, params.radius, ce), 0.05);
  if (abs(q.x) > R) {
    return vec4f(0.0, 0.0, 0.0, 1.0); // beyond silhouette = black stage
  }
  let a = R * asin(clamp(q.x / R, -1.0, 1.0)); // arc length along drum, half-extent units

  // Fake perspective: receding surface compresses vertically -> arched top/bottom silhouette.
  let z = R * (1.0 - cos(a / R));
  let vy = q.y * (1.0 + z * params.depth);
  if (abs(vy) > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let v = vy * 0.5 + 0.5;

  // Content repeat: video wraps around the drum; at ce=0 the wrap rate morphs
  // to 0.5 so the mapping is exactly the flat identity.
  let K = mix(0.5, params.panels / (TWO_PI * R), ce);
  let spin = params.videoTime * params.speed * ce; // in video-widths
  var u = fract(a * K + spin);
  if (ce > 0.0) {
    // Round the sampling: while curled, each copy shows the same video so
    // slits sit on copy boundaries.
    let gapW = params.gap * ce * 0.5;
    let d = min(u, 1.0 - u);
    if (d < gapW) {
      return vec4f(0.0, 0.0, 0.0, 1.0);
    }
    u = fract(u * 1.0 / (1.0 - params.gap * ce));
  }

  let out = sampleVideo(src, samp, vec2f(u, v));
  return out;
}
