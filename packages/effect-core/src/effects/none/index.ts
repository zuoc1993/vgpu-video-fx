import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const noneEffect: EffectDefinition = {
  id: "none",
  name: "原片",
  category: "基础",
  description: "不处理，只按画布比例完整显示视频。",
  params: [],
  shader,
  uniforms(_values, ctx) {
    return {
      params: {
        time: ctx.time,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
