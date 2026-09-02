import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const squigglevisionEffect: EffectDefinition = {
  id: "squigglevision",
  name: "Squigglevision",
  category: "扭曲",
  description: "frei0r squigglevision 复刻：分块值噪声位移，线条抖动式蠕变。",
  params: [
    { key: "strength", label: "位移强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "fps", label: "抖动频率", type: "range", min: 1, max: 30, step: 1, default: 10 },
    { key: "scale", label: "噪声粒度", type: "range", min: 2, max: 100, step: 1, default: 14 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        strength: values.strength,
        fps: values.fps,
        scale: values.scale,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
