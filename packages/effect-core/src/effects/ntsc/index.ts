import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const ntscEffect: EffectDefinition = {
  id: "ntsc",
  name: "NTSC",
  category: "复古",
  description: "frei0r ntsc 复刻：NTSC 色差采样、动态行相位色闪、信号噪点与扫描线。",
  params: [
    { key: "noise", label: "信号噪点", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "scanlines", label: "扫描线", type: "range", min: 0, max: 1, step: 0.01, default: 0.6 },
    { key: "burst", label: "色差窜扰", type: "range", min: 0, max: 1, step: 0.01, default: 0.4 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        noise: values.noise,
        scanlines: values.scanlines,
        burst: values.burst,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
