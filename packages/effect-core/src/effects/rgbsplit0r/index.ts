import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const rgbsplit0rEffect: EffectDefinition = {
  id: "rgbsplit0r",
  name: "Rgb split0r",
  category: "故障",
  description: "frei0r rgbsplit0r 复刻：RGB 通道错位，色差分离（0.5 为中性点）。",
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
