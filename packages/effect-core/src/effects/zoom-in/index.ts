import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const zoomInEffect: EffectDefinition = {
  id: "zoom-in",
  name: "Zoom in",
  category: "缩放",
  description: "图层由小变大，S 形缓动，对齐参考片 50%→70% 的放大。",
  params: [
    { key: "startScale", label: "起始缩放", type: "range", min: 0.2, max: 1.5, step: 0.01, default: 0.5 },
    { key: "endScale", label: "结束缩放", type: "range", min: 0.2, max: 1.5, step: 0.01, default: 0.7 },
    { key: "duration", label: "时长(秒)", type: "range", min: 0.2, max: 8, step: 0.05, default: 1 },
    { key: "loop", label: "循环", type: "range", min: 0, max: 1, step: 1, default: 1 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        videoTime: ctx.videoDuration > 0 ? ctx.videoTime : ctx.time,
        startScale: values.startScale,
        endScale: values.endScale,
        duration: values.duration,
        looping: values.loop,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
