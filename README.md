# vgpu Video FX

同一套 WebGPU 特效：浏览器里实时预览，BMF 里经 Node sidecar 离线出片。

## 文档

| 文档 | 内容 |
|---|---|
| [架构](docs/architecture.md) | 模块职责、数据流、协议、性能 |
| [使用指南](docs/usage.md) | 预览、出片、参数、排错 |
| [开发](docs/development.md) | 加特效、时钟、测试、约束 |

## 快速开始

```sh
npm install
npm run dev          # http://127.0.0.1:5173/
```

出片：先 `npm run sidecar`，再 `cd bmf-demo && uv sync && uv run run_demo.py`。细节见使用指南。

```sh
npm test
```

## 特效

`none` · `handheld-cam` · `camera-shake` · `local-push` · `glitch` · `screen-shake` · `zoom-in` · `zoom-out`
