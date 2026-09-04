
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
// vgsl-module: /Users/zuoc/Documents/vscode/vgpu/packages/effect-core/src/effects/spectral-flare/effect.wgsl
// Spectral ghost flare, ported from charbelmalo/PrismaticShadersPack (MIT).
// https://github.com/charbelmalo/PrismaticShadersPack
     

struct _vgsl_a996f039__Params {
  time: f32,
  threshold: f32,
  strength: f32,
  size: f32,
  halo: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: _vgsl_a996f039__Params;

fn _vgsl_a996f039__sampleVideoW(u: vec2f) -> vec3f {
  return textureSampleLevel(src, samp, vec2f(fract(u.x), clamp(u.y, 0.0, 1.0)), 0.0).rgb;
}

// Simplified Planckian locus approximation: 380-780nm -> RGB.
fn _vgsl_a996f039__wavelengthToRgb(wl: f32) -> vec3f {
  var c = vec3f(0.0);
  if (wl < 440.0) {
    c = vec3f(-(wl - 440.0) / 60.0, 0.0, 1.0);
  } else if (wl < 490.0) {
    c = vec3f(0.0, (wl - 440.0) / 50.0, 1.0);
  } else if (wl < 510.0) {
    c = vec3f(0.0, 1.0, -(wl - 510.0) / 20.0);
  } else if (wl < 580.0) {
    c = vec3f((wl - 510.0) / 70.0, 1.0, 0.0);
  } else if (wl < 645.0) {
    c = vec3f(1.0, -(wl - 645.0) / 65.0, 0.0);
  } else {
    c = vec3f(1.0, 0.0, 0.0);
  }
  var factor = 1.0;
  if (wl < 420.0) {
    factor = 0.3 + 0.7 * (wl - 380.0) / 40.0;
  } else if (wl > 700.0) {
    factor = 0.3 + 0.7 * (780.0 - wl) / 80.0;
  }
  return c * factor;
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = _vgsl_35d1d59a__containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let color = _vgsl_a996f039__sampleVideoW(v);
  let center = vec2f(0.5);
  let dir = v - center;
  let dist = length(dir);

  let lum = dot(color, vec3f(0.2126, 0.7152, 0.0722));
  let mask = smoothstep(params.threshold - 0.1, params.threshold + 0.1, lum) * params.strength;

  // Spectral ghost samples along the light -> center axis.
  var flare = vec3f(0.0);
  for (var i = 0u; i < 6u; i += 1u) {
    let t = f32(i) / 5.0;
    let offsetScale = (0.02 + 0.08 * t) * dist * mix(1.0, params.size * 10.0, 0.5);
    let ghost1 = center + dir * 1.5 + dir * offsetScale;
    let ghost2 = center + dir * 0.7 - dir * offsetScale * 0.5;
    let rgb = _vgsl_a996f039__wavelengthToRgb(380.0 + t * 400.0);
    flare += _vgsl_a996f039__sampleVideoW(ghost1) * rgb * mask * 0.4;
    flare += _vgsl_a996f039__sampleVideoW(ghost2) * rgb * mask * 0.25;
  }

  // Broad halo around bright regions.
  let haloWidth = 0.03;
  let haloColor = (_vgsl_a996f039__sampleVideoW(v + dir * haloWidth) + _vgsl_a996f039__sampleVideoW(v - dir * haloWidth)) * 0.5;
  let haloMask = smoothstep(params.threshold * 0.3, params.threshold, lum);
  flare += haloColor * haloMask * 0.2 * params.halo;

  // Rainbow fringing on highlights.
  let caOffset = dir * params.size * 0.003 * dist;
  var caColor = color;
  caColor.r = _vgsl_a996f039__sampleVideoW(v + caOffset).r;
  caColor.b = _vgsl_a996f039__sampleVideoW(v - caOffset).b;

  return vec4f(min(caColor + flare, vec3f(2.0)), 1.0);
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










