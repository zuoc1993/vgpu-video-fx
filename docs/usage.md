# 使用指南

两条用法：**浏览器预览**（实时）和 **BMF 出片**（解码 → 特效 → 编码）。特效 id 两边相同。出片有三个后端：`wgpu`（进程内 GPU，推荐，无需 sidecar）、`socket`（Node sidecar + Dawn）、`native`（effect_rs CPU，仅 5 个特效）。

## 环境

- Node.js（能跑 Vite 和 `vgpu/node` / Dawn）
- 本机 GPU（预览用浏览器 WebGPU；sidecar 用 Dawn）
- 出片另需：
  - [uv](https://docs.astral.sh/uv/)
  - Python 3.10–3.12（推荐 3.12；不要 3.14）
  - FFmpeg 4（`libavcodec.58`）
  - macOS：`brew install ffmpeg@4`

仓库根目录：

```sh
npm install
```

允许 `@vgpu/adapter-node` / `webgpu` 的 postinstall（`package.json` 里 `allowScripts`）。第一次可跑：

```sh
npx vgpu doctor
```

示例视频：`public/sample.mp4`（2160×3840 竖屏、60fps、约 6.7s、无音轨）。

## 实时预览

```sh
npm run dev
```

打开 http://127.0.0.1:5173/

1. **加载示例** 或 **选择视频**
2. 左侧选特效，右侧拖参数
3. **播放**：按视频帧回调画 canvas；右上角是完成 `renderTo` 的 fps

需要 Chrome / Edge / Safari 等支持 WebGPU 的浏览器。画布跟窗口走，视频按 `contain` 完整显示，多出来的是黑边。

只构建静态页：

```sh
npm run build
npm run preview
```

预览**不需要** sidecar。

## 离线出片

### 选后端

| backend | 依赖 | 特效覆盖 | 什么时候用 |
|---|---|---|---|
| `wgpu`（推荐） | `uv sync --group wgpu` + 已入库的 `dist-effects/` | 全量 39 个 | 默认；不起 sidecar，最快 |
| `socket` | `npm run sidecar`（Dawn） | 全量 39 个 | 需要和浏览器/Dawn 逐像素对齐验证时 |
| `native` | effect_rs 本地 wheel | 已移植的 5 个 | 无 GPU 环境兜底 |

不指定时 `run_demo.py` 自动选：装了 effect_rs 用 `native`，否则 `socket`；模块内 `pick_backend` 还会在请求后端不可用时按 wgpu→native→socket 回退。

### 1a. wgpu 后端（不起 sidecar）

```sh
npm run export:effects        # 产物已入库；只有改过 shader 才需要重跑
cd bmf-demo
uv sync --group wgpu          # 装 wgpu-py（≥0.20）
VGPU_FX_BACKEND=wgpu uv run run_demo.py
```

免 BMF 冒烟（合成帧直接过 GPU）：

```sh
uv run vgpu_fx_gpu.py posterize 4
```

### 1b. socket 后端（先起 sidecar）

```sh
npm run sidecar
```

默认听 `/tmp/vgpu-fx.sock`。看到 `vgpu-fx sidecar listening on ...` 再往下。

换路径：

```sh
VGPU_FX_SOCK=/tmp/my-fx.sock npm run sidecar
```

Python / BMF 用同一个环境变量。

残留进程或旧 socket 会导致 `FileNotFoundError` / 连不上：

```sh
# 停掉旧 sidecar 后
rm -f /tmp/vgpu-fx.sock
npm run sidecar
```

改过 `effect-core` 或 sidecar 源码后必须重启这个进程。

### 2. Python 依赖

```sh
cd bmf-demo
uv sync
```

`uv.lock` 会装 `babitmf` + `numpy`（group `bmf`）。wgpu 后端加 `--group wgpu`；native 后端装本地 wheel：`uv pip install ../effect-rs/target/wheels/effect_rs-*.whl`（注意：`uv sync` 会清掉不属于任何依赖组的 wheel，装完 wgpu 组后若要用 native 需重装一次）。

### 3. 跑出片

在**另一个终端**（socket 后端时 sidecar 保持开着；wgpu/native 不需要）：

```sh
cd bmf-demo
VGPU_FX_BACKEND=wgpu uv run run_demo.py     # 全量 39 个
```

输入固定为仓库根下 `public/sample.mp4`。  
输出：`bmf-demo/output/{effect}.mp4`（gitignore）。

控制台每行是 `vgpu_fx[{backend}] {effect}: ... fps` 和 wall time。

环境变量：

| 变量 | 默认 | 作用 |
|---|---|---|
| `VGPU_FX_BACKEND` | auto | `wgpu` / `socket` / `native` |
| `VGPU_FX_SOCK` | `/tmp/vgpu-fx.sock` | 和 sidecar 同一条 socket（仅 socket 后端） |
| `VGPU_FX_BATCH` | `15` | 一次渲染几帧（同特效、同分辨率） |
| `VGPU_FX_EFFECTS` | 全部 | 逗号分隔，缩小特效范围 |
| `VGPU_FX_LIST_ONLY` | 关 | 置 `1` 只打印计划渲染的特效，不出片 |

只验协议、不跑 BMF：

```sh
# sidecar 已启动
cd bmf-demo
uv run python test_client.py
```

应打印 `ok python sidecar client`。

### 4. 自己的片子 / 单个特效

`run_demo.py` 里写死了 sample 和 catalog 的 39 个 id。换输入或只出某一个，改 `inp` / `EFFECTS`（或用 `VGPU_FX_EFFECTS=a,b,c`），或在自己的 BMF 图里挂模块：

```python
option = {
    "effect": "glitch",
    "socket": "/tmp/vgpu-fx.sock",
    "batch": 15,
    "params": {"intensity": 0.7, "speed": 1.4},
    "videoDuration": 10.0,  # zoom 缓动需要；没有可传 0
}
video = graph.decode({"input_path": "in.mp4"})["video"]
video = video.py_module("vgpu_fx", option, HERE, "vgpu_fx.VgpuFx")
video.encode(None, {"output_path": "out.mp4", "video_params": {"codec": "h264"}}).run()
```

`HERE` 必须是 `vgpu_fx.py` 所在目录。有音轨时把 `encode` 的音频 pad 接上，不要丢 `None`（本 demo 的 sample 没有音）。

`params` 的 key 与 catalog 里 `ParamDef.key` 一致，见下表。省略则用默认。

## 特效与参数

| id | 可调参数（默认） |
|---|---|
| `none` | 无 |
| `handheld-cam` | intensity 0.75, speed 1, zoom 0.14, sway 1, blur 1, glow 0.55 |
| `camera-shake` | intensity 0.5, speed 1.2, frequency 14, rotation 0.25, zoom 0.15 |
| `local-push` | intensity 0.75, speed 0.85, zoom 0.45, centerX/Y 0.5, chromatic 0.7, distortion 0.4, glow 0.55 |
| `glitch` | intensity 0.7, speed 1.4, slices 28, rgbSplit 1, block 0.8, scanline 0.35 |
| `screen-shake` | intensity 0.7, speed 1.6, punch 0.9, blur 0.85 |
| `zoom-in` | startScale 1.0, endScale 1.35, duration 1, centerX/Y 0.5, drift 0, **loop** 0 |
| `zoom-out` | startScale 1.35, endScale 1.0, duration 1, centerX/Y 0.5, drift 0.35, **loop** 0 |
| `colorhalftone` | dotRadius 0.4, angC 0.0417, angM 0.2083, angY 0 |
| `defish0r` | amount 0.55, scale 0.9, mode 1 (Defish) |
| `pixs0r` | intensity 0.5, blockHeight 12 (0=随机), columns 0.35, speed 0.6 |
| `dissolve` | speed 0.5, scale 5, edgeGlow 0.8, invert 1 (烧掉) |

zoom 的 `loop`：`1` 用 ping-pong 平滑循环，`0` 播完停在 `endScale`。出片请传 `videoDuration`（秒），缓动按 pts/`videoTime` 走。默认起止缩放都 ≥1，不再露黑边。

时间：预览用播放头；出片用帧 pts（秒）。调用方按时间轴选 **哪一个 id**，引擎不负责「到点切特效」。

## 出片速度

出片每帧都要 CPU→GPU→CPU（2160×3840 RGBA 约 33MB/帧），瓶颈是搬运，不是特效——`none` 也差不多。实测（Apple M3 Max，2160×3840@60fps，400 帧/特效）：

| backend | render fps | 单特效 wall |
|---|---|---|
| `wgpu` | ≈ 37–49 | ≈ 36–40s |
| `socket` | ≈ 16–17（socket 拷贝占大头） | ≈ 52–54s |
| `native` | 9–101（CPU，因特效而异） | 36–73s |

wgpu 进程内省掉 socket 和第二进程，是目前最快的出片路径。加大 `VGPU_FX_BATCH` 只能少几次往返，总流量不变。Web 预览没有读回，所以快。

## 故障排除

**预览黑屏 / 启动失败**  
浏览器不支持 WebGPU，或 `npx vgpu doctor` 不过。看页面 `#status`。

**`sidecar not listening`**  
先 `npm run sidecar`。路径要和 `VGPU_FX_SOCK` 一致。

**连上又立刻断 / 空 socket**  
杀掉旧 `start.mjs`，`rm -f /tmp/vgpu-fx.sock` 再启动。

**`str has no attribute uid`**  
BMF 挂载写错了，必须用 `video.py_module("vgpu_fx", option, HERE, "vgpu_fx.VgpuFx")`。

**BabitMF 找不到 `libavcodec.58`**  
装 FFmpeg 4，不是 5/6/7。macOS：`brew install ffmpeg@4`。

**`uv` / Python 3.14**  
换成 3.12：`bmf-demo/.python-version` 已是 3.12。

**编码器立刻结束**  
空音频 pad + 无音视频。无音轨用 `encode(None, ...)`。

**改了特效出片没变**  
socket 后端：sidecar 没重启。wgpu 后端：改了 WGSL 没重跑 `npm run export:effects`。

**wgpu 后端报 missing effects.json**  
先 `npm run export:effects` 生成 `packages/effect-core/dist-effects/`（正常已入库，clone 后即存在）。

**wgpu 后端拿不到 adapter**  
Linux 无 GPU 环境装 lavapipe（`apt install mesa-vulkan-drivers`）；macOS 不会出现。

**升级 wgpu-py 后渲染报错**  
API 可能漂移（如 0.32 的读回路径）。按 [验证手册](./wgpu-py-validation.md) 重跑 Step 3/4 验收。

**想逐像素对比 Dawn 和 wgpu 的结果**  
sidecar 开着，跑 `cd bmf-demo && uv run compare_wgpu.py`（39 特效全表，阈值见验证手册）。

**zoom 不动画**  
没传 `videoDuration`，或 `times` 全是 0。

## 测试（使用者可选）

```sh
npm test
```

会跑 doctor、shader 检查、engine smoke、sidecar smoke、frames、video-wait、tsc。sidecar smoke 自己拉起临时 worker，不必先手动 `npm run sidecar`。
