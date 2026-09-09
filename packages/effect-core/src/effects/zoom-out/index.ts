import type { EffectDefinition } from "../types.ts";
import shader from "../zoom-in/effect.wgsl";

export const zoomOutEffect: EffectDefinition = {
  id: "zoom-out",
  name: "Zoom out",
  category: "缩放",
  description: "全屏缩小，S 形缓动并向右缓慢漂移；默认 1.35→1.0 不露黑边。",
  params: [
    { key: "startScale", label: "起始缩放", type: "range", min: 0.5, max: 2, step: 0.01, default: 1.35 },
    { key: "endScale", label: "结束缩放", type: "range", min: 0.5, max: 2, step: 0.01, default: 1.0 },
    { key: "duration", label: "时长(秒)", type: "range", min: 0.2, max: 8, step: 0.05, default: 1 },
    { key: "centerX", label: "中心 X", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "centerY", label: "中心 Y", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "drift", label: "横向漂移", type: "range", min: -1, max: 1, step: 0.01, default: 0.35 },
    { key: "loop", label: "循环", type: "range", min: 0, max: 1, step: 1, default: 0 },
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
        centerX: values.centerX,
        centerY: values.centerY,
        drift: values.drift,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
