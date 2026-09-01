const HAVE_CURRENT_DATA = 2;

export type VideoEventTarget = {
  readyState: number;
  videoWidth: number;
  error: { message: string } | null;
  addEventListener(type: string, fn: () => void): void;
  removeEventListener(type: string, fn: () => void): void;
};

export function isDecoded(readyState: number, videoWidth: number): boolean {
  return readyState >= HAVE_CURRENT_DATA && videoWidth > 0;
}

export function needsSeekToStart(currentTime: number): boolean {
  return currentTime > 1e-3;
}

export function effectClock(ready: boolean, videoTime: number, gpuTime: number): number {
  return ready ? videoTime : gpuTime;
}

export function shouldPushParams(paramsDirty: boolean, playing: boolean): boolean {
  return paramsDirty || playing;
}

export function waitVideoEvent(
  el: VideoEventTarget,
  ok: "loadeddata" | "seeked",
  timeoutMs = 30_000,
): Promise<void> {
  if (ok === "loadeddata" && isDecoded(el.readyState, el.videoWidth)) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const finish = (fn: () => void) => {
      clearTimeout(timer);
      el.removeEventListener(ok, onOk);
      el.removeEventListener("error", onErr);
      fn();
    };
    const onOk = () => finish(resolve);
    const onErr = () => finish(() => reject(new Error(el.error?.message ?? "视频无法解码")));
    const timer = setTimeout(() => finish(() => reject(new Error("视频加载超时"))), timeoutMs);
    el.addEventListener(ok, onOk);
    el.addEventListener("error", onErr);
  });
}
