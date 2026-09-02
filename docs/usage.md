# 使用指南

两条用法：**浏览器预览**（实时）和 **BMF 出片**（sidecar + 解码编码）。特效 id 两边相同。

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

示例视频：`public/sample.mp4`（约 1664×1080、3.6s、无音轨）。

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

先起 GPU worker，再跑 BMF。

### 1. Sidecar

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

`uv.lock` 会装 `babitmf` + `numpy`（group `bmf`）。

### 3. 跑 8 个特效

在**另一个终端**（sidecar 保持开着）：

```sh
cd bmf-demo
uv run run_demo.py
```

输入固定为仓库根下 `public/sample.mp4`。  
输出：`bmf-demo/output/{effect}.mp4`（gitignore）。

控制台会打 sidecar 耗时和 fps，以及 wall time。

环境变量：

| 变量 | 默认 | 作用 |
|---|---|---|
| `VGPU_FX_SOCK` | `/tmp/vgpu-fx.sock` | 和 sidecar 同一条 socket |
| `VGPU_FX_BATCH` | `15` | 一次 socket 送几帧（同特效、同分辨率） |

只验协议、不跑 BMF：

```sh
# sidecar 已启动
cd bmf-demo
uv run python test_client.py
```

应打印 `ok python sidecar client`。

### 4. 自己的片子 / 单个特效

`run_demo.py` 里写死了 sample 和 8 个 id。换输入或只出某一个，改 `inp` / `EFFECTS`，或在自己的 BMF 图里挂模块：

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
| `camera-shake` | intensity 0.5, speed 1.2, frequency 14 |
| `local-push` | intensity 0.75, speed 0.85, zoom 0.45, centerX/Y 0.5, chromatic 0.7, distortion 0.4, glow 0.55 |
| `glitch` | intensity 0.7, speed 1.4, slices 28, rgbSplit 1, block 0.8, scanline 0.35 |
| `screen-shake` | intensity 0.7, speed 1.6, punch 0.9, blur 0.85 |
| `zoom-in` | startScale 0.5, endScale 0.7, duration 1, **loop** 1 |
| `zoom-out` | startScale 0.7, endScale 0.5, duration 1, **loop** 1 |

zoom 的 `loop`：`1` 循环，`0` 播完停在 `endScale`。出片请传 `videoDuration`（秒），缓动按 pts/`videoTime` 走。

时间：预览用播放头；出片用帧 pts（秒）。调用方按时间轴选 **哪一个 id**，引擎不负责「到点切特效」。

## 出片速度

sidecar 路径每帧都要 CPU→GPU→CPU，再加 socket。1080p RGBA 约 7MB/帧，常见大约数 fps，`none` 也差不多——瓶颈是搬运，不是特效。Web 预览没有读回，所以快。

加大 `VGPU_FX_BATCH` 只能少几次往返，总流量不变。

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
sidecar 没重启。

**zoom 不动画**  
没传 `videoDuration`，或 `times` 全是 0。

## 测试（使用者可选）

```sh
npm test
```

会跑 doctor、shader 检查、engine smoke、sidecar smoke、frames、video-wait、tsc。sidecar smoke 自己拉起临时 worker，不必先手动 `npm run sidecar`。
