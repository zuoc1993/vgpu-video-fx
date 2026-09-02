import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const glitch0rEffect: EffectDefinition = {
  id: "glitch0r",
  name: "Glitch0r",
  category: "故障",
  description: "frei0r glitch0r 复刻：行块错位、RGB 分离与色相翻转的故障切片。",
  params: [
    { key: "frequency", label: "触发频率", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "blockHeight", label: "切片高度", type: "range", min: 0, max: 1, step: 0.01, default: 0.6 },
    { key: "shift", label: "移位强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "colorAmt", label: "色彩故障", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        frequency: values.frequency,
        blockHeight: values.blockHeight,
        shift: values.shift,
        colorAmt: values.colorAmt,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
