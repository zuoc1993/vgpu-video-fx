import type { EffectDefinition } from "./types.ts";
import { cameraShakeEffect } from "./camera-shake/index.ts";
import { glitchEffect } from "./glitch/index.ts";
import { handheldCamEffect } from "./handheld-cam/index.ts";
import { localPushEffect } from "./local-push/index.ts";
import { noneEffect } from "./none/index.ts";
import { screenShakeEffect } from "./screen-shake/index.ts";
import { zoomInEffect } from "./zoom-in/index.ts";
import { zoomOutEffect } from "./zoom-out/index.ts";

/** Add a new effect by exporting its definition and appending it here. */
export const catalog: readonly EffectDefinition[] = [
  noneEffect,
  handheldCamEffect,
  cameraShakeEffect,
  localPushEffect,
  glitchEffect,
  screenShakeEffect,
  zoomInEffect,
  zoomOutEffect,
];

export function getEffect(id: string): EffectDefinition | undefined {
  return catalog.find((item) => item.id === id);
}
