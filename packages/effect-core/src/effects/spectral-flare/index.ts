import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const spectralFlareEffect: EffectDefinition = {
  id: "spectral-flare",
  name: "Spectral flare",
  category: "风格化",
  description: "移植 PrismaticShadersPack (MIT)：高光驱动 6 波长谱段 ghost 光晕与彩虹边缘。",
  params: [
    { key: "threshold", label: "高光阈值", type: "range", min: 0, max: 1, step: 0.01, default: 0.6 },
    { key: "strength", label: "光晕强度", type: "range", min: 0, max: 2, step: 0.05, default: 0.9 },
    { key: "size", label: "光晕尺寸", type: "range", min: 0, max: 2, step: 0.05, default: 0.8 },
    { key: "halo", label: "宽光带", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        threshold: values.threshold,
        strength: values.strength,
        size: values.size,
        halo: values.halo,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
