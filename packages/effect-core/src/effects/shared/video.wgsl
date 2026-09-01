// Pure helpers: no @group/@binding. Entry shaders own resources.

export fn containUv(uv: vec2f, canvas: vec2f, video: vec2f) -> vec2f {
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

export fn sampleVideo(src: texture_2d<f32>, samp: sampler, uv: vec2f) -> vec4f {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  return textureSampleLevel(src, samp, uv, 0.0);
}

export fn easeInOutCubic(t: f32) -> f32 {
  let x = clamp(t, 0.0, 1.0);
  if (x < 0.5) {
    return 4.0 * x * x * x;
  }
  let u = -2.0 * x + 2.0;
  return 1.0 - u * u * u / 2.0;
}

export fn rotateUv(uv: vec2f, angle: f32, center: vec2f) -> vec2f {
  let c = cos(angle);
  let s = sin(angle);
  let p = uv - center;
  return vec2f(p.x * c - p.y * s, p.x * s + p.y * c) + center;
}

export fn zoomAt(uv: vec2f, zoom: f32, center: vec2f) -> vec2f {
  return (uv - center) / max(zoom, 0.01) + center;
}

export fn directionalBlur(src: texture_2d<f32>, samp: sampler, uv: vec2f, dir: vec2f) -> vec3f {
  var acc = vec3f(0.0);
  for (var i = 0; i < 9; i += 1) {
    let k = (f32(i) / 8.0 - 0.5) * 2.0;
    acc += sampleVideo(src, samp, uv + dir * k).rgb;
  }
  return acc / 9.0;
}
