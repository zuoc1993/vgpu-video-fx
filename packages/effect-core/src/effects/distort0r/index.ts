import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const distort0rEffect: EffectDefinition = {
  id: "distort0r",
  name: "Distort0r",
  category: "扭曲",
  description: "frei0r distort0r 复刻：Perlin 平滑场位移，波浪形扭曲。",
  params: [
    { key: "amplitude", label: "幅度", type: "range", min: 0, max: 1, step: 0.01, default: 0.35 },
    { key: "freq", label: "频率", type: "range", min: 0.5, max: 16, step: 0.1, default: 3 },
    { key: "speed", label: "速度", type: "range", min: 0, max: 3, step: 0.05, default: 0.8 },
    { key: "velocity", label: "漂向", type: "range", min: 0, max: 1, step: 0.05, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        amplitude: values.amplitude,
        freq: values.freq,
        speed: values.speed,
        velocity: values.velocity,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
