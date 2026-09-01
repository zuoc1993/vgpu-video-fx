import {
  effectClock,
  isDecoded,
  needsSeekToStart,
  shouldPushParams,
  waitVideoEvent,
} from "../packages/web/src/video-wait.ts";

class FakeVideo {
  readyState = 0;
  videoWidth = 0;
  error = null;
  listeners = new Map();

  addEventListener(type, fn) {
    const set = this.listeners.get(type) ?? new Set();
    set.add(fn);
    this.listeners.set(type, set);
  }

  removeEventListener(type, fn) {
    this.listeners.get(type)?.delete(fn);
  }

  emit(type) {
    for (const fn of [...(this.listeners.get(type) ?? [])]) fn();
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

assert(!isDecoded(0, 1920), "empty readyState");
assert(!isDecoded(2, 0), "zero width");
assert(isDecoded(2, 480), "decoded");
assert(!needsSeekToStart(0), "already at start");
assert(needsSeekToStart(1.2), "needs seek");
assert(effectClock(true, 3, 99) === 3, "video clock");
assert(effectClock(false, 3, 99) === 99, "gpu clock");
assert(shouldPushParams(true, false), "dirty");
assert(shouldPushParams(false, true), "playing");
assert(!shouldPushParams(false, false), "paused clean");

const already = new FakeVideo();
already.readyState = 2;
already.videoWidth = 640;
await waitVideoEvent(already, "loadeddata");

const pending = new FakeVideo();
const loaded = waitVideoEvent(pending, "loadeddata");
pending.readyState = 2;
pending.videoWidth = 320;
pending.emit("loadeddata");
await loaded;

const boom = new FakeVideo();
const failed = waitVideoEvent(boom, "loadeddata");
boom.error = { message: "decode failed" };
boom.emit("error");
try {
  await failed;
  throw new Error("expected reject");
} catch (err) {
  assert(err instanceof Error && err.message === "decode failed", "error message");
}

try {
  await waitVideoEvent(new FakeVideo(), "loadeddata", 20);
  throw new Error("expected timeout");
} catch (err) {
  assert(err instanceof Error && err.message === "视频加载超时", "timeout message");
}

console.log("ok video-wait");
