
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/dust-bokeh/effect.wgsl
// Floating bokeh dust, inspired by charbelmalo/PrismaticShadersPack dust
// particles (MIT). Procedural soft discs instead of an atlas texture.
      
     

struct _vgsl_e084b4ee__Params {
  time: f32,
  count: f32,
  size: f32,
  focus: f32,
  opacity: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_e084b4ee__Params;

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let ar = params.resolution.x / max(params.resolution.y, 1.0);
  let n = max(floor(params.count), 4.0);
  var dust = 0.0;
  var tint = 0.0;
  for (var i = 0u; i < 24u; i += 1u) {
    let f = f32(i);
    if (f >= n) {
      break;
    }
    // Base position drifts slowly; depth per particle controls both scale and
    // blur radius (pre-computed-atlas analogue: sigma = radius*blur).
    let depth = _vgsl_9a0b5690__hash1(f * 7.31);
    let drift = vec2f(_vgsl_9a0b5690__hash1(f * 13.7 + 1.0), _vgsl_9a0b5690__hash1(f * 19.3 + 2.0)) - 0.5;
    var pos = vec2f(_vgsl_9a0b5690__hash1(f * 3.3), _vgsl_9a0b5690__hash1(f * 5.1)) + drift * 0.2 * params.time;
    pos = vec2f(fract(pos.x), fract(pos.y));
    // Correct the screen-space offset by aspect so distance reads square.
    let p = vec2f((v.x - pos.x) * ar, v.y - pos.y);
    let r = length(p);
    let bokeh = mix(params.size * 0.02, params.size * 0.05, depth);
    let focusDist = abs(depth - params.focus);
    let sigma = bokeh * (0.4 + focusDist * 1.6);
    let a = exp(-(r * r) / max(sigma * sigma, 1e-5)) * (0.16 - focusDist * 0.1);
    dust += a;
    tint += (0.9 + 0.2 * _vgsl_9a0b5690__hash1(f * 29.5 + 3.0)) * a;
  }
  let col = _vgsl_35d1d59a__sampleVideo(src, samp, v).rgb;
  // Dust is additive and slightly warm.
  return vec4f(col + dust * params.opacity * 0.35 * tint, 1.0);
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









// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/node_modules/@vgpu/wgsl-std/src/hash/index.wgsl
// Wellons lowbias32: https://github.com/skeeto/hash-prospector
fn _vgsl_9a0b5690__hashU32(value: u32) -> u32 {
  var hashed = value;
  hashed = (hashed ^ (hashed >> 16u)) * 0x7feb352du;
  hashed = (hashed ^ (hashed >> 15u)) * 0x846ca68bu;
  hashed = hashed ^ (hashed >> 16u);
  return hashed;
}





fn _vgsl_9a0b5690__unitFloat(hash: u32) -> f32 {
  return f32(hash >> 8u) * (1.0 / 16777216.0);
}

fn _vgsl_9a0b5690__hash1(seed: f32) -> f32 {
  return _vgsl_9a0b5690__unitFloat(_vgsl_9a0b5690__hashU32(bitcast<u32>(seed)));
}




