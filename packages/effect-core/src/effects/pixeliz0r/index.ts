import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const pixeliz0rEffect: EffectDefinition = {
  id: "pixeliz0r",
  name: "Pixeliz0r",
  category: "像素",
  description: "frei0r pixeliz0r 复刻：按块取中心色，马赛克块状化。",
  params: [
    { key: "bw", label: "块宽", type: "range", min: 0.02, max: 0.4, step: 0.005, default: 0.05 },
    { key: "bh", label: "块高", type: "range", min: 0.02, max: 0.4, step: 0.005, default: 0.08 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        bw: values.bw,
        bh: values.bh,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
