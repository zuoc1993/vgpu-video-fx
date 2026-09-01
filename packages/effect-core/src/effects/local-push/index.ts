import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const localPushEffect: EffectDefinition = {
  id: "local-push",
  name: "局部推镜",
  category: "运镜",
  description: "朝焦点径向推进，峰值带拉丝模糊、红青边和扭曲。",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.75 },
    { key: "speed", label: "速度", type: "range", min: 0.1, max: 3, step: 0.05, default: 0.85 },
    { key: "zoom", label: "推进幅度", type: "range", min: 0, max: 1.2, step: 0.01, default: 0.45 },
    { key: "centerX", label: "水平焦点", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "centerY", label: "垂直焦点", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "chromatic", label: "色差", type: "range", min: 0, max: 2, step: 0.01, default: 0.7 },
    { key: "distortion", label: "扭曲", type: "range", min: 0, max: 2, step: 0.01, default: 0.4 },
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
        glow: values.glow,
        chromatic: values.chromatic,
        distortion: values.distortion,
        centerX: values.centerX,
        centerY: values.centerY,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
