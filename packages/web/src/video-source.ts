import { isDecoded, needsSeekToStart, waitVideoEvent } from "./video-wait.ts";

const FALLBACK_FPS = 30;

export class VideoSource {
  readonly el = document.createElement("video");
  private objectUrl: string | null = null;
  private usingRvcf = false;
  private needsPresent = false;
  private lastQuantized = -1;
  private chain: Promise<void> = Promise.resolve();

  constructor() {
    this.el.muted = true;
    this.el.loop = true;
    this.el.playsInline = true;
    this.el.preload = "auto";
    this.el.setAttribute("aria-hidden", "true");
    this.el.style.cssText = "position:fixed;width:1px;height:1px;opacity:0;pointer-events:none";
    this.el.addEventListener("loadeddata", () => {
      this.needsPresent = true;
    });
    document.body.append(this.el);
  }

  get ready(): boolean {
    return isDecoded(this.el.readyState, this.el.videoWidth);
  }

  get size(): readonly [number, number] {
    return [this.el.videoWidth || 1, this.el.videoHeight || 1];
  }

  get currentTime(): number {
    return this.el.currentTime;
  }

  get duration(): number {
    return Number.isFinite(this.el.duration) ? this.el.duration : 0;
  }

  async load(file: File): Promise<void> {
    const run = this.chain.then(() => this.loadNow(file), () => this.loadNow(file));
    this.chain = run.then(() => undefined, () => undefined);
    return run;
  }

  play(): void {
    void this.el.play();
  }

  pause(): void {
    this.el.pause();
    this.needsPresent = true;
  }

  /** True when the preview should sample a new video frame. */
  takeFrame(): boolean {
    if (!this.ready) return false;
    if (this.needsPresent) {
      this.needsPresent = false;
      return true;
    }
    if (this.usingRvcf) return false;
    if (this.el.paused) return false;
    const next = Math.floor(this.el.currentTime * FALLBACK_FPS);
    if (next === this.lastQuantized) return false;
    this.lastQuantized = next;
    return true;
  }

  onVideoFrame(cb: () => void): void {
    if (typeof this.el.requestVideoFrameCallback !== "function") return;
    const tick = () => {
      this.needsPresent = true;
      cb();
      if (!this.el.paused) this.el.requestVideoFrameCallback(tick);
      else this.usingRvcf = false;
    };
    if (!this.usingRvcf) {
      this.usingRvcf = true;
      this.el.requestVideoFrameCallback(tick);
    }
  }

  dispose(): void {
    this.el.pause();
    const prev = this.objectUrl;
    this.el.removeAttribute("src");
    this.objectUrl = null;
    if (prev) URL.revokeObjectURL(prev);
    this.el.remove();
  }

  private async loadNow(file: File): Promise<void> {
    const prevUrl = this.objectUrl;
    const nextUrl = URL.createObjectURL(file);
    this.objectUrl = nextUrl;
    this.el.src = nextUrl;
    if (prevUrl) URL.revokeObjectURL(prevUrl);
    this.lastQuantized = -1;
    this.needsPresent = true;
    const ready = waitVideoEvent(this.el, "loadeddata");
    void this.el.play().catch(() => undefined);
    await ready;
    this.el.pause();
    if (needsSeekToStart(this.el.currentTime)) {
      const seeked = waitVideoEvent(this.el, "seeked");
      this.el.currentTime = 0;
      await seeked;
    }
    if (!this.ready) throw new Error("视频无法解码");
    this.needsPresent = true;
  }
}
