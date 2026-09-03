import {
  catalog,
  EffectEngine,
  type EffectDefinition,
  type ParamValues,
} from "@vgpu-fx/effect-core";
import { RsEffectEngine, type RsEffectMeta } from "./rs-engine.ts";
import { VideoSource } from "./video-source.ts";

/** Structural subset shared by EffectDefinition (GPU) and RsEffectMeta (wasm). */
type EffectInfo = {
  id: string;
  name: string;
  category: string;
  description: string;
  params: readonly {
    key: string;
    label: string;
    type: string;
    min: number;
    max: number;
    step: number;
    default: number;
  }[];
};

type Backend = "webgpu" | "rs";

interface PreviewBackend {
  readonly kind: Backend;
  readonly catalog: readonly EffectInfo[];
  defaults(id: string): ParamValues;
  renderTo(canvas: HTMLCanvasElement, opts: {
    effect: string;
    params?: ParamValues;
    time?: number;
    videoTime?: number;
    videoDuration?: number;
    frame: { source: HTMLVideoElement };
  }): Promise<void> | void;
  dispose(): void;
}

class GpuBackend implements PreviewBackend {
  readonly kind = "webgpu" as const;
  constructor(readonly engine: EffectEngine, readonly catalog: readonly EffectInfo[]) {}
  defaults(id: string): ParamValues {
    return this.engine.defaults(id);
  }
  renderTo(canvas: HTMLCanvasElement, opts: Parameters<PreviewBackend["renderTo"]>[1]): Promise<void> {
    return this.engine.renderTo(canvas, opts);
  }
  dispose(): void {
    this.engine.dispose();
  }
}

class RsBackend implements PreviewBackend {
  readonly kind = "rs" as const;
  constructor(readonly engine: RsEffectEngine, readonly catalog: readonly EffectInfo[]) {}
  defaults(id: string): ParamValues {
    return this.engine.defaults(id);
  }
  renderTo(canvas: HTMLCanvasElement, opts: Parameters<PreviewBackend["renderTo"]>[1]): Promise<void> {
    return this.engine.renderTo(canvas, opts);
  }
  dispose(): void {
    this.engine.dispose();
  }
}

export async function startApp(): Promise<() => void> {
  const gpuCanvas = required("#preview", HTMLCanvasElement);
  const cpuCanvas = required("#preview-cpu", HTMLCanvasElement);
  const backendSelect = required("#backend-select", HTMLSelectElement);
  const list = required("#effect-list", HTMLElement);
  const paramList = required("#param-list", HTMLElement);
  const paramTitle = required("#param-title", HTMLElement);
  const paramDesc = required("#param-desc", HTMLElement);
  const status = required("#status", HTMLElement);
  const fps = required("#fps", HTMLElement);
  const meta = required("#video-meta", HTMLElement);
  const input = required("#video-input", HTMLInputElement);
  const playBtn = required("#play-btn", HTMLButtonElement);
  const sampleBtn = required("#sample-btn", HTMLButtonElement);

  const video = new VideoSource();

  const backends = new Map<Backend, PreviewBackend>();
  try {
    const gpu = await EffectEngine.create({
      onError: (error) => {
        status.textContent = error.message;
      },
    });
    backends.set("webgpu", new GpuBackend(gpu, catalog));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    status.textContent = `WebGPU 启动失败（${message}），回退 Rust CPU 后端`;
    backendSelect.value = "rs";
  }
  try {
    const rs = await RsEffectEngine.create();
    backends.set("rs", new RsBackend(rs, rs.catalog as unknown as EffectInfo[]));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    status.textContent = `wasm 引擎加载失败：${message}（先跑 npm run build:effect-rs:wasm）`;
  }
  if (backends.size === 0) throw new Error("没有可用渲染后端");

  let backend: Backend =
    (backendSelect.value === "rs" && backends.has("rs")) || !backends.has("webgpu") ? "rs" : "webgpu";
  backendSelect.value = backend;
  backendSelect.disabled = backends.size < 2;

  const engine = (): PreviewBackend => backends.get(backend)!;
  const showCanvas = (kind: Backend): void => {
    gpuCanvas.style.display = kind === "webgpu" ? "block" : "none";
    cpuCanvas.style.display = kind === "rs" ? "block" : "none";
  };
  showCanvas(backend);

  let effectId = engine().catalog[0]?.id ?? "none";
  let params: ParamValues = engine().defaults(effectId);
  let drawing = false;
  let queued = false;
  let fpsFrames = 0;
  let fpsStamp = performance.now();

  const draw = async () => {
    if (drawing) {
      queued = true;
      return;
    }
    if (!video.ready) return;
    drawing = true;
    try {
      await engine().renderTo(backend === "webgpu" ? gpuCanvas : cpuCanvas, {
        effect: effectId,
        params,
        time: video.currentTime,
        videoTime: video.currentTime,
        videoDuration: video.duration,
        frame: { source: video.el },
      });
      fpsFrames += 1;
      const now = performance.now();
      const elapsed = now - fpsStamp;
      if (elapsed >= 500) {
        fps.textContent = `${Math.round((fpsFrames * 1000) / elapsed)} fps`;
        fpsFrames = 0;
        fpsStamp = now;
      }
    } catch (err) {
      status.textContent = err instanceof Error ? err.message : String(err);
    } finally {
      drawing = false;
      if (queued) {
        queued = false;
        void draw();
      }
    }
  };

  const select = (id: string) => {
    effectId = id;
    params = engine().defaults(id);
    const def = engine().catalog.find((item) => item.id === id);
    if (!def) return;
    renderList(list, engine().catalog, def.id, select);
    renderParams(paramList, paramTitle, paramDesc, def, params, (key, value) => {
      params = { ...params, [key]: value };
      void draw();
    });
    status.textContent = `特效：${def.name} · ${backend === "webgpu" ? "WebGPU" : "Rust CPU (wasm)"}`;
    void draw();
  };

  select(effectId);
  status.textContent =
    backend === "webgpu" ? "WebGPU 就绪，选择视频后开始预览" : "Rust CPU (wasm) 就绪，选择视频后开始预览";
  new ResizeObserver(() => {
    void draw();
  }).observe(gpuCanvas);

  backendSelect.addEventListener("change", () => {
    const next = backendSelect.value as Backend;
    if (!backends.has(next)) {
      backendSelect.value = backend;
      return;
    }
    backend = next;
    showCanvas(backend);
    const first = engine().catalog[0]?.id ?? "none";
    select(first);
    status.textContent = `后端：${backend === "webgpu" ? "WebGPU" : "Rust CPU (wasm)"}（${engine().catalog.length} 个特效）`;
  });

  let attachGen = 0;
  const attachFile = async (file: File) => {
    const gen = ++attachGen;
    try {
      await video.load(file);
      if (gen !== attachGen) return;
      meta.textContent = `${file.name} · ${video.size[0]}×${video.size[1]}`;
      playBtn.disabled = false;
      playBtn.textContent = "播放";
      status.textContent = "视频已加载，点播放实时预览";
      await draw();
    } catch (err) {
      if (gen !== attachGen) return;
      playBtn.disabled = true;
      playBtn.textContent = "播放";
      status.textContent = err instanceof Error ? err.message : String(err);
    }
  };

  input.addEventListener("change", async () => {
    const file = input.files?.[0];
    if (file) await attachFile(file);
  });

  sampleBtn.addEventListener("click", async () => {
    try {
      const response = await fetch("/sample.mp4");
      if (!response.ok) throw new Error(`示例视频加载失败 (${response.status})`);
      const blob = await response.blob();
      await attachFile(new File([blob], "sample.mp4", { type: "video/mp4" }));
    } catch (err) {
      status.textContent = err instanceof Error ? err.message : String(err);
    }
  });

  playBtn.addEventListener("click", () => {
    if (video.el.paused) {
      video.play();
      playBtn.textContent = "暂停";
      video.onVideoFrame(() => {
        void draw();
      });
      const fallback = () => {
        if (video.el.paused) return;
        if (video.takeFrame()) void draw();
        requestAnimationFrame(fallback);
      };
      if (typeof video.el.requestVideoFrameCallback !== "function") requestAnimationFrame(fallback);
    } else {
      video.pause();
      playBtn.textContent = "播放";
      void draw();
    }
  });

  return () => {
    video.dispose();
    for (const b of backends.values()) b.dispose();
  };
}

function renderList(
  root: HTMLElement,
  effects: readonly EffectInfo[],
  activeId: string,
  onPick: (id: string) => void,
): void {
  root.replaceChildren();
  for (const effect of effects) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = effect.id === activeId ? "effect-item active" : "effect-item";
    btn.innerHTML = `<span class="name">${effect.name}</span><span class="cat">${effect.category}</span>`;
    btn.addEventListener("click", () => onPick(effect.id));
    root.append(btn);
  }
}

function renderParams(
  root: HTMLElement,
  title: HTMLElement,
  desc: HTMLElement,
  effect: EffectInfo,
  values: ParamValues,
  onChange: (key: string, value: number) => void,
): void {
  title.textContent = effect.name;
  desc.textContent = effect.description;
  root.replaceChildren();
  if (effect.params.length === 0) {
    const empty = document.createElement("p");
    empty.className = "desc";
    empty.textContent = "这个特效没有可调参数。";
    root.append(empty);
    return;
  }
  for (const param of effect.params) {
    const row = document.createElement("label");
    row.className = "param";
    const value = values[param.key] ?? param.default;
    row.innerHTML = `
      <span class="param-label">${param.label}</span>
      <input type="range" min="${param.min}" max="${param.max}" step="${param.step}" value="${value}" />
      <span class="param-value">${formatValue(value)}</span>
    `;
    const slider = row.querySelector("input")!;
    const readout = row.querySelector(".param-value")!;
    slider.addEventListener("input", () => {
      const next = Number(slider.value);
      readout.textContent = formatValue(next);
      onChange(param.key, next);
    });
    root.append(row);
  }
}

function formatValue(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

function required<T extends Element>(selector: string, ctor: new () => T): T {
  const el = document.querySelector(selector);
  if (!(el instanceof ctor)) throw new Error(`Missing ${selector}`);
  return el;
}

// keep the effect-core import referenced for the GPU catalog type-check
export type { EffectDefinition, ParamValues };
