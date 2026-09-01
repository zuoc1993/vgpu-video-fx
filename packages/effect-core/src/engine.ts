import {
  effect,
  frame,
  init,
  sampler,
  surface,
  target,
  type Effect,
  type Gpu,
  type Surface,
  type Target,
} from "vgpu";
import type { Texture } from "vgpu/core";
import { defaultsFrom, type EffectDefinition, type ParamValues } from "./effects/types.ts";
import { frameSize, frameTime, isPixelBuffer, type FrameIn, type PixelBuffer } from "./frames.ts";

export type RenderOptions = {
  effect: string;
  params?: ParamValues;
  time?: number;
  deltaTime?: number;
  videoTime?: number;
  videoDuration?: number;
  frame: FrameIn;
};

export type BatchOptions = {
  effect: string;
  params?: ParamValues;
  videoDuration?: number;
  frames: readonly FrameIn[];
};

export type CreateOptions = {
  /** Pass a live Gpu (e.g. from `vgpu/node`) to skip `init()`. */
  gpu?: Gpu;
  catalog?: readonly EffectDefinition[];
  onError?: (error: Error) => void;
};

export class EffectEngine {
  readonly gpu: Gpu;
  readonly catalog: readonly EffectDefinition[];
  private readonly samp: GPUSampler;
  private readonly instances: Map<string, Effect>;
  private readonly ownsGpu: boolean;

  private constructor(
    gpu: Gpu,
    catalog: readonly EffectDefinition[],
    samp: GPUSampler,
    instances: Map<string, Effect>,
    ownsGpu: boolean,
  ) {
    this.gpu = gpu;
    this.catalog = catalog;
    this.samp = samp;
    this.instances = instances;
    this.ownsGpu = ownsGpu;
  }

  private srcTex: Texture | null = null;
  private out: Target | null = null;
  private placeholder: Texture | null = null;
  private canvasSurface: Surface | null = null;
  private compiled = new Set<string>();
  private retiring: Texture[] = [];

  static async create(opts: CreateOptions = {}): Promise<EffectEngine> {
    const ownsGpu = !opts.gpu;
    const gpu = opts.gpu ?? (await init());
    if (opts.onError) {
      gpu.onError((err) => opts.onError?.(err instanceof Error ? err : new Error(String(err))));
    }
    const list = opts.catalog ?? (await import("./effects/registry.ts")).catalog;
    const samp = sampler(gpu, { minFilter: "linear", magFilter: "linear" });
    const placeholder = gpu.device.createTexture({
      label: "effect-placeholder",
      size: [4, 4],
      format: "rgba8unorm",
      usage: ["copy_dst", "texture_binding"],
    });
    gpu.gpu.queue.writeTexture(
      { texture: placeholder.gpu },
      new Uint8Array(4 * 4 * 4),
      { bytesPerRow: 16 },
      { width: 4, height: 4 },
    );

    const instances = new Map<string, Effect>();
    for (const def of list) {
      const fx = effect(gpu, def.shader, {
        label: def.id,
        set: {
          src: placeholder,
          samp,
          params: def.uniforms(defaultsFrom(def.params), {
            time: 0,
            deltaTime: 0,
            videoTime: 0,
            videoDuration: 0,
            resolution: [4, 4],
            texel: [1 / 4, 1 / 4],
            videoSize: [4, 4],
          }).params,
        },
      });
      instances.set(def.id, fx);
    }

    const engine = new EffectEngine(gpu, list, samp, instances, ownsGpu);
    engine.placeholder = placeholder;
    await engine.compile({ colors: ["rgba8unorm"] });
    return engine;
  }

  getEffect(id: string): EffectDefinition {
    const def = this.catalog.find((item) => item.id === id);
    if (!def) throw new Error(`Unknown effect: ${id}`);
    return def;
  }

  defaults(id: string): ParamValues {
    return defaultsFrom(this.getEffect(id).params);
  }

  /** Draw onto a canvas. Output size follows the surface; input size is the video. */
  async renderTo(canvas: HTMLCanvasElement, opts: RenderOptions): Promise<void> {
    this.bindCanvas(canvas);
    const surface = this.canvasSurface!;
    // Surface itself cannot be compiled/drawn outside frame(gpu).
    await this.compile({ colors: [surface.format] });
    const uploaded = this.upload(opts.frame);
    this.draw(opts, uploaded, surface);
  }

  /** Apply an effect and read RGBA8 back. Output size matches the input frame. */
  async render(opts: RenderOptions): Promise<PixelBuffer> {
    const uploaded = this.upload(opts.frame);
    const [width, height] = uploaded.size;
    const dest = this.ensureOut(width, height);
    await this.compile({ colors: [dest.format] });
    this.draw(opts, uploaded, dest);
    const data = await dest.read();
    await this.gpu.settled();
    return {
      width,
      height,
      data,
      time: opts.time ?? uploaded.time,
    };
  }

  /** Same as `render` over many frames, one Gpu, no re-init. */
  async renderBatch(opts: BatchOptions): Promise<PixelBuffer[]> {
    const out: PixelBuffer[] = [];
    for (const item of opts.frames) {
      out.push(await this.render({
        effect: opts.effect,
        params: opts.params,
        time: frameTime(item),
        videoDuration: opts.videoDuration,
        frame: item,
      }));
    }
    return out;
  }

  dispose(): void {
    this.canvasSurface?.dispose();
    this.canvasSurface = null;
    for (const texture of this.retiring) texture.destroy();
    this.retiring = [];
    this.srcTex?.destroy();
    this.srcTex = null;
    this.placeholder?.destroy();
    this.placeholder = null;
    if (this.out && "destroy" in this.out) (this.out as { destroy: () => void }).destroy();
    this.out = null;
    if (this.ownsGpu) this.gpu.dispose();
  }

  private draw(opts: RenderOptions, uploaded: { size: readonly [number, number]; time?: number }, dest: Surface | Target): void {
    const def = this.getEffect(opts.effect);
    const fx = this.instances.get(def.id);
    if (!fx || !this.srcTex) throw new Error(`effect not ready: ${def.id}`);
    const time = opts.time ?? uploaded.time ?? 0;
    const values = { ...defaultsFrom(def.params), ...opts.params };
    fx.set({
      src: this.srcTex,
      samp: this.samp,
      params: def.uniforms(values, {
        time,
        deltaTime: opts.deltaTime ?? 0,
        videoTime: opts.videoTime ?? time,
        videoDuration: opts.videoDuration ?? 0,
        resolution: dest.size,
        texel: dest.texelSize,
        videoSize: uploaded.size,
      }).params,
    });
    frame(this.gpu, (pass) => {
      pass.pass(dest, fx);
    });
  }

  private upload(input: FrameIn): { size: readonly [number, number]; time?: number } {
    const [width, height] = frameSize(input);
    if (width < 1 || height < 1) throw new Error("invalid frame size");
    const tex = this.ensureSrc(width, height);
    if (isPixelBuffer(input)) {
      if (input.data.byteLength < width * height * 4) throw new Error("RGBA buffer too small");
      this.gpu.gpu.queue.writeTexture(
        { texture: tex.gpu },
        input.data as GPUAllowSharedBufferSource,
        { bytesPerRow: width * 4 },
        { width, height },
      );
    } else {
      this.gpu.gpu.queue.copyExternalImageToTexture(
        { source: input.source },
        { texture: tex.gpu },
        { width, height },
      );
    }
    return { size: [width, height], time: frameTime(input) };
  }

  private ensureSrc(width: number, height: number): Texture {
    if (this.srcTex && this.srcTex.size[0] === width && this.srcTex.size[1] === height) return this.srcTex;
    if (this.srcTex) this.retire(this.srcTex);
    this.srcTex = this.gpu.device.createTexture({
      label: "effect-src",
      size: [width, height],
      format: "rgba8unorm",
      usage: ["copy_dst", "texture_binding", "render_attachment"],
    });
    return this.srcTex;
  }

  private ensureOut(width: number, height: number): Target {
    if (!this.out) {
      this.out = target(this.gpu, { size: [width, height], format: "rgba8unorm" });
      return this.out;
    }
    if (this.out.size[0] !== width || this.out.size[1] !== height) this.out.resize([width, height]);
    return this.out;
  }

  private bindCanvas(canvas: HTMLCanvasElement): void {
    if (this.canvasSurface?.canvas === canvas && !this.canvasSurface.disposed) return;
    this.canvasSurface?.dispose();
    this.canvasSurface = surface(this.gpu, canvas, { dpr: [1, 2] });
  }

  private async compile(dest: Target | { colors: readonly GPUTextureFormat[] }): Promise<void> {
    const key = "format" in dest ? dest.format : dest.colors.join(",");
    if (this.compiled.has(key)) return;
    for (const fx of this.instances.values()) await fx.compile(dest);
    this.compiled.add(key);
  }

  private retire(texture: Texture): void {
    this.retiring.push(texture);
    void this.gpu.gpu.queue.onSubmittedWorkDone().then(() => {
      texture.destroy();
      this.retiring = this.retiring.filter((item) => item !== texture);
    });
  }
}
