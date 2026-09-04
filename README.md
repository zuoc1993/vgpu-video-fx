# vgpu Video FX

同一套 WebGPU 特效（38 个）：浏览器里实时预览；BMF 离线出片有三条后端——进程内 wgpu-py（推荐，无需 sidecar）、Node sidecar（Dawn）、effect_rs（CPU，5 个特效）。

## 文档

| 文档 | 内容 |
|---|---|
| [架构](docs/architecture.md) | 模块职责、数据流、协议、性能 |
| [使用指南](docs/usage.md) | 预览、出片、参数、排错 |
| [开发](docs/development.md) | 加特效、时钟、测试、约束 |
| [wgpu-py 后端](docs/wgpu-py-backend.md) | 导出产物设计、渲染语义、一致性基准 |
| [wgpu-py 验证手册](docs/wgpu-py-validation.md) | 后端验收步骤与报告模板 |
| [effect-rs 验证](docs/effect-rs-validation.md) | CPU 后端验收记录 |

## 快速开始

```sh
npm install
npm run dev          # http://127.0.0.1:5173/
```

出片（wgpu 后端，不起 sidecar）：

```sh
npm run export:effects                       # 导出 WGSL 产物（已入库，改 shader 后重跑）
cd bmf-demo && uv sync --group wgpu
VGPU_FX_BACKEND=wgpu uv run run_demo.py
```

sidecar 出片：先 `npm run sidecar`，再 `cd bmf-demo && uv sync && VGPU_FX_BACKEND=socket uv run run_demo.py`。细节见使用指南。

```sh
npm test
```

## 特效

`none` · `handheld-cam` · `camera-shake` · `local-push` · `glitch` · `screen-shake` · `zoom-in` · `zoom-out` · `cylinder-wrap` · `pixeliz0r` · `squigglevision` · `colorhalftone` · `sobel` · `water` · `defish0r` · `vignette` · `heatmap0r` · `glitch0r` · `pixels0rt` · `kaleid0sc0pe` · `distort0r` · `rgbsplit0r` · `emboss` · `posterize` · `pixs0r` · `dither` · `ntsc` · `edgeglow` · `scanline0r` · `glow` · `crt` · `spectral-flare` · `dust-bokeh` · `spacetime-lens` · `retro-quantize` · `grade` · `light-leak` · `dissolve`
