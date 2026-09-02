import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const lightLeakEffect: EffectDefinition = {
  id: "light-leak",
  name: "Light leak",
  category: "氛围",
  description: "胶片漏光：暖色光带扫屏 + 角落漏光，现代氛围滤镜。",
  params: [
    { key: "intensity", label: "漏光强度", type: "range", min: 0, max: 1.5, step: 0.05, default: 0.7 },
    { key: "size", label: "光带宽度", type: "range", min: 0.2, max: 2, step: 0.05, default: 0.9 },
    { key: "speed", label: "扫动速度", type: "range", min: 0, max: 2, step: 0.05, default: 0.6 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        size: values.size,
        speed: values.speed,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
