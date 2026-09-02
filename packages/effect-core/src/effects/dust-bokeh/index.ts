import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const dustBokehEffect: EffectDefinition = {
  id: "dust-bokeh",
  name: "Dust bokeh",
  category: "氛围",
  description: "灵感来自 PrismaticShadersPack 尘埃粒子 (MIT)：程序化焦外尘点，深度控制虚化半径。",
  params: [
    { key: "count", label: "颗粒数", type: "range", min: 4, max: 24, step: 1, default: 16 },
    { key: "size", label: "粒径", type: "range", min: 0.2, max: 2, step: 0.05, default: 1 },
    { key: "focus", label: "对焦深度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "opacity", label: "亮度", type: "range", min: 0, max: 2, step: 0.05, default: 1 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        count: values.count,
        size: values.size,
        focus: values.focus,
        opacity: values.opacity,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
