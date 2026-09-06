import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const curtainWindEffect: EffectDefinition = {
  id: "curtain-wind",
  name: "Curtain Wind",
  category: "扭曲",
  description: "风吹窗帘/床单：画面化作挂在杆上的布，顶端固定、下摆自由，褶皱随风向下滚动，褶边透出暖阳。",
  params: [
    { key: "strength", label: "风力", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "folds", label: "褶皱数", type: "range", min: 1, max: 8, step: 0.1, default: 3.5 },
    { key: "speed", label: "风速", type: "range", min: 0, max: 3, step: 0.05, default: 1.0 },
    { key: "gust", label: "阵风", type: "range", min: 0, max: 1, step: 0.01, default: 0.65 },
    { key: "sway", label: "摆动", type: "range", min: 0, max: 1, step: 0.01, default: 0.4 },
    { key: "bleed", label: "透光", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        strength: values.strength,
        folds: values.folds,
        speed: values.speed,
        gust: values.gust,
        sway: values.sway,
        bleed: values.bleed,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
