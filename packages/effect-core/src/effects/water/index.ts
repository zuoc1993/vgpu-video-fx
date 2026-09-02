import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const waterEffect: EffectDefinition = {
  id: "water",
  name: "Water",
  category: "扭曲",
  description: "frei0r water 复刻：层叠正弦涟漪 + 中心缓旋涡。",
  params: [
    { key: "amp", label: "波幅", type: "range", min: 0, max: 0.05, step: 0.005, default: 0.035 },
    { key: "freq", label: "波纹频率", type: "range", min: 0.5, max: 8, step: 0.1, default: 1.6 },
    { key: "speed", label: "波速", type: "range", min: 0, max: 3, step: 0.05, default: 0.9 },
    { key: "swirl", label: "旋涡", type: "range", min: 0, max: 3, step: 0.05, default: 0.8 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        amp: values.amp,
        freq: values.freq,
        speed: values.speed,
        swirl: values.swirl,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
