import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const dissolveEffect: EffectDefinition = {
  id: "dissolve",
  name: "Dissolve",
  category: "转场",
  description: "fBm 阈值溶解：噪声场扫过画面，边缘带燃火色描边，循环节奏。",
  params: [
    { key: "speed", label: "溶解速度", type: "range", min: 0, max: 2, step: 0.05, default: 0.5 },
    { key: "scale", label: "噪点粗细", type: "range", min: 2, max: 16, step: 0.1, default: 5 },
    { key: "edgeGlow", label: "边缘火色", type: "range", min: 0, max: 1, step: 0.01, default: 0.8 },
    { key: "invert", label: "反转", type: "range", min: 0, max: 1, step: 1, default: 0 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        speed: values.speed,
        scale: values.scale,
        edgeGlow: values.edgeGlow,
        invert: values.invert,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
