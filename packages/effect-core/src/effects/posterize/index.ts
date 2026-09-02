import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const posterizeEffect: EffectDefinition = {
  id: "posterize",
  name: "Posterize",
  category: "风格化",
  description: "frei0r posterize 复刻：色阶量化海报化，值越低越猛。",
  params: [
    { key: "levels", label: "量化级数", type: "range", min: 0.01, max: 1, step: 0.01, default: 0.02 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        levels: values.levels,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
