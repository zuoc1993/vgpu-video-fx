# 架构

本仓库是一套 **WebGPU 视频特效**：同一份 WGSL catalog，两条出路——浏览器实时预览，以及 BMF 离线出片。出片不在 Python 里画，而是把 RGBA 帧发给 Node sidecar，由 Dawn 跑和预览同一套 shader。

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
                                                     │ 协议
                                           bmf-demo (Python)
                                           解码 → RGBA → 编码
```

两条链路只在「像素从哪来、画完去哪」上不同，特效 id / 参数 / 时钟语义共用。

## 包与目录

| 路径 | 职责 |
|---|---|
| `packages/effect-core` | 特效定义、WGSL、`EffectEngine` |
| `packages/web` | 浏览器预览 UI |
| `packages/sidecar` | Node GPU worker，听 Unix socket |
| `bmf-demo/` | BMF 图：解码 → `VgpuFx` → 编码 |
| `public/sample.mp4` | 示例片（Vite `publicDir` 也指这里） |
| `scripts/` | doctor / shader / smoke / frames / video-wait |

npm workspaces：`@vgpu-fx/effect-core`、`@vgpu-fx/web`、`@vgpu-fx/sidecar`。

## 特效核心

### Catalog

每个特效是一个 `EffectDefinition`（`packages/effect-core/src/effects/types.ts`）：

- `id` / `name` / `category` / `description`
- `params`：目前只有 `range`，给 Web 滑条和默认值
- `shader`：WGSL 模块（`import "...wgsl"`）
- `uniforms(values, ctx)`：把滑条值和帧上下文打成 shader `params`

注册表：`packages/effect-core/src/effects/registry.ts`。现有 id：

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

`zoom-out` 复用 `zoom-in/effect.wgsl`，只改默认起止缩放。共用几何在 `effects/shared/video.wgsl`（`containUv`、`sampleVideo`、缓动、方向模糊）。

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

## BMF 出片

`bmf-demo/vgpu_fx.py` 的 `VgpuFx` 是 BMF `Module`：

1. 解码帧 `reformat` 成 RGB24，补 alpha=255
2. 攒到 `batch`（默认 15，`VGPU_FX_BATCH`）
3. `VgpuFxClient.render` → sidecar
4. 去掉 alpha，`VideoFrame` 写回，保留 pts
5. 图末 `encode(None, ...)`：示例片没有音轨，空音频 pad 会 EOF 编码器

挂模块必须用官方 API：

```python
video.py_module("vgpu_fx", option, HERE, "vgpu_fx.VgpuFx")
```

不要把路径塞进早期的 `module(...)` / `pre_module`（会变成 `str has no attribute uid`）。

`run_demo.py` 对 8 个 id 各出 `bmf-demo/output/{effect}.mp4`，并打印 sidecar fps。

## 性能模型

| 路径 | 像素怎么走 | 观感 |
|---|---|---|
| Web `renderTo` | GPU 内：video → texture → canvas | 实时 |
| Sidecar | CPU RGBA 上 GPU，再 `read()` 回 CPU，再经 socket | 1080p 大约数 fps |

出片慢主要在 **每帧 上传 + 读回 + 进程间拷贝**，不在 shader（`none` 和 `glitch` 帧率几乎一样）。batch 只减少往返次数，不减少字节数。

vgpu 的 `frame()` 多 pass 是「一帧里一次 submit」，不是「N 个视频帧一次上传」。

## 依赖边界

- **Web**：浏览器 WebGPU；无 sidecar
- **Sidecar**：Dawn（`vgpu/node`）；改 `engine` / WGSL 后重启
- **BMF**：Python **3.12**（`requires-python <3.13`，BabitMF 无 3.14 wheel）、FFmpeg **4**（`libavcodec.58`）。macOS：`brew install ffmpeg@4`（keg-only；BabitMF rpath 会找 `/opt/homebrew/opt/ffmpeg@4/lib`）
- 示例片无音频
