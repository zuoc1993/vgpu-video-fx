import {
  catalog,
  EffectEngine,
  type EffectDefinition,
  type ParamValues,
} from "@vgpu-fx/effect-core";
import { VideoSource } from "./video-source.ts";

export async function startApp(): Promise<() => void> {
  const canvas = required("#preview", HTMLCanvasElement);
  const list = required("#effect-list", HTMLElement);
  const paramList = required("#param-list", HTMLElement);
  const paramTitle = required("#param-title", HTMLElement);
  const paramDesc = required("#param-desc", HTMLElement);
  const status = required("#status", HTMLElement);
  const meta = required("#video-meta", HTMLElement);
  const input = required("#video-input", HTMLInputElement);
  const playBtn = required("#play-btn", HTMLButtonElement);
  const sampleBtn = required("#sample-btn", HTMLButtonElement);

  const video = new VideoSource();
  let engine: EffectEngine;
  try {
    engine = await EffectEngine.create({
      onError: (error) => {
        status.textContent = error.message;
      },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    status.textContent = `启动失败：${message}`;
    throw err;
  }

  let effectId = catalog[0]?.id ?? "none";
  let params: ParamValues = engine.defaults(effectId);
  let drawing = false;
  let queued = false;

  const draw = async () => {
    if (drawing) {
      queued = true;
      return;
    }
    if (!video.ready) return;
    drawing = true;
    try {
      await engine.renderTo(canvas, {
        effect: effectId,
        params,
        time: video.currentTime,
        videoTime: video.currentTime,
        videoDuration: video.duration,
        frame: { source: video.el },
      });
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
    params = engine.defaults(id);
    const def = engine.getEffect(id);
    renderList(list, catalog, def.id, select);
    renderParams(paramList, paramTitle, paramDesc, def, params, (key, value) => {
      params = { ...params, [key]: value };
      void draw();
    });
    status.textContent = `特效：${def.name}`;
    void draw();
  };

  select(effectId);
  status.textContent = "WebGPU 就绪，选择视频后开始预览";
  new ResizeObserver(() => {
    void draw();
  }).observe(canvas);

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
    engine.dispose();
  };
}

function renderList(
  root: HTMLElement,
  effects: readonly EffectDefinition[],
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
  effect: EffectDefinition,
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
