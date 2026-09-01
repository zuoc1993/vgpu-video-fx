import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const cameraShakeEffect: EffectDefinition = {
  id: "camera-shake",
  name: "镜头摇晃",
  category: "运镜",
  description: "机位随机平移，类似剪映「镜头晃动」。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "speed", label: "速度", type: "range", min: 0.2, max: 4, step: 0.05, default: 1.2 },
    { key: "frequency", label: "抖动频率", type: "range", min: 4, max: 30, step: 0.5, default: 14 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        speed: values.speed,
        frequency: values.frequency,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
