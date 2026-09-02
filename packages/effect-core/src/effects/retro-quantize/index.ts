import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const retroQuantizeEffect: EffectDefinition = {
  id: "retro-quantize",
  name: "Retro quantize",
  category: "复古",
  description: "概念来自 msg_shaders (Apache-2.0)：Oklab 最近调色板匹配 + Bayer 抖动，复古量化。",
  params: [
    { key: "colors", label: "色数", type: "range", min: 0, max: 3, step: 1, default: 2 },
    { key: "dither", label: "抖动", type: "range", min: 0, max: 1, step: 0.01, default: 0.6 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        colors: values.colors,
        dither: values.dither,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
