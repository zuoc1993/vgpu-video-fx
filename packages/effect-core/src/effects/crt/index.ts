import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const crtEffect: EffectDefinition = {
  id: "crt",
  name: "CRT",
  category: "复古",
  description: "移植 bevy_retro_shaders (MIT)：桶形曲率、径向色差、行故障、胶片噪点、波形扫描线与 CRT 暗角。",
  params: [
    { key: "curvature", label: "曲率", type: "range", min: 0, max: 1, step: 0.01, default: 0.35 },
    { key: "chromatic", label: "色差", type: "range", min: 0, max: 0.03, step: 0.001, default: 0.012 },
    { key: "scanline", label: "扫描线", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
    { key: "grain", label: "噪点", type: "range", min: 0, max: 0.3, step: 0.01, default: 0.08 },
    { key: "glitch", label: "故障强度", type: "range", min: 0, max: 0.5, step: 0.01, default: 0.12 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        curvature: values.curvature,
        chromatic: values.chromatic,
        scanline: values.scanline,
        grain: values.grain,
        glitch: values.glitch,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
