import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const colorhalftoneEffect: EffectDefinition = {
  id: "colorhalftone",
  name: "Color halftone",
  category: "风格化",
  description: "frei0r colorhalftone 复刻：三色旋转网点半调印刷质感。",
  params: [
    { key: "dotRadius", label: "网点尺寸", type: "range", min: 0, max: 1, step: 0.01, default: 0.4 },
    { key: "angC", label: "青网点角", type: "range", min: 0, max: 1, step: 0.01, default: 0.3 },
    { key: "angM", label: "品红网点角", type: "range", min: 0, max: 1, step: 0.01, default: 0.45 },
    { key: "angY", label: "黄网点角", type: "range", min: 0, max: 1, step: 0.01, default: 0.25 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        dotRadius: values.dotRadius,
        angC: values.angC,
        angM: values.angM,
        angY: values.angY,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
