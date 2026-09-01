import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const glitchEffect: EffectDefinition = {
  id: "glitch",
  name: "Glitch",
  category: "故障",
  description: "水平撕裂、RGB 错位，爆发时叠品红 / 黄 / 青等半透明竖条和色块。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.7 },
    { key: "speed", label: "速度", type: "range", min: 0.2, max: 4, step: 0.05, default: 1.4 },
    { key: "slices", label: "条带数", type: "range", min: 4, max: 80, step: 1, default: 28 },
    { key: "rgbSplit", label: "RGB 分离", type: "range", min: 0, max: 3, step: 0.01, default: 1 },
    { key: "block", label: "色块撕裂", type: "range", min: 0, max: 2, step: 0.01, default: 0.8 },
    { key: "scanline", label: "扫描线", type: "range", min: 0, max: 1, step: 0.01, default: 0.35 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        speed: values.speed,
        slices: values.slices,
        rgbSplit: values.rgbSplit,
        block: values.block,
        scanline: values.scanline,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
