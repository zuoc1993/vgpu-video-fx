import { frameSize, isPixelBuffer } from "../packages/effect-core/src/frames.ts";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

const pixel = { width: 2, height: 2, data: new Uint8Array(16), time: 1 };
assert(isPixelBuffer(pixel), "pixel buffer");
assert(frameSize(pixel)[0] === 2 && frameSize(pixel)[1] === 2, "pixel size");

const image = { source: { width: 8, height: 4 }, time: 0 };
assert(!isPixelBuffer(image), "image source");
assert(frameSize(image)[0] === 8 && frameSize(image)[1] === 4, "image size");

console.log("ok frames");
