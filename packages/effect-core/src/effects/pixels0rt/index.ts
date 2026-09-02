import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const pixels0rtEffect: EffectDefinition = {
  id: "pixels0rt",
  name: "Pixels0rt",
  category: "像素",
  description: "frei0r pixels0rt 简化复刻：每列条带拉伸最亮像素形成像素拉丝。",
  params: [
    { key: "width", label: "条带宽", type: "range", min: 0, max: 1, step: 0.01, default: 0.4 },
    { key: "strength", label: "拉丝强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.8 },
    { key: "threshold", label: "亮度阈值", type: "range", min: 0, max: 1, step: 0.01, default: 0.25 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        width: values.width,
        strength: values.strength,
        threshold: values.threshold,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
