import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const edgeglowEffect: EffectDefinition = {
  id: "edgeglow",
  name: "Edge glow",
  category: "风格化",
  description: "frei0r edgeglow 复刻：Sobel 边缘提亮，可调色相的高光描边。",
  params: [
    { key: "threshold", label: "阈值", type: "range", min: 0, max: 0.5, step: 0.01, default: 0.12 },
    { key: "intensity", label: "光晕强度", type: "range", min: 0, max: 2, step: 0.05, default: 1.1 },
    { key: "hueShift", label: "光晕色相", type: "range", min: 0, max: 1, step: 0.01, default: 0 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        threshold: values.threshold,
        intensity: values.intensity,
        hueShift: values.hueShift,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
