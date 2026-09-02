# 开发者文档

先读 [架构](./architecture.md) 和 [使用](./usage.md)。这里只写怎么改代码、加特效、以及不能踩的坑。

## 仓库习惯

- npm workspaces，源码 TypeScript 直接给 Vite / sidecar 的 loader 用，不先编一摊 dist。
- 特效 **id、时钟名、已有 WGSL 公式** 是契约：Web、sidecar、`bmf-demo/run_demo.py` 的 `EFFECTS` 必须对得上。
- 不要「顺手」改已有 catalog 的 shader / 默认参数，除非任务就是改观感。
- 最短能跑的改动优先。非平凡逻辑留一个最小自检（现有 `scripts/` 或补一条 smoke）。

官方测试：

```sh
npm test
```

等于：`vgpu doctor` → `check:shaders` → `smoke` → `smoke:sidecar` → `check:frames` → `check:video-wait` → `tsc`。

单跑：

```sh
npm run check:shaders    # nvp vgpu check 每个 .wgsl
npm run smoke            # Node Dawn 上 32×32 过一遍 catalog
npm run smoke:sidecar    # 拉起临时 sidecar + 协议
npm run typecheck
```

改 UI 时在 http://127.0.0.1:5173/ 用示例片点一遍播放、切特效、拖滑条。改出片时重启 sidecar 再 `uv run run_demo.py`。

## 加一个特效

1. 建目录 `packages/effect-core/src/effects/<id>/`
   - `effect.wgsl`：全屏 fragment（vgpu 会补 triangle + `@location(0) uv`）
   - `index.ts`：`EffectDefinition`
2. 在 `registry.ts` 的 `catalog` **追加**（顺序即 Web 列表顺序）
3. 能复用的纯函数放 `effects/shared/video.wgsl`，用 `import { ... } from "..."`
4. `scripts/smoke.mjs` 的 `cases` 补上该 id 的一组 params
5. `bmf-demo/run_demo.py` 的 `EFFECTS` 同步（要出片的话）

`index.ts` 骨架：

```ts
import type { EffectDefinition } from "../types.ts";
import shader from "./effect.wgsl";

export const fooEffect: EffectDefinition = {
  id: "foo",
  name: "Foo",
  category: "…",
  description: "…",
  params: [
    { key: "intensity", label: "强度", type: "range", min: 0, max: 1, step: 0.01, default: 0.5 },
  ],
  shader,
  uniforms(values, ctx) {
    return {
      params: {
        time: ctx.time,
        intensity: values.intensity,
        resolution: ctx.resolution,
        videoSize: ctx.videoSize,
      },
    };
  },
};
```

WGSL 里 `struct Params` 的字段要和 `uniforms` 对得上（含 `resolution` / `videoSize` 这类 ctx）。采样视频用 `containUv` + `sampleVideo`，越界返回黑，和现有特效一致。

`uv` 是**顶原点**（和 WebGPU 纹理、`target.read()` 一样），不要按 Shadertoy 再翻一次 Y，除非你在移植一份底原点 shader。

验证：

```sh
npx vgpu check packages/effect-core/src/effects/foo/effect.wgsl --require-validation
npm run smoke
npm run dev   # 列表里应出现 Foo
```

## 时钟和参数

- **`time`**：动画。预览 = 播放时间；sidecar = 该帧 pts。
- **`videoTime`**：时间轴。Web/sidecar 目前都等于上面那个时间。zoom 在 `videoDuration > 0` 时用它做 0→1 进度。
- **`deltaTime`**：引擎会算，shader 先别依赖。
- UI 的 `key` 可以和 WGSL 字段不同（zoom：`loop` → `looping`），只在 `uniforms()` 里映射。
- sidecar 请求的 `params` 是扁平 `Record<string, number>`，未知 key 进 `values` 后若 `uniforms` 没用就被丢掉。

不要把时钟改名成 `t` / `pts` 之类，两边调用方已经写死。

## Engine 与 vgpu

- Surface 目标：只在 `frame(gpu, cb)` 里 `pass`。`compile({ colors: [surface.format] })`。
- 读回：`render` / `renderBatch` 必须 `await dest.read()` 且 `await gpu.settled()`。
- 调用方传入的 `gpu`：`ownsGpu === false`，`dispose()` 不关它（sidecar 自己关）。
- **禁止**在一个 `frame()` 里对**同一个** effect 多次 `set` 不同 `time` 再 `pass`：uniform 原地写，GPU 执行时只剩最后一次。
- `renderBatch` 共用一张 src：必须 upload+draw 交错。要真批量上传得 N 张 src 或 atlas，还要 `UniformPool` 才能一个 encoder 里带不同 time。收益有限（见架构「性能模型」）。

Node 里创建 engine：先注册 `packages/sidecar/src/wgsl-loader.mjs`，或像 `scripts/smoke.mjs` 那样 `resolveShader` 后自己拼 catalog。不要在无 loader 的 Node 里 `import "./effect.wgsl"`。

## Sidecar

- 入口必须是 `node src/start.mjs`（register loader），不要直接 `node server.ts`。
- 读 socket 用 `sockReader`（buffer + 一个 `data`）。自己 `readExact` 再 `unshift` 会和 `pauseOnConnect` 死锁。
- 客户端连上后不要先 `pause()`。
- `exclusive`：全局一把 GPU，不要并行 `handle`。
- 协议改字段：同时改 `packages/sidecar/src/protocol.ts` 和 `bmf-demo/vgpu_fx_protocol.py`，并更新 `smoke-sidecar`。
- 像素：RGBA8、紧凑、顶原点、`width*height*4`。BMF 侧 RGB→补 A、回来再剥 A。

## BMF 模块

- 挂载：`video.py_module("vgpu_fx", option, HERE, "vgpu_fx.VgpuFx")`。`HERE` 是包含 `vgpu_fx.py` 的目录。
- `from_numpy` 只收 ndarray：`mp.Frame(mp.from_numpy(rgb), mp.PixelInfo(mp.kPF_RGB24))`。
- 无音频：`encode(None, ...)`。
- 默认 group `bmf`；CI/smoke 可用 `uv run --no-dev --no-default-groups python test_client.py`（不依赖 BabitMF）。
- Python 版本锁在 `bmf-demo/.python-version`（3.12）。

## Web UI

- 列表和滑条完全由 `catalog` + `params` 生成，加特效一般不用改 `app.ts`。
- 新控件类型（非 `range`）要改 `types.ts` 和 `renderParams`。
- `VideoSource`：解码等待逻辑有单测 `scripts/check-video-wait.mjs`，改 `video-wait.ts` 时一起跑。
- Vite 把仓库 `public/` 当静态目录；示例片走 `/sample.mp4`。

## 目录与脚本

```
packages/effect-core/src/
  engine.ts          # 上传 / 画 / 读回
  frames.ts          # FrameIn
  effects/registry.ts
  effects/<id>/{index.ts,effect.wgsl}
  effects/shared/video.wgsl
packages/web/src/{main,app,video-source,video-wait}.ts
packages/sidecar/src/{start.mjs,wgsl-loader.mjs,server.ts,protocol.ts,read.ts}
bmf-demo/{vgpu_fx.py,vgpu_fx_protocol.py,run_demo.py,test_client.py}
scripts/{check-shaders,smoke,smoke-sidecar,check-frames,check-video-wait,e2e-preview}.mjs
```

## 已知限制（改之前先看）

1. 出片路径是 CPU↔GPU 往返，batch / 多 pass 一次 submit **解决不了** 1080p 实时导出。
2. shader 是 `texture_2d`，不是数组，无法一条 draw 吃 N 帧。
3. 调用方选每段时间的 effect id；引擎不做时间轴编排。
4. 预览和出片若要像素级一致：同一 id、同一 params、同一 `time`/`videoTime`；预览画布比例若和视频不同，contain 的黑边会不同。出片输出尺寸 = 输入帧尺寸。

## 建议的下一步（未做）

按需，不是路线图承诺：

- 出片要快：进程内渲染或 CPU 实现简单特效，或结果不读回、直接硬编——见架构性能节。
- 时间轴多特效：在 BMF/Web 按 pts 切 id，不必改 engine。
- 新特效：只加目录 + registry + smoke cases，保持现有 WGSL 不动。
