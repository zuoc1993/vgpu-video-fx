import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const glowEffect: EffectDefinition = {
  id: "glow",
  name: "Glow",
  category: "风格化",
  description: "frei0r glow 复刻（单 pass 近似）：八向采样光环叠加提亮。",
  params: [
    { key: "blur", label: "光晕半径", type: "range", min: 1, max: 24, step: 0.5, default: 9 },
    { key: "amount", label: "光强", type: "range", min: 0, max: 2, step: 0.05, default: 1.1 },
    { key: "threshold", label: "提亮阈值", type: "range", min: 0, max: 1, step: 0.01, default: 0.08 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        blur: values.blur,
        amount: values.amount,
        threshold: values.threshold,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
