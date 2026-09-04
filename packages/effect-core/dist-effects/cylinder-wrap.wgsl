
struct VgpuFullscreenVertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};
@vertex fn vgpu_fullscreen_vs(@builtin(vertex_index) vi: u32) -> VgpuFullscreenVertexOut {
  var pos = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  var uv = array<vec2f, 3>(vec2f(0.0, 1.0), vec2f(2.0, 1.0), vec2f(0.0, -1.0));
  var out: VgpuFullscreenVertexOut;
  out.position = vec4f(pos[vi], 0.0, 1.0);
  out.uv = uv[vi];
  return out;
}
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/cylinder-wrap/effect.wgsl
struct _vgsl_94a10455__Params {
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
@group(0) @binding(2) var<uniform> params: _vgsl_94a10455__Params;

const _vgsl_94a10455__TWO_PI: f32 = 6.2831853;
const _vgsl_94a10455__FLAT_R: f32 = 1e4; // huge radius = flat plane limit

// Rounded-box SDF, < 0 inside. p centered half-extents, r in the same units.
fn _vgsl_94a10455__rbox(p: vec2f, r: f32) -> f32 {
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
    ce = _vgsl_35d1d59a__easeInOutCubic((t - 0.30) / 0.10);
  } else if (t < 0.70) {
    ce = 1.0;
  } else if (t < 0.82) {
    // push-in: uncurl toward fullscreen, easing to a stop (d(ce)/dt -> 0)
    let p = (t - 0.70) / 0.12;
    ce = 1.0 - smoothstep(0.0, 1.0, p);
  } else {
    ce = 0.0;
  }

  // Centered half-extent coords in the video's own aspect space; shrink onto the stage while curled.
  var q = (_vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize) - vec2f(0.5)) * 2.0;
  q = q / mix(1.0, params.scale, ce);

  // Rounded stage corners: only while curled, radius grows with curl.
  // All cuts are soft (smoothstep on fwidth) — the mask multiplies to black
  // at the end, so edges anti-alias instead of shimmering.
  var mask = 1.0;
  let cr = params.corner * ce;
  if (cr > 0.0) {
    let sd = _vgsl_94a10455__rbox(q, cr);
    let fw = max(fwidth(sd), 1e-5);
    mask *= 1.0 - smoothstep(-fw, fw, sd);
  }

  // One drum for both views. "Inner" is the same drum (same panels/slits/spin)
  // with the vertical arch inverted: outside, receding sides compress the
  // frame vertically; inside the drum, the wall is everywhere equidistant so
  // the sides expand vertically (you are looking out at the surrounding wall).
  let drumR = params.radius * mix(1.0, params.innerScale, params.inner);
  let R = max(mix(_vgsl_94a10455__FLAT_R, drumR, ce), 0.05);
  // Silhouette: beyond |q.x| = R is black stage.
  let xn = q.x / R;
  let fx = max(fwidth(xn), 1e-5);
  mask *= 1.0 - smoothstep(1.0 - fx, 1.0 + fx, abs(xn));
  let a = R * asin(clamp(xn, -1.0, 1.0)); // arc along drum, half-extent units

  // Recess depth: 0 at the center silhouette, grows toward the edges.
  let z = R * (1.0 - cos(a / R));
  // Outside: edges recede (compressed like orthographic); inside: edges stay
  // equidistant so they open up (amplified like a wall around the camera).
  let vz = 1.0 + z * params.depth;
  var vy = q.y * vz;
  if (params.inner > 0.5) {
    vy = q.y / vz;
  }
  let fy = max(fwidth(vy), 1e-5);
  mask *= 1.0 - smoothstep(1.0 - fy, 1.0 + fy, abs(vy));
  let v = vy * 0.5 + 0.5;

  // Content rate: full video copy per panel at full curl, identity at flat.
  // Spin uses cycle-local time so the phase target stays bounded; absolute
  // videoTime would make curl-in whip through many turns late in a long clip.
  let K = mix(0.5, params.panels / (_vgsl_94a10455__TWO_PI * R), ce);
  var u = fract(a * K + t * dur * params.speed * ce * params.dir + 0.5);

  if (ce > 0.0) {
    // Black slits on copy boundaries (gap width grows with curl), soft-edged.
    let gapW = params.gap * ce * 0.5;
    let d = min(u, 1.0 - u);
    let gu = 1.5 / max(params.videoSize.x, 1.0); // ~1.5px in u units
    mask *= smoothstep(gapW - gu, gapW + gu, d);
    u = fract(u / (1.0 - params.gap * ce));
  }

  var col = _vgsl_35d1d59a__sampleVideo(src, samp, vec2f(u, v));
  // Drum shading: facing ratio darkens receding panels, sells the curve.
  let shade = mix(1.0, cos(a / R), min(ce * params.depth * 0.55, 0.85));
  return vec4f(col.rgb * shade * mask, 1.0);
}

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/shared/video.wgsl
// Pure helpers: no @group/@binding. Entry shaders own resources.

fn _vgsl_35d1d59a__containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
  let canvasSafe = max(canvas, vec2f(1.0));
  let videoSafe = max(video, vec2f(1.0));
  let canvasAspect = canvasSafe.x / canvasSafe.y;
  let videoAspect = videoSafe.x / videoSafe.y;
  var scale = vec2f(1.0);
  if (canvasAspect > videoAspect) {
    scale.x = videoAspect / canvasAspect;
  } else {
    scale.y = canvasAspect / videoAspect;
  }
  return (uv - vec2f(0.5)) / scale + vec2f(0.5);
}

fn _vgsl_35d1d59a__sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}

fn _vgsl_35d1d59a__easeInOutCubic(t: f32) -> f32 {
  let x = clamp(t, 0.0, 1.0);
  if (x < 0.5) {
    return 4.0 * x * x * x;
  }
  let u = -2.0 * x + 2.0;
  return 1.0 - u * u * u / 2.0;
}






