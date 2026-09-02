import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const vignetteEffect: EffectDefinition = {
  id: "vignette",
  name: "Vignette",
  category: "调整",
  description: "frei0r vignette 复刻：径向暗角，带中心留白与软边。",
  params: [
    { key: "amount", label: "暗度", type: "range", min: 0, max: 1, step: 0.01, default: 0.8 },
    { key: "radius", label: "半径", type: "range", min: 0.3, max: 1.2, step: 0.01, default: 0.85 },
    { key: "softness", label: "软边", type: "range", min: 0.05, max: 1, step: 0.01, default: 0.6 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        amount: values.amount,
        radius: values.radius,
        softness: values.softness,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
