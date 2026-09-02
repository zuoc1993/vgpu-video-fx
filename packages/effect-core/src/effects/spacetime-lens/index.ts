import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const spacetimeLensEffect: EffectDefinition = {
  id: "spacetime-lens",
  name: "Spacetime lens",
  category: "扭曲",
  description: "灵感来自 msg_shaders 黑洞透镜 (Apache-2.0，Bruneton BSD-3)：2D 引力偏折 + 光子环回声。",
  params: [
    { key: "radius", label: "事件视界", type: "range", min: 0.02, max: 0.3, step: 0.01, default: 0.09 },
    { key: "strength", label: "偏折强度", type: "range", min: 0, max: 3, step: 0.05, default: 1.6 },
    { key: "echo", label: "光子环回声", type: "range", min: 0, max: 1.5, step: 0.05, default: 0.8 },
    { key: "swirl", label: "旋涡", type: "range", min: 0, max: 1, step: 0.01, default: 0.3 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        radius: values.radius,
        strength: values.strength,
        echo: values.echo,
        swirl: values.swirl,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
