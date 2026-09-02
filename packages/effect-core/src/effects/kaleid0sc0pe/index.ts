import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const kaleid0sc0peEffect: EffectDefinition = {
  id: "kaleid0sc0pe",
  name: "Kaleid0sc0pe",
  category: "风格化",
  description: "frei0r kaleid0sc0pe 复刻：扇形镜像万花筒，径向扭曲 + 旋转。",
  params: [
    { key: "segs", label: "扇区数", type: "range", min: 3, max: 16, step: 1, default: 6 },
    { key: "zoom", label: "缩放", type: "range", min: 0.5, max: 1.6, step: 0.01, default: 1 },
    { key: "speed", label: "旋转速度", type: "range", min: 0, max: 1.5, step: 0.01, default: 0.25 },
    { key: "twist", label: "径向扭转", type: "range", min: 0, max: 2, step: 0.05, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        segs: values.segs,
        zoom: values.zoom,
        speed: values.speed,
        twist: values.twist,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
