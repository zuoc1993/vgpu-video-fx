import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const gradeEffect: EffectDefinition = {
  id: "grade",
  name: "Grade",
  category: "调整",
  description: "语义来自 PrismaticShadersPack (MIT)：lift/gamma/gain 电影调色 + 饱和度，一键去灰。",
  params: [
    { key: "lift", label: "提暗部", type: "range", min: -1, max: 1, step: 0.01, default: 0.05 },
    { key: "gamma", label: "伽马", type: "range", min: 0.4, max: 1.8, step: 0.01, default: 0.85 },
    { key: "gain", label: "增益", type: "range", min: 0.6, max: 1.6, step: 0.01, default: 1.05 },
    { key: "saturation", label: "饱和度", type: "range", min: 0, max: 2, step: 0.01, default: 1.15 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        lift: values.lift,
        gamma: values.gamma,
        gain: values.gain,
        saturation: values.saturation,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
