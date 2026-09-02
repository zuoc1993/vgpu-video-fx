import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const pixs0rEffect: EffectDefinition = {
  id: "pixs0r",
  name: "Pixs0r",
  category: "故障",
  description: "frei0r pixs0r 复刻：随机行块横移切片，JPEG 式错位抖动。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "blockHeight", label: "块高(px)", type: "range", min: 2, max: 64, step: 1, default: 12 },
    { key: "speed", label: "抖动速度", type: "range", min: 0, max: 2, step: 0.05, default: 0.6 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        blockHeight: values.blockHeight,
        speed: values.speed,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
