
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/crt/effect.wgsl
// CRT post-process, ported from Kodaskills/bevy_retro_shaders (MIT).
// https://github.com/Kodaskills/bevy_retro_shaders
     

struct _vgsl_ea9b5060__Params {
  time: f32,
  curvature: f32,
  chromatic: f32,
  scanline: f32,
  grain: f32,
  glitch: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_ea9b5060__Params;

fn _vgsl_ea9b5060__hash(n: f32) -> f32 {
  let x = sin(n) * 43758.5453;
  return x - floor(x);
}

fn _vgsl_ea9b5060__hash2(p: vec2f) -> f32 {
  return _vgsl_ea9b5060__hash(dot(p, vec2f(127.1, 311.7)));
}

fn _vgsl_ea9b5060__inB(uv: vec2f) -> f32 {
  let below = step(vec2f(0.0), uv);
  let above = step(uv, vec2f(1.0));
  return below.x * below.y * above.x * above.y;
}

fn _vgsl_ea9b5060__barrel(uv: vec2f, curvature: f32) -> vec2f {
  var p = uv * 2.0 - 1.0;
  let r2 = dot(p, p);
  p = p * (1.0 + curvature * r2);
  return p * 0.5 + 0.5;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_17688d6e__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let gi = params.glitch;
  let seed = params.time * 7.0;
  let px = v * params.resolution;

  var sampleUv = _vgsl_ea9b5060__barrel(v, params.curvature);

  // Row-band shifts (glitch), driven by time.
  let band = floor(px.y / 6.0);
  let shouldShift = step(1.0 - gi * 0.65, _vgsl_ea9b5060__hash(band * 7.3 + seed * 100.0));
  let shiftAmount = (_vgsl_ea9b5060__hash(band + seed * 31.0) - 0.5) * 0.09 * gi;
  sampleUv.x += shiftAmount * shouldShift;

  // Chromatic aberration radial, extra split on glitch rows.
  let uvCenter = sampleUv - 0.5;
  let lineHash = _vgsl_ea9b5060__hash(floor(px.y) * 1.3 + seed * 200.0);
  let rgbGlitch = step(1.0 - gi * 0.45, lineHash);
  let glitchSplit = gi * 0.04 * rgbGlitch;
  let uvR = sampleUv + uvCenter * params.chromatic + vec2f(glitchSplit, 0.0);
  let uvB = sampleUv - uvCenter * params.chromatic - vec2f(glitchSplit, 0.0);
  let r = textureSampleLevel(src, samp, vec2f(fract(uvR.x), clamp(uvR.y, 0.0, 1.0)), 0.0).r;
  let g = textureSampleLevel(src, samp, vec2f(fract(sampleUv.x), clamp(sampleUv.y, 0.0, 1.0)), 0.0).g;
  let b = textureSampleLevel(src, samp, vec2f(fract(uvB.x), clamp(uvB.y, 0.0, 1.0)), 0.0).b;
  var col = vec4f(r, g, b, 1.0) * _vgsl_ea9b5060__inB(sampleUv);

  // Film grain.
  let pixelHash = _vgsl_ea9b5060__hash2(floor(px) + fract(seed * 500.0) * 999.0);
  let noiseVal = (pixelHash - 0.5) * 2.0;
  col = vec4f(col.rgb + noiseVal * params.grain, col.a);

  // CRT wave scanlines.
  let angle = (px.y / 4.0) * 6.2831853;
  let wave = cos(angle) * 0.5 + 0.5;
  let scan = 1.0 - params.scanline * (1.0 - wave * wave * wave);
  col = vec4f(col.rgb * clamp(scan, 0.0, 1.0), 1.0);

  // CRT corner vignette.
  let vv = uv * 2.0 - 1.0;
  let vignette = 1.0 - dot(vv * vv, vv * vv) * 0.25;
  col = vec4f(col.rgb * clamp(vignette, 0.0, 1.0), 1.0);

  return col;
}

// vgsl-module: /Users/zuoc/Documents/vscode/vgpu-video-fx/packages/effect-core/src/effects/shared/video.wgsl
// Pure helpers: no @group/@binding. Entry shaders own resources.

 fn _vgsl_17688d6e__containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
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

 

 

 

 

 
