import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const ditherEffect: EffectDefinition = {
  id: "dither",
  name: "Dither",
  category: "风格化",
  description: "frei0r dither 复刻：4×4 Bayer 有序抖动降色带，值越低越狠。",
  params: [
    { key: "levels", label: "量化级数", type: "range", min: 0.01, max: 1, step: 0.01, default: 0.05 },
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
