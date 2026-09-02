import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const scanline0rEffect: EffectDefinition = {
  id: "scanline0r",
  name: "Scanline0r",
  category: "复古",
  description: "frei0r scanline0r 复刻：CRT 逐行扫描线 + 荫罩式色栅。",
  params: [
    { key: "strength", label: "扫描线强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.6 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        strength: values.strength,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
