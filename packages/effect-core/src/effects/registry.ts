import type { EffectDefinition } from "./types.ts";
import { cameraShakeEffect } from "./camera-shake/index.ts";
import { colorhalftoneEffect } from "./colorhalftone/index.ts";
import { crtEffect } from "./crt/index.ts";
import { curtainWindEffect } from "./curtain-wind/index.ts";
import { cylinderWrapEffect } from "./cylinder-wrap/index.ts";
import { defish0rEffect } from "./defish0r/index.ts";
import { dissolveEffect } from "./dissolve/index.ts";
import { dustBokehEffect } from "./dust-bokeh/index.ts";
import { gradeEffect } from "./grade/index.ts";
import { lightLeakEffect } from "./light-leak/index.ts";
import { retroQuantizeEffect } from "./retro-quantize/index.ts";
import { ditherEffect } from "./dither/index.ts";
import { distort0rEffect } from "./distort0r/index.ts";
import { edgeglowEffect } from "./edgeglow/index.ts";
import { embossEffect } from "./emboss/index.ts";
import { glitchEffect } from "./glitch/index.ts";
import { glitch0rEffect } from "./glitch0r/index.ts";
import { glowEffect } from "./glow/index.ts";
import { handheldCamEffect } from "./handheld-cam/index.ts";
import { heatmap0rEffect } from "./heatmap0r/index.ts";
import { kaleid0sc0peEffect } from "./kaleid0sc0pe/index.ts";
import { localPushEffect } from "./local-push/index.ts";
import { noneEffect } from "./none/index.ts";
import { ntscEffect } from "./ntsc/index.ts";
import { pixeliz0rEffect } from "./pixeliz0r/index.ts";
import { pixels0rtEffect } from "./pixels0rt/index.ts";
import { pixs0rEffect } from "./pixs0r/index.ts";
import { posterizeEffect } from "./posterize/index.ts";
import { rgbsplit0rEffect } from "./rgbsplit0r/index.ts";
import { scanline0rEffect } from "./scanline0r/index.ts";
import { screenShakeEffect } from "./screen-shake/index.ts";
import { spacetimeLensEffect } from "./spacetime-lens/index.ts";
import { spectralFlareEffect } from "./spectral-flare/index.ts";
import { sobelEffect } from "./sobel/index.ts";
import { squigglevisionEffect } from "./squigglevision/index.ts";
import { vignetteEffect } from "./vignette/index.ts";
import { waterEffect } from "./water/index.ts";
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
  cylinderWrapEffect,
  pixeliz0rEffect,
  squigglevisionEffect,
  colorhalftoneEffect,
  sobelEffect,
  waterEffect,
  defish0rEffect,
  vignetteEffect,
  heatmap0rEffect,
  glitch0rEffect,
  pixels0rtEffect,
  kaleid0sc0peEffect,
  distort0rEffect,
  rgbsplit0rEffect,
  embossEffect,
  posterizeEffect,
  pixs0rEffect,
  ditherEffect,
  ntscEffect,
  edgeglowEffect,
  scanline0rEffect,
  glowEffect,
  crtEffect,
  spectralFlareEffect,
  dustBokehEffect,
  spacetimeLensEffect,
  retroQuantizeEffect,
  gradeEffect,
  lightLeakEffect,
  dissolveEffect,
  curtainWindEffect,
];

export function getEffect(id: string): EffectDefinition | undefined {
  return catalog.find((item) => item.id === id);
}
