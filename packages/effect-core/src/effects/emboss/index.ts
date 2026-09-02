import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const embossEffect: EffectDefinition = {
  id: "emboss",
  name: "Emboss",
  category: "风格化",
  description: "frei0r emboss 复刻：方向梯度浮雕，灰底凸起。",
  params: [
    { key: "azimuth", label: "光照方向", type: "range", min: 0, max: 1, step: 0.01, default: 0.33 },
    { key: "elevation", label: "浮雕高度", type: "range", min: 0, max: 1, step: 0.01, default: 0.35 },
    { key: "width", label: "效果宽度", type: "range", min: 0.5, max: 10, step: 0.1, default: 2.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        azimuth: values.azimuth,
        elevation: values.elevation,
        width: values.width,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
