import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const cylinderWrapEffect: EffectDefinition = {
  id: "cylinder-wrap",
  name: "Cylinder wrap",
  category: "3D",
  description: "平面视窗卷成竖轴滚筒内壁并绕轴旋转，面板带黑缝与圆角，末段前推铺满全屏。",
  params: [
    { key: "radius", label: "滚筒半径", type: "range", min: 0.4, max: 2, step: 0.01, default: 0.9 },
    { key: "depth", label: "纵深感", type: "range", min: 0, max: 2, step: 0.01, default: 0.9 },
    { key: "scale", label: "画面缩放", type: "range", min: 0.5, max: 1, step: 0.01, default: 0.85 },
    { key: "speed", label: "旋转速度", type: "range", min: 0, max: 1.5, step: 0.01, default: 0.35 },
    { key: "panels", label: "面板数", type: "range", min: 3, max: 12, step: 1, default: 6 },
    { key: "gap", label: "面板缝隙", type: "range", min: 0, max: 0.3, step: 0.01, default: 0.1 },
    { key: "corner", label: "圆角", type: "range", min: 0, max: 0.3, step: 0.01, default: 0.08 },
    { key: "duration", label: "周期(秒)", type: "range", min: 0.5, max: 8, step: 0.05, default: 3 },
    { key: "loop", label: "循环", type: "range", min: 0, max: 1, step: 1, default: 1 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        videoTime: ctx.videoDuration > 0 ? ctx.videoTime : ctx.time,
        radius: values.radius,
        depth: values.depth,
        scale: values.scale,
        speed: values.speed,
        panels: values.panels,
        gap: values.gap,
        corner: values.corner,
        duration: values.duration,
        looping: values.loop,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
