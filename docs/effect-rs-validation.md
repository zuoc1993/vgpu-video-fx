# effect-rs 验证报告

日期：2026-08-04 · 机器：macOS aarch64（Apple Silicon）· 视频：public/sample.mp4（1664×1080，30fps，109 帧）

## 1. 结论

架构可行，端到端验证通过：

- **实现一致性**：5 个移植特效中 4 个与 GPU（WebGPU sidecar）输出达到位级一致或 ±1 LSB；glitch 99.57% 像素在 ±2 LSB 内（详见 §2）。
- **性能**：离线渲染 native（PyO3，rayon 批内并行）在 1080p 下 4 个特效渲染吞吐高于原 socket+GPU 管线（none/posterize 约 8×），glow 类重采样特效约为 GPU 路径的 0.57×（仍 44.6fps > 实时）。
- **双绑定**：wasm 包 93.6KB（gzip 42.5KB），Node 冒烟与 vite dev/build 均通过；python wheel（abi3，Py ≥3.10）在 bmf-demo venv 内直接调用，零拷贝入参。

## 2. 一致性（compare_backends.py，10 帧，diff = |gpu − rust| / 255）

| effect | mean | max | pct>2 | 判定 |
|---|---|---|---|---|
| none | 0.000 | 0 | 0.00% | 位级一致 |
| posterize | 0.000 | 0 | 0.00% | 位级一致 |
| rgbsplit0r | 0.003 | 1 | 0.00% | ≤1 LSB |
| glow | 0.000 | 1 | 0.00% | ≤1 LSB |
| glitch | 0.217 | 248 | 0.43% | 图案几何一致，采样有噪声 |

说明：

- hash2/pcg2d 按 u32 wrapping 算术位级复刻（单测含跨实现参考向量），glitch 的 tick/burst/slice/色块布局与 GPU **完全相同**。
- glitch 的 0.43% 离群像素来自 fract 边界：GPU varying 插值/采样器坐标计算与 CPU 的 f32 舍入在“恰好落在换行边界附近”的坐标上可能差 1 ulp，导致个别像素采到对侧纹素（max 248）。均值 0.217/255，视觉上为噪声级。
- 双线性采样器按 WebGPU linear 语义实现（u8/255 f32、clamp 边缘、texel 中心）；rgbsplit0r/glow 的 ±1 LSB 来自 GPU 硬件滤波权重精度，属预期。

## 3. 性能（bmf-demo 端到端，109 帧，render 阶段 fps）

| effect | native (effect_rs) | socket (GPU sidecar) | native wall | socket wall |
|---|---|---|---|---|
| none | **551.2 fps** | 64.8 fps | 2.24s | 3.95s |
| posterize | **530.2 fps** | 74.1 fps | 2.20s | 3.37s |
| rgbsplit0r | **139.4 fps** | 74.1 fps | 2.60s | 3.39s |
| glitch | **88.1 fps** | 70.9 fps | 3.10s | 3.48s |
| glow | 44.6 fps | **78.3 fps** | 4.27s | 3.30s |

- native 数字为 `effect_rs.render_batch` 调用耗时（rayon 并行 8 批 ×15 帧），不含 numpy 转换（cvt-in/out 两边相同，约 1.3s/109 帧）。
- socket 数字含 16MB/批 ×2 的进程间搬运与 GPU readback。
- 编译器自动 SIMD 达成目标：none/posterize 的逐像素 kernel（`chunks_exact(4)` 无分支 + 行序）在 1080p 并行下 ~2.5ms/帧，未手写任何 intrinsics。
- glow（8-tap 邻域采样）是 CPU 弱项，44.6fps 仍高于视频实时帧率；后续可换分离 box blur 优化。

## 4. 交付物

| 组件 | 状态 |
|---|---|
| effect-rs crate（核心 + 5 特效 + 单测 11 项） | ✅ `npm run test:effect-rs` |
| wasm 包 effect-rs/pkg（wasm-pack --target web，含 .d.ts） | ✅ `npm run build:effect-rs:wasm` |
| python wheel（abi3-py310） | ✅ `npm run build:effect-rs:py` |
| web 双后端切换（WebGPU / Rust CPU (wasm)） | ✅ typecheck + vite build + dev 端点冒烟 |
| bmf-demo 后端切换（native / socket，默认 native 回退 socket） | ✅ 端到端产出 5 个 mp4 |
| compare_backends.py 一致性对比 | ✅ 见 §2 |
| scripts/wasm-smoke.mjs（Node 下 wasm 冒烟） | ✅ |

web 侧说明：wasm 预览路径为单线程 + Uint8Array 进出各一次拷贝；浏览器内的交互验证建议人工打开 `npm run dev` 切换“Rust CPU (wasm)”后端确认。

### 4.1 web wasm 预览帧率问题与处理

首版 wasm 预览在 1080p 只有 ~15fps。原因与处理：

1. **单线程 + 无 SIMD 收益有限**：wasm 构建已启用 `+simd128`（仓库根 `.cargo/config.toml` 的 `target.wasm32-unknown-unknown` rustflags），但实测热循环向量化收益仅 ~0–12%（gather/带宽受限），不是主要杠杆。
2. **渲染分辨率上限（主要修复）**：`rs-engine.ts` 将 wasm 渲染分辨率限制为 720 宽（`MAX_RENDER_W`），视频先在 2D canvas 降采样、渲染结果再 drawImage 放大到显示画布（带信箱黑边）。渲染成本与窗口大小解耦。

实测纯渲染耗时（simd128 单线程，ms/帧）：

| 分辨率 | posterize | rgbsplit0r | glitch | glow |
|---|---|---|---|---|
| 1664×1080 | 14.1 | 99.3 | 141.1 | 240.4 |
| 1280×720 | 7.1 | 50.9 | 72.4 | 124.0 |
| 960×540 | 4.0 | 28.5 | 40.6 | 69.4 |
| 720×405 | 2.2 | 16.1 | 22.8 | 39.0 |
| 640×360（当前预览上限） | 1.7 | 12.7 | 18.0 | 31.0 |

#### Retina 15fps 问题（已修复，实测）

首轮 720 上限在 Retina（dpr=2）实测仍只有 15fps，经无头 Chrome + CDP 分阶段计时（`scripts/browser-perf.mjs`，帧内计时由 `window.__RS_TIMING=1` 开启）定位到两处：

| 阶段（720 宽，dpr=2） | 修复前 | 修复后 |
|---|---|---|
| capture（视频降采样） | 4–7.5ms | 0.2ms（`createImageBitmap` 一步缩放，替代软件 drawImage） |
| render（glitch wasm） | 26.9ms | 20.9ms（上限降至 640 宽） |
| upscale（显示画布） | 3x 插值+填充 | ~0ms（显示画布固定 dpr=1，Retina 放大交给浏览器合成器） |
| **total** | 31.5–35.1ms（恰好卡在 33.3ms 帧间隔边界，抖动即跌到 15fps） | **23.2ms** |

最终实测（headless Chrome，dpr=2，1664×1080 视频）：none 29fps、posterize 30fps、rgbsplit0r 30fps、glitch **30fps**、glow 24fps（30fps 为视频帧率上限；WebGPU 后端对照 29–30fps）。进一步压 glow 可引入 COOP/COEP + wasm 线程或分离 box blur；基准脚本 `scripts/bench-wasm.mjs`（Node）与 `scripts/browser-perf.mjs`（真实 Chrome）可复测。

## 5. 已知边界 / 后续方向

- **wasm 单线程**：web 预览 glow 在 1080p 会明显掉帧；多线程需 COOP/COEP（部署变更），暂缓。可选 `RUSTFLAGS="-C target-feature=+simd128"` 开启 wasm SIMD128 再测。
- **剩余 33 个特效未移植**：结构已就绪（`Effect` trait + registry），逐特效翻译 WGSL 即可；优先顺序建议按“逐像素 → 重采样 → 模糊”展开。
- **许可**：0r 系源自 GPL-2.0 的 frei0r（经仓库已有 WGSL 移植），公开发布前需明确 effect-rs 的许可立场（当前 crate 标为 GPL-2.0-only）。
- **发布矩阵**：当前仅 macOS arm64 wheel；linux x86_64 / wasm CI 未覆盖。
- **glitch 边界噪声**：如需像素级全等，需复刻 GPU varying/采样器舍入行为，投入产出比低，不建议。

## 6. 复现命令

```bash
npm run test:effect-rs          # Rust 单测
npm run build:effect-rs:wasm    # wasm 包 → effect-rs/pkg
npm run build:effect-rs:py      # wheel → bmf-demo/.venv
npm run sidecar                 # 终端 A：GPU 对照后端
cd bmf-demo && VGPU_FX_BACKEND=socket uv run compare_backends.py   # 一致性
cd bmf-demo && VGPU_FX_BACKEND=native uv run run_demo.py           # native 渲染（自动只跑 rs 已有的特效）
cd bmf-demo && VGPU_FX_BACKEND=socket uv run run_demo.py           # socket 渲染（全量 TS 特效清单）
cd bmf-demo && VGPU_FX_BACKEND=socket VGPU_FX_LIST_ONLY=1 uv run run_demo.py  # 只看计划清单
node scripts/wasm-smoke.mjs     # wasm 绑定冒烟
```

特效选择跟随后端：native → `effect_rs.catalog()` 与 TS 清单的交集（当前 5 个）；socket → 全量 38 个；`VGPU_FX_EFFECTS` 可进一步收窄。web 侧同样按后端展示：WebGPU 显示 38 个，Rust CPU (wasm) 显示 wasm catalog 的 5 个。
