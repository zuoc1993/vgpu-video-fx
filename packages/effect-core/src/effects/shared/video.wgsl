// Pure helpers: no @group/@binding. Entry shaders own resources.

export fn containScale(canvas: vec2f, video: vec2f) -> vec2f {
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
  return scale;
}

export fn containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
  let scale = containScale(canvas, video);
  return (uv - vec2f(0.5)) / scale + vec2f(0.5);
}

// Step in video UV that corresponds to one output pixel, after containUv.
// Use this for source-space kernels (Sobel/emboss/glow) instead of 1/resolution,
// otherwise preview and offscreen renders diverge when the canvas aspect differs.
export fn sourceTexel(canvas: vec2f, video: vec2f) -> vec2f {
  let scale = containScale(canvas, video);
  return 1.0 / (max(canvas, vec2f(1.0)) * scale);
}

export fn sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}

// Edge-clamped source sample for convolution/blur kernels: a uniform frame must
// not grow a false white border, and blur halos must not eat the video edges.
export fn sampleVideoClamp(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  return textureSampleLevel(src, samp, clamp(uv, vec2f(0.0), vec2f(1.0)), 0.0);
}

export fn easeInOutCubic(t: f32) -> f32 {
  let x = clamp(t, 0.0, 1.0);
  if (x < 0.5) {
    return 4.0 * x * x * x;
  }
  let u = -2.0 * x + 2.0;
  return 1.0 - u * u * u / 2.0;
}

// Aspect-corrected rotation: uv is video UV, aspect = videoWidth / videoHeight.
export fn rotateUvAspect(uv: vec2f, angle: f32, center: vec2f, aspect: f32) -> vec2f {
  let c = cos(angle);
  let s = sin(angle);
  let p = (uv - center) * vec2f(aspect, 1.0);
  return center + vec2f(p.x * c - p.y * s, p.x * s + p.y * c) / vec2f(aspect, 1.0);
}

// Aspect-corrected zoom: a circular magnification in pixel space, not an
// ellipse in UV space (which is what naive (uv-center)/zoom does on non-square video).
export fn zoomAtAspect(uv: vec2f, zoom: f32, center: vec2f, aspect: f32) -> vec2f {
  let p = (uv - center) * vec2f(aspect, 1.0);
  return center + p / max(zoom, 0.01) / vec2f(aspect, 1.0);
}

export fn directionalBlur(src: texture_2d<f32>, samp: sampler, uv: vec2f, dir: vec2f) -> vec3f {
  var acc = vec3f(0.0);
  for (var i = 0; i < 9; i += 1) {
    let k = (f32(i) / 8.0 - 0.5) * 2.0;
    acc += sampleVideoClamp(src, samp, uv + dir * k).rgb;
  }
  return acc / 9.0;
}
