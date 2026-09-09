import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const pixs0rEffect: EffectDefinition = {
  id: "pixs0r",
  name: "Pixs0r",
  category: "故障",
  description: "frei0r pixs0r 简化复刻：行/列块随机横移切片，块高可固定或随机。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "blockHeight", label: "块高(px，0=随机)", type: "range", min: 0, max: 64, step: 1, default: 12 },
    { key: "columns", label: "列错位", type: "range", min: 0, max: 1, step: 0.01, default: 0.35 },
    { key: "speed", label: "抖动速度", type: "range", min: 0, max: 2, step: 0.05, default: 0.6 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        blockHeight: values.blockHeight,
        columns: values.columns,
        speed: values.speed,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
