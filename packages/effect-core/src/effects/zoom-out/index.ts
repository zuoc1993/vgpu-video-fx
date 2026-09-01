import type { EffectDefinition } from "../types.ts";
import shader from "../zoom-in/effect.wgsl";

export const zoomOutEffect: EffectDefinition = {
  id: "zoom-out",
  name: "Zoom out",
  category: "缩放",
  description: "图层由大变小，S 形缓动，对齐参考片 70%→50% 的缩小。",
  params: [
    { key: "startScale", label: "起始缩放", type: "range", min: 0.2, max: 1.5, step: 0.01, default: 0.7 },
    { key: "endScale", label: "结束缩放", type: "range", min: 0.2, max: 1.5, step: 0.01, default: 0.5 },
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
