import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const screenShakeEffect: EffectDefinition = {
  id: "screen-shake",
  name: "Screen Shake",
  category: "冲击",
  description: "整屏冲击：位移、缩放，峰值是长斜向拖影。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.7 },
    { key: "speed", label: "速度", type: "range", min: 0.2, max: 4, step: 0.05, default: 1.6 },
    { key: "punch", label: "缩放冲击", type: "range", min: 0, max: 2, step: 0.01, default: 0.9 },
    { key: "blur", label: "运动模糊", type: "range", min: 0, max: 2, step: 0.01, default: 0.85 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        speed: values.speed,
        punch: values.punch,
        blur: values.blur,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
