# 架构

本仓库是一套 **WebGPU 视频特效**：同一份 WGSL catalog（38 个特效），两条预览/出片出路——浏览器实时预览，以及 BMF 离线出片。出片有三个可互换的后端：**wgpu**（Python 进程内 wgpu-py 跑导出产物，推荐）、**socket**（RGBA 帧发给 Node sidecar，Dawn 渲染）、**native**（effect_rs Rust/CPU，仅 5 个移植特效）。设计与验收见 [wgpu-py 后端](./wgpu-py-backend.md) / [验证手册](./wgpu-py-validation.md)。

仓库名 `vgpu-video-fx`。渲染库是 [vgpu](https://vgpu.sh) `^0.3.1`。

## 总览

```
                    ┌─────────────────────────┐
                    │  @vgpu-fx/effect-core   │
                    │  catalog + EffectEngine │
                    └───────────┬─────────────┘
               renderTo(canvas) │  render / renderBatch
           ┌────────────────────┴────────────────────┐
           ▼                                         ▼
   @vgpu-fx/web                              @vgpu-fx/sidecar
   Vite + <video>                            Unix socket + Dawn
   帧留在 GPU，不上屏读回                      上传 → 画 → 读回 CPU
                                                     ▲
   npm run export:effects                            │ socket 协议
           │（拍平 + 反射，产物入库）                  │
           ▼                                         │
   dist-effects/{id}.wgsl + effects.json             │
           │ wgpu-py 进程内渲染（同一份 WGSL，naga）   │
           ▼                                         ▼
   ┌───────────────────────────────────────────────────┐
   │ bmf-demo (Python)：解码 → RGBA → VgpuFx → 编码     │
   │ backend = wgpu（进程内）/ socket（sidecar）/ native │
   └───────────────────────────────────────────────────┘
```

各链路只在「像素从哪来、画完去哪」上不同，特效 id / 参数 / 时钟语义共用；wgpu 后端连 WGSL 字符串本身都与 sidecar 逐字节一致（见「导出产物与 wgpu 后端」节）。

## 包与目录

| 路径 | 职责 |
|---|---|
| `packages/effect-core` | 特效定义、WGSL、`EffectEngine` |
| `packages/effect-core/dist-effects` | 导出产物：38 个拍平 `.wgsl` + `effects.json`（**入库**，wgpu 后端的权威输入） |
| `packages/web` | 浏览器预览 UI |
| `packages/sidecar` | Node GPU worker，听 Unix socket |
| `bmf-demo/` | BMF 图：解码 → `VgpuFx` → 编码；含 `vgpu_fx_gpu.py`（wgpu 渲染器）、`compare_wgpu.py`（Dawn↔wgpu 对照） |
| `effect-rs/` | native 后端：Rust/CPU 移植的 5 个特效（PyO3） |
| `public/sample.mp4` | 示例片（Vite `publicDir` 也指这里） |
| `scripts/` | doctor / shader / smoke / frames / video-wait / `export-effects.mjs`（导出器） |

npm workspaces：`@vgpu-fx/effect-core`、`@vgpu-fx/web`、`@vgpu-fx/sidecar`。

## 特效核心

### Catalog

每个特效是一个 `EffectDefinition`（`packages/effect-core/src/effects/types.ts`）：

- `id` / `name` / `category` / `description`
- `params`：目前只有 `range`，给 Web 滑条和默认值
- `shader`：WGSL 模块（`import "...wgsl"`）
- `uniforms(values, ctx)`：把滑条值和帧上下文打成 shader `params`

注册表：`packages/effect-core/src/effects/registry.ts`。现有 38 个 id：

| id | 名称 | 类别 |
|---|---|---|
| `none` | 原片 | 基础 |
| `handheld-cam` | 摇晃运镜 | 运镜 |
| `camera-shake` | 镜头摇晃 | 运镜 |
| `local-push` | 局部推镜 | 运镜 |
| `glitch` | Glitch | 故障 |
| `screen-shake` | Screen Shake | 冲击 |
| `zoom-in` | Zoom in | 缩放 |
| `zoom-out` | Zoom out | 缩放 |
| `cylinder-wrap` | Cylinder wrap | 3D |
| `pixeliz0r` | Pixeliz0r | 像素 |
| `squigglevision` | Squigglevision | 扭曲 |
| `colorhalftone` | Color halftone | 风格化 |
| `sobel` | Sobel edges | 风格化 |
| `water` | Water | 扭曲 |
| `defish0r` | Defish0r | 扭曲 |
| `vignette` | Vignette | 调整 |
| `heatmap0r` | Heatmap0r | 风格化 |
| `glitch0r` | Glitch0r | 故障 |
| `pixels0rt` | Pixels0rt | 像素 |
| `kaleid0sc0pe` | Kaleid0sc0pe | 风格化 |
| `distort0r` | Distort0r | 扭曲 |
| `rgbsplit0r` | Rgb split0r | 故障 |
| `emboss` | Emboss | 风格化 |
| `posterize` | Posterize | 风格化 |
| `pixs0r` | Pixs0r | 故障 |
| `dither` | Dither | 风格化 |
| `ntsc` | NTSC | 复古 |
| `edgeglow` | Edge glow | 风格化 |
| `scanline0r` | Scanline0r | 复古 |
| `glow` | Glow | 风格化 |
| `crt` | CRT | 复古 |
| `spectral-flare` | Spectral flare | 风格化 |
| `dust-bokeh` | Dust bokeh | 氛围 |
| `spacetime-lens` | Spacetime lens | 扭曲 |
| `retro-quantize` | Retro quantize | 复古 |
| `grade` | Grade | 调整 |
| `light-leak` | Light leak | 氛围 |
| `dissolve` | Dissolve | 转场 |

`zoom-out` 复用 `zoom-in/effect.wgsl`，只改默认起止缩放。共用几何在 `effects/shared/video.wgsl`（`containUv`、`sampleVideo`、缓动、方向模糊）；hash / perlin 噪声等来自 `@vgpu/wgsl-std`（导出器会内联拍平）。

### 时钟

| 字段 | 含义 |
|---|---|
| `time` | 特效动画时钟（秒） |
| `videoTime` | 时间轴 / pts（秒） |
| `deltaTime` | 与上一帧的间隔；**当前没有任何 shader 使用** |
| `videoDuration` | 成片时长；zoom 在 `> 0` 时用 `videoTime` 做缓动 |

Web 与 sidecar 都把 `time` 和 `videoTime` 设成同一套时间（预览用 `video.currentTime`，出片用 pts）。zoom 的 UI 键是 `loop`，写入 shader 的字段是 `looping`。

### EffectEngine

`EffectEngine.create` 申请（或接收）一个 `Gpu`，为 catalog 里每个 id `effect()` 一次，预热 `rgba8unorm` pipeline。

输入 `FrameIn` 两种：

- **PixelBuffer**：紧凑 RGBA8，`writeTexture`
- **ImageSource**：`<video>` / `VideoFrame` / canvas，`copyExternalImageToTexture`

出口三种：

| 方法 | 去向 | 谁用 |
|---|---|---|
| `renderTo(canvas)` | swapchain，不 `read()` | Web |
| `render` | offscreen → `dest.read()` | 单帧读回 |
| `renderBatch` | N 张 dest，再 `Promise.all(read)` | sidecar |

`draw` 每次：`fx.set({ src, samp, params })` + `frame(gpu, p => p.pass(dest, fx))`。Surface 只能在 `frame()` 里画。传入的 `gpu` 不由 engine `dispose`。

`set()` 原地写同一块 uniform。不要把多个不同 `time` 的 `set()+pass` 塞进**同一个** `frame()`，所有 pass 会看到最后一次写入。所以 batch 是「一帧一个 `frame()`」，不是一次 submit 画完 N 帧。

共用一张 `src` 纹理：下一帧 `writeTexture` 会盖掉上一帧，因此必须「上传 → 画」交错，不能先灌完再画。

## Web 预览

`packages/web`：Vite，`wgslVitePlugin` 解析 `.wgsl`。

1. `VideoSource` 藏一个 `<video>`，解码后帧在 GPU
2. `requestVideoFrameCallback`（没有则 rAF 量化）触发 `renderTo`
3. `copyExternalImageToTexture` → 全屏 effect → canvas

不把像素拉回 CPU，所以能实时。右上角 `#fps` 按 500ms 窗口统计完成的 `renderTo`。预览可掉帧（`drawing` 时只记一笔 queued）。

## Sidecar

`packages/sidecar/src/start.mjs` 先 `register(wgsl-loader.mjs)`，再加载 `server.ts`。Node 没有 Vite loader，必须用这个 hook 把 `.wgsl` 收成 `{ version, wgsl }`。

进程启动时 `init()` from `vgpu/node`（Dawn），`EffectEngine.create({ gpu })`，听 `$VGPU_FX_SOCK`（默认 `/tmp/vgpu-fx.sock`）。

- `createServer({ pauseOnConnect: true })`，`sockReader` 里 `resume()` 并只挂一个 `data` 监听。客户端**不要**在 connect 前 `pause()`。
- 请求进 `exclusive` 队列：一把 Gpu，串行 `renderBatch`。

改完 `engine.ts` 或 shader 后要**重启 sidecar**，否则还是旧进程。

## 协议

一帧报文：

```
[u32le headerLen][JSON utf8][RGBA8 像素]
```

请求 JSON：

```json
{
  "id": "1",
  "effect": "glitch",
  "params": { "intensity": 0.7 },
  "width": 1664,
  "height": 1080,
  "count": 15,
  "times": [0.0, 0.033, "..."],
  "videoDuration": 3.63
}
```

- `count === times.length`
- 像素：`count * width * height * 4`，紧凑 RGBA8，顶原点，和 WebGPU `texture` / `target.read()` 一致
- 一批里 effect / params / 分辨率相同

成功：`{ id, ok: true, width, height, count }` + 同样大小的像素。  
失败：`{ id, ok: false, error }`，无 body。

Python：`bmf-demo/vgpu_fx_protocol.py`（`struct.pack("<I", ...)`）。  
Node：`packages/sidecar/src/protocol.ts`。

## 导出产物与 wgpu 后端

`npm run export:effects`（`scripts/export-effects.mjs`）为 wgpu 后端生成权威产物，写入 `packages/effect-core/dist-effects/` 并**入库**（Python 侧运行不依赖 Node；改 shader 后重跑，`git diff` 即评审面）：

- `{id}.wgsl`：vgpu 拍平器（`resolveShader`，和 sidecar 的 node loader 同一代码路径）拍平所有 import，再拼上 vgpu `effect()` 运行时注入的全屏三角形顶点阶段——**逐字节等于 vgpu 喂给 Dawn 的字符串**
- `effects.json`：参数默认值、vgpu 反射的 uniform 布局（字段 offset / 总 size，naga-standard host-shareable 规则）、以及 `(values, ctx) → uniform 字段` 的映射（导出器用哨兵值求值 `uniforms()` 自动判定，遇到不认识的逻辑会**报错而不是猜**）

`bmf-demo/vgpu_fx_gpu.py` 的 `WgpuFxRenderer` 用 [wgpu-py](https://github.com/pygfx/wgpu-py) 在 Python 进程内跑这些产物：Python 不解析 WGSL，按 `effects.json` 打包 uniform 字节。渲染语义刻意与 sidecar 对齐：全屏三角形无顶点缓冲 `draw(3)`、group0 = texture/sampler/uniform、`rgba8unorm` 离屏、clear `[0,0,0,1]`、**逐帧 submit**（uniform 原地写，不合批）、读回 `copy_texture_to_buffer` + 256 对齐去 padding。

一致性基准：sidecar（Dawn/tint→MSL）是参照系，wgpu-py（wgpu/naga→MSL）是同 GPU 的另一条编译链。`bmf-demo/compare_wgpu.py` 对全量 38 特效逐帧比对（需 sidecar 在线）：整数 hash 位级一致，浮点滤波允许 ±1 LSB；判定阈值 mean < 0.05 且 pct>2 < 1%。验收全流程见 [验证手册](./wgpu-py-validation.md)。

## BMF 出片

`bmf-demo/vgpu_fx.py` 的 `VgpuFx` 是 BMF `Module`：

1. 解码帧 `reformat` 成 RGB24，补 alpha=255
2. 攒到 `batch`（默认 15，`VGPU_FX_BATCH`）
3. 按 backend 渲染：`wgpu` → `WgpuFxRenderer.render_batch`（进程内）；`socket` → `VgpuFxClient.render` → sidecar；`native` → `effect_rs.render_batch`（CPU）
4. 去掉 alpha，`VideoFrame` 写回，保留 pts
5. 图末 `encode(None, ...)`：示例片没有音轨，空音频 pad 会 EOF 编码器

后端由 option `backend` 或 `VGPU_FX_BACKEND` 指定，`pick_backend` 按可用性回退（请求的不可用时：wgpu→native→socket，native→wgpu→socket；未指定时 auto：进程内优先，sidecar 兜底）。wgpu 需要已导出 `dist-effects/` 且装好 `wgpu` 依赖组。

挂模块必须用官方 API：

```python
video.py_module("vgpu_fx", option, HERE, "vgpu_fx.VgpuFx")
```

不要把路径塞进早期的 `module(...)` / `pre_module`（会变成 `str has no attribute uid`）。

`run_demo.py` 按 backend 规划特效集合（wgpu/socket → 全量 38 个；native → effect_rs 已移植的 5 个），各出 `bmf-demo/output/{effect}.mp4`，并打印 `vgpu_fx[{backend}]` 的 render fps / cvt 耗时 / wall time。

## 性能模型

| 路径 | 像素怎么走 | 观感 |
|---|---|---|
| Web `renderTo` | GPU 内：video → texture → canvas | 实时 |
| wgpu 进程内 | CPU RGBA 上 GPU，读回 CPU；无 socket、无第二进程 | 1664×1080 实测 render ≈ 250–340 fps，单特效 wall ≈ 2.2s（109 帧） |
| Sidecar | 同上，再叠加 socket 双向拷贝 | 同分辨率 render ≈ 70–85 fps，wall ≈ 3.2s |
| native (effect_rs) | 纯 CPU | 因特效而异（实测 44–524 fps） |

出片慢主要在 **每帧 上传 + 读回**（socket 路径再加进程间拷贝），不在 shader（`none` 和 `glitch` 帧率几乎一样）。batch 只减少往返次数，不减少字节数。wgpu 后端省掉的是 socket 与进程边界，CPU↔GPU 搬运本身仍在。

（以上实测：Apple M3 Max，109 帧 1664×1080；逐特效数据见 [验证手册](./wgpu-py-validation.md) 的报告模板。）

vgpu 的 `frame()` 多 pass 是「一帧里一次 submit」，不是「N 个视频帧一次上传」。

## 依赖边界

- **Web**：浏览器 WebGPU；无 sidecar
- **Sidecar**：Dawn（`vgpu/node`）；改 `engine` / WGSL 后重启
- **wgpu 后端**：wgpu-py ≥ 0.20（`cd bmf-demo && uv sync --group wgpu`），依赖已入库的 `dist-effects/`；无 Node 运行时依赖。wgpu-py 无类型约束，升级后按验证手册重跑验收（0.32 曾漂移读回 API，见开发文档）
- **native 后端**：effect_rs 本地 wheel（`uv pip install effect-rs/target/wheels/*.whl`），仅 5 个特效
- **BMF**：Python **3.12**（`requires-python <3.13`，BabitMF 无 3.14 wheel）、FFmpeg **4**（`libavcodec.58`）。macOS：`brew install ffmpeg@4`（keg-only；BabitMF rpath 会找 `/opt/homebrew/opt/ffmpeg@4/lib`）
- 示例片无音频
