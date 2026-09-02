import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const defish0rEffect: EffectDefinition = {
  id: "defish0r",
  name: "Defish0r",
  category: "扭曲",
  description: "frei0r defish0r 复刻：桶形/鱼眼径向畸变。",
  params: [
    { key: "amount", label: "畸变量", type: "range", min: 0, max: 1, step: 0.01, default: 0.55 },
    { key: "scale", label: "缩放", type: "range", min: 0.5, max: 1.5, step: 0.01, default: 0.9 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        amount: values.amount,
        scale: values.scale,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
