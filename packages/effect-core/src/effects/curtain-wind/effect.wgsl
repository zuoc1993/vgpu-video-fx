import { containUv, sampleVideo } from "../shared/video.wgsl";

struct Params {
  time: f32,
  strength: f32,
  folds: f32,
  speed: f32,
  gust: f32,
  sway: f32,
  bleed: f32,
  resolution: vec2f,
  videoSize: vec2f,
}

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;
@group(0) @binding(2) var<uniform> params: Params;

const TAU: f32 = 6.2831853;
// 光源：左上方、略偏向观察者。
const LIGHT: vec3f = vec3f(-0.3505, -0.4506, 0.8211);
// 暖色背光（阳光透布）。
const WARM: vec3f = vec3f(1.0, 0.82, 0.58);

// 阵风包络 [0,1]：几条慢速正弦叠加后锐化，制造起风/停歇的呼吸感。
fn gustEnv(t: f32) -> f32 {
  let g = sin(t * 0.45) * 0.5 + sin(t * 0.83 + 1.7) * 0.3 + sin(t * 0.21 + 0.5) * 0.2;
  return pow(0.5 + 0.5 * g, 1.35);
}

@fragment
fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let v = containUv(uv, params.resolution, params.videoSize);
  if (v.x < 0.0 || v.x > 1.0 || v.y < 0.0 || v.y > 1.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }

  let t = params.time * (0.4 + params.speed);
  // 布料自由度：顶端挂在杆上为 0，下摆为 1。
  let freedom = pow(v.y, 0.8);
  let dfreedom = min(0.8 * pow(max(v.y, 1e-3), -0.2), 3.0);
  let env = (1.0 - params.gust) * 0.62 + params.gust * gustEnv(t) * 1.25;

  // ---- 布面高度场 z(v) --------------------------------------------------
  // 垂直褶皱为主，相位沿 y 向下漂移 → 风从杆边一路滚到下摆；再加整面布
  // 的低频"呼吸"鼓起。
  let wob = v.y * 2.6 - t * 1.8;
  let phase = v.x * params.folds * TAU
            + sin(wob) * 0.9 * freedom
            + sin(t * 0.5) * params.sway * 0.8;
  let amp = params.strength * 0.055 * env * freedom;
  let bphase = v.y * 2.2 - t * 1.1 + v.x * 1.2;
  let bamp = params.strength * 0.05 * env * freedom;
  let z = amp * sin(phase) + bamp * sin(bphase);

  // 高度场梯度（解析求导；uv 与 z 同单位）。
  let dzdx = amp * cos(phase) * params.folds * TAU
           + bamp * cos(bphase) * 1.2;
  let dzdy = params.strength * 0.055 * env * dfreedom * sin(phase)
           + amp * cos(phase) * cos(wob) * 2.34 * freedom
           + amp * cos(phase) * sin(wob) * 0.9 * dfreedom
           + bamp * cos(bphase) * 2.2
           + params.strength * 0.05 * env * dfreedom * sin(bphase);

  // ---- 形变：到布面真正所在的位置取样 ------------------------------------
  // 褶皱沿 x 挤压/拉伸；整体鼓起时下摆上抬；外加整幅缓摆。
  var du = dzdx * 0.05 + sin(t * 0.42) * params.sway * 0.035 * freedom;
  var dv = -z * 0.4 + sin(t * 0.9 + 1.3) * params.sway * 0.012 * freedom;
  // 软限幅：再大的风，布边也只露出一条细缝而不是黑洞。
  let wl = length(vec2f(du, dv));
  let wmax = 0.085;
  if (wl > wmax) {
    let k = wmax / wl;
    du *= k;
    dv *= k;
  }
  let suv = vec2f(v.x + du, v.y + dv);
  let inside = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
  let col = sampleVideo(src, samp, suv);

  // ---- 光照 -------------------------------------------------------------
  let n = normalize(vec3f(-dzdx, -dzdy, 1.0));
  let diff = max(dot(n, LIGHT), 0.0);
  var shade = 0.55 + 0.48 * diff;                 // 褶皱上流动的明暗
  shade *= 1.0 + z * 1.4;                         // 鼓向镜头的布面更亮
  let rim = (1.0 - n.z) * (1.0 - n.z);            // 侧对的褶边透背光
  let hv = normalize(LIGHT + vec3f(0.0, 0.0, 1.0));
  let sheen = pow(max(dot(n, hv), 0.0), 24.0) * 0.10;   // 丝绸光泽
  let glow = WARM * (rim * 0.30 + sheen) * params.bleed * inside;

  return vec4f(col.rgb * shade + glow, 1.0);
}
