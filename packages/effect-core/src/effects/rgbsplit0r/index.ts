import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const rgbsplit0rEffect: EffectDefinition = {
  id: "rgbsplit0r",
  name: "Rgb split0r",
  category: "故障",
  description: "frei0r rgbsplit0r 复刻：水平/垂直独立控制 R/B 反向通道错位（0.5 中性）。",
  params: [
    { key: "vertical", label: "垂直分离", type: "range", min: 0, max: 1, step: 0.01, default: 0.9 },
    { key: "horizontal", label: "水平分离", type: "range", min: 0, max: 1, step: 0.01, default: 0.9 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        vertical: values.vertical,
        horizontal: values.horizontal,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
