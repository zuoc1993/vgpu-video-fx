import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const sobelEffect: EffectDefinition = {
  id: "sobel",
  name: "Sobel edges",
  category: "风格化",
  description: "frei0r sobel 复刻：3×3 Sobel 边缘检测，白边黑底。",
  params: [
    { key: "threshold", label: "阈值", type: "range", min: 0, max: 0.5, step: 0.01, default: 0.12 },
    { key: "gain", label: "增益", type: "range", min: 0.5, max: 3, step: 0.05, default: 1.4 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        threshold: values.threshold,
        gain: values.gain,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
