// Rust CPU (wasm) preview backend: wraps effect-rs/pkg (wasm-pack output).
//
// The wasm build is single-threaded (no COOP/COEP) and the heavy effects are
// gather/bandwidth-bound, so preview renders at a capped resolution and the
// 2D canvas scales the result onto the display canvas. Measured render cost
// (simd128 build, single thread, 2160x3840 sample):
//   2160x3840 glitch 698ms  glow 1193ms  <- unusable for preview
//   1080x1920 glitch 173ms  glow  295ms
//   720x1280  glitch  77ms  glow  131ms
//   540x960   glitch  43ms  glow   73ms
//   640x1138  glitch  61ms  glow  102ms  <- MAX_RENDER_W target
// Browser pipeline (headless Chrome, dpr 2): capture ~4-7ms + render ~27ms at
// 720 wide sat exactly on the 30fps rVFC cadence boundary and dropped to
// ~15fps on any jitter; 640 wide buys a comfortable margin.
// The GPU (WebGPU) backend is unaffected and renders at full resolution.

import init, {
  catalog as wasmCatalog,
  render as wasmRender,
} from "../../../effect-rs/pkg/effect_rs.js";

export type RsParamDef = {
  key: string;
  label: string;
  type: "range";
  min: number;
  max: number;
  step: number;
  default: number;
};

export type RsEffectMeta = {
  id: string;
  name: string;
  category: string;
  description: string;
  params: RsParamDef[];
};

export type ParamValues = Record<string, number>;

/** Max render width for the wasm backend; see the note at the top. */
const MAX_RENDER_W = 640;

let loadPromise: Promise<void> | null = null;
function load(): Promise<void> {
  loadPromise ??= init().then(() => undefined);
  return loadPromise;
}

/** Preview backend compatible with effect-core's EffectEngine surface. */
export class RsEffectEngine {
  private scratch: HTMLCanvasElement | null = null;
  private renderCanvas: HTMLCanvasElement | null = null;

  private constructor(readonly catalog: RsEffectMeta[]) {}

  static async create(): Promise<RsEffectEngine> {
    await load();
    const catalog = (await wasmCatalog()) as unknown as RsEffectMeta[];
    return new RsEffectEngine(catalog);
  }

  defaults(id: string): ParamValues {
    // Derive from catalog metadata (clean f64 values); the wasm defaults()
    // export round-trips f32 and shows rounding noise in the UI.
    const def = this.getEffect(id);
    return Object.fromEntries(def.params.map((p) => [p.key, p.default]));
  }

  getEffect(id: string): RsEffectMeta {
    const def = this.catalog.find((item) => item.id === id);
    if (!def) throw new Error(`Unknown effect: ${id}`);
    return def;
  }

  /**
   * Draw a video frame through the wasm engine onto a 2D canvas.
   * Pixels are captured at a capped render resolution (video aspect) and the
   * result is scaled onto the canvas backing store with letterboxing, so the
   * CPU cost stays independent of the window size.
   */
  async renderTo(canvas: HTMLCanvasElement, opts: {
    effect: string;
    params?: ParamValues;
    time?: number;
    videoTime?: number;
    videoDuration?: number;
    frame: { source: HTMLVideoElement };
  }): Promise<void> {
    const timing = (globalThis as { __RS_TIMING?: boolean }).__RS_TIMING === true;
    const marks: number[] = [];
    const mark = () => marks.push(performance.now());
    if (timing) mark();
    const video = opts.frame.source;
    const vw = video.videoWidth || 1;
    const vh = video.videoHeight || 1;
    let rw = vw;
    let rh = vh;
    if (rw > MAX_RENDER_W) {
      rh = Math.max(1, Math.round((rh * MAX_RENDER_W) / rw));
      rw = MAX_RENDER_W;
    }

    if (!this.scratch) this.scratch = document.createElement("canvas");
    const scratch = this.scratch;
    if (scratch.width !== rw || scratch.height !== rh) {
      scratch.width = rw;
      scratch.height = rh;
    }
    const sctx = scratch.getContext("2d", { willReadFrequently: true });
    if (!sctx) throw new Error("2D context unavailable");
    // Downscale the video to the render size in one optimized step; the
    // plain drawImage path is the fallback for older browsers.
    let frame: ImageBitmap | HTMLVideoElement = video;
    if (typeof createImageBitmap === "function") {
      try {
        frame = await createImageBitmap(video, {
          resizeWidth: rw,
          resizeHeight: rh,
          resizeQuality: "medium",
        });
      } catch {
        frame = video;
      }
    }
    sctx.drawImage(frame, 0, 0, rw, rh);
    if (frame !== video) (frame as ImageBitmap).close();
    if (timing) mark();
    const img = sctx.getImageData(0, 0, rw, rh);
    if (timing) mark();

    // The CPU backend renders at the capped preview resolution already, so
    // the display canvas runs at CSS resolution (dpr 1). The browser
    // compositor handles the Retina upscale for free; using dpr 2 here made
    // every frame pay a ~2000x1124 software fillRect + 3x smoothing drawImage
    // and dropped glitch to ~15fps on Retina displays.
    const dpr = 1;
    const cw = Math.max(1, Math.round(canvas.clientWidth * dpr));
    const ch = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (canvas.width !== cw || canvas.height !== ch) {
      canvas.width = cw;
      canvas.height = ch;
    }

    const time = opts.time ?? 0;
    const srcBytes = new Uint8Array(img.data.buffer, img.data.byteOffset, img.data.byteLength);
    const out = wasmRender(
      opts.effect,
      opts.params ?? null,
      time,
      0,
      opts.videoTime ?? time,
      opts.videoDuration ?? 0,
      srcBytes,
      rw,
      rh,
      rw,
      rh,
    );
    if (timing) mark();

    if (!this.renderCanvas) this.renderCanvas = document.createElement("canvas");
    const renderCanvas = this.renderCanvas;
    if (renderCanvas.width !== rw || renderCanvas.height !== rh) {
      renderCanvas.width = rw;
      renderCanvas.height = rh;
    }
    const rctx = renderCanvas.getContext("2d");
    if (!rctx) throw new Error("2D context unavailable");
    const outData = new Uint8ClampedArray(out.byteLength);
    outData.set(out);
    rctx.putImageData(new ImageData(outData, rw, rh), 0, 0);
    if (timing) mark();

    const octx = canvas.getContext("2d");
    if (!octx) throw new Error("2D context unavailable");
    octx.fillStyle = "#000";
    octx.fillRect(0, 0, cw, ch);
    octx.imageSmoothingEnabled = true;
    octx.imageSmoothingQuality = "high";
    const fit = containRect(cw, ch, rw, rh);
    octx.drawImage(renderCanvas, fit.dx, fit.dy, fit.dw, fit.dh);
    if (timing) {
      mark();
      const [t0, t1, t2, t3, t4, t5] = marks;
      console.log(
        "rs-timing",
        JSON.stringify({
          capture: +(t1 - t0).toFixed(1),
          readback: +(t2 - t1).toFixed(1),
          render: +(t3 - t2).toFixed(1),
          put: +(t4 - t3).toFixed(1),
          upscale: +(t5 - t4).toFixed(1),
          total: +(t5 - t0).toFixed(1),
          canvas: [cw, ch],
          renderSize: [rw, rh],
        }),
      );
    }
  }

  dispose(): void {
    this.scratch = null;
    this.renderCanvas = null;
  }
}

/** Fit rw x rh inside cw x ch (letterbox), pixel-aligned. */
function containRect(cw: number, ch: number, rw: number, rh: number): {
  dx: number;
  dy: number;
  dw: number;
  dh: number;
} {
  const scale = Math.min(cw / rw, ch / rh);
  const dw = Math.max(1, Math.round(rw * scale));
  const dh = Math.max(1, Math.round(rh * scale));
  return { dx: Math.round((cw - dw) / 2), dy: Math.round((ch - dh) / 2), dw, dh };
}
