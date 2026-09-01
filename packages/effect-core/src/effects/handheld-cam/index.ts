import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const handheldCamEffect: EffectDefinition = {
  id: "handheld-cam",
  name: "摇晃运镜",
  category: "运镜",
  description: "手持运镜：缩放摆动，峰值时整屏斜向拖影，高光带辉光。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.75 },
    { key: "speed", label: "速度", type: "range", min: 0.1, max: 4, step: 0.05, default: 1 },
    { key: "zoom", label: "变焦幅度", type: "range", min: 0, max: 0.35, step: 0.005, default: 0.14 },
    { key: "sway", label: "摆动", type: "range", min: 0, max: 2, step: 0.01, default: 1 },
    { key: "blur", label: "运动模糊", type: "range", min: 0, max: 2, step: 0.01, default: 1 },
    { key: "glow", label: "辉光", type: "range", min: 0, max: 2, step: 0.01, default: 0.55 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        speed: values.speed,
        zoom: values.zoom,
        sway: values.sway,
        glow: values.glow,
        blur: values.blur,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
