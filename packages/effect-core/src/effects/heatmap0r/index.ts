import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const heatmap0rEffect: EffectDefinition = {
  id: "heatmap0r",
  name: "Heatmap0r",
  category: "风格化",
  description: "frei0r heatmap0r 复刻：亮度映射紫-品红-黄热力色。",
  params: [
    { key: "hueShift", label: "色相偏移", type: "range", min: 0, max: 1, step: 0.01, default: 0 },
    { key: "greyPoint", label: "灰度中点", type: "range", min: 0.1, max: 0.9, step: 0.01, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        hueShift: values.hueShift,
        greyPoint: values.greyPoint,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
