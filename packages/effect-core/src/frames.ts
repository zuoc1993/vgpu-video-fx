export type PixelBuffer = {
  width: number;
  height: number;
  /** Tightly packed RGBA8, `width * height * 4` bytes. */
  data: Uint8Array | Uint8ClampedArray;
  time?: number;
};

export type ImageSource = {
  source: TexImageSource | OffscreenCanvas;
  width?: number;
  height?: number;
  time?: number;
};

export type FrameIn = PixelBuffer | ImageSource;

export function isPixelBuffer(frame: FrameIn): frame is PixelBuffer {
  return "data" in frame;
}

export function frameSize(frame: FrameIn): readonly [number, number] {
  if (isPixelBuffer(frame)) return [frame.width, frame.height];
  const hinted = frame.width && frame.height ? ([frame.width, frame.height] as const) : null;
  if (hinted) return hinted;
  const src = frame.source;
  if (typeof HTMLVideoElement !== "undefined" && src instanceof HTMLVideoElement) {
    return [src.videoWidth, src.videoHeight];
  }
  if (typeof VideoFrame !== "undefined" && src instanceof VideoFrame) {
    return [src.displayWidth, src.displayHeight];
  }
  if ("width" in src && "height" in src) {
    return [Number(src.width), Number(src.height)];
  }
  throw new Error("cannot determine frame size");
}

export function frameTime(frame: FrameIn): number | undefined {
  return frame.time;
}
