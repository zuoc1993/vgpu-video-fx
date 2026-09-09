# effect-rs 验证报告

日期：2026-08-07 · 机器：macOS aarch64（Apple M3 Max）· 视频：public/sample.mp4（2160×3840，60fps，400 帧）

## 1. 结论

架构可行，端到端验证通过：

- **实现一致性**：5 个移植特效与 GPU（WebGPU sidecar）输出均达到位级一致或 ±1 LSB；2026-09-09 回归复测 glitch max=1、pct>2=0.00%（详见 §2/§2.1）。
- **性能**：离线渲染 native（PyO3，rayon 批内并行）在 2160×3840 下 4 个特效渲染吞吐高于原 socket+GPU 管线（none/posterize 约 6×），glow 类重采样特效约为 GPU 路径的 0.55×（9.0fps，已低于 60fps 实时）。
- **双绑定**：wasm 包 97.8KB（gzip 43.4KB，2026-09-09 复测），Node 冒烟与 vite dev/build 均通过；python wheel（abi3，Py ≥3.10）在 bmf-demo venv 内直接调用，零拷贝入参。

## 2. 一致性（compare_backends.py，10 帧，diff = |gpu − rust| / 255）

| effect | mean | max | pct>2 | 判定 |
|---|---|---|---|---|
| none | 0.000 | 0 | 0.00% | 位级一致 |
| posterize | 0.000 | 0 | 0.00% | 位级一致 |
| rgbsplit0r | 0.002 | 1 | 0.00% | ≤1 LSB |
| glow | 0.001 | 1 | 0.00% | ≤1 LSB |
| glitch | 0.003 | 34 | 0.00% | 图案几何一致，几乎无离群 |

说明：

- hash2/pcg2d 按 u32 wrapping 算术位级复刻（单测含跨实现参考向量），glitch 的 tick/burst/slice/色块布局与 GPU **完全相同**。
- glitch 的极少量离群像素来自 fract 边界：GPU varying 插值/采样器坐标计算与 CPU 的 f32 舍入在“恰好落在换行边界附近”的坐标上可能差 1 ulp，导致个别像素采到对侧纹素。当前样片 10 帧实测 pct>2 仅 0.00%（mean 0.003/255，max 34；旧 1664×1080 样片曾测得 0.43%），视觉上为噪声级。
- 双线性采样器按 WebGPU linear 语义实现（u8/255 f32、clamp 边缘、texel 中心）；rgbsplit0r/glow 的 ±1 LSB 来自 GPU 硬件滤波权重精度，属预期。

### 2.1 2026-09-09 回归复测（hue/glow/rgbsplit 修复后）

修复 `hueRotate`、`glow` 亮部阈值/各向同性半径、`rgbsplit0r` 轴向耦合后重跑
`compare_backends.py`（4 帧，2160×3840，Apple M3 Max）：

| effect | mean | max | pct>2 | 判定 |
|---|---|---|---|---|
| none | 0.000 | 0 | 0.00% | 位级一致 |
| posterize | 0.000 | 0 | 0.00% | 位级一致 |
| rgbsplit0r | 0.002 | 1 | 0.00% | ≤1 LSB |
| glitch | 0.003 | 1 | 0.00% | ≤1 LSB |
| glow | 0.001 | 1 | 0.00% | ≤1 LSB |

同一轮还用 `compare_wgpu.py` 全量 39 特效对照 Dawn↔wgpu（2 帧），全部
`mean=0.000`、`pct>2=0.00%`（个别特效 max=1~3 LSB）。wasm 包与 native wheel
均已按同一份 Rust 源码重建；`node scripts/wasm-smoke.mjs` 通过。

## 3. 性能（bmf-demo 端到端，400 帧，render 阶段 fps）

| effect | native (effect_rs) | socket (GPU sidecar) | native wall | socket wall |
|---|---|---|---|---|
| none | **100.2 fps** | 15.6 fps | 36.6s | 54.4s |
| posterize | **100.8 fps** | 16.6 fps | 36.5s | 52.4s |
| rgbsplit0r | **28.7 fps** | 16.8 fps | 42.0s | 52.2s |
| glitch | **18.4 fps** | 16.0 fps | 50.1s | 54.1s |
| glow | 9.0 fps | **16.4 fps** | 72.7s | 52.6s |

- native 数字为 `effect_rs.render_batch` 调用耗时（rayon 并行 27 批 ×15 帧），不含 numpy 转换（cvt-in/out 两边相同，约 19.1s + 4.6s /400 帧）。
- socket 数字含 498MB/批 ×2 的进程间搬运与 GPU readback。
- 编译器自动 SIMD 达成目标：none/posterize 的逐像素 kernel（`chunks_exact(4)` 无分支 + 行序）在 2160×3840 并行下 ~10ms/帧，未手写任何 intrinsics。
- glow（8-tap 邻域采样）是 CPU 弱项，9.0fps 已低于 60fps 实时帧率；后续可换分离 box blur 优化。

## 4. 交付物

| 组件 | 状态 |
|---|---|
| effect-rs crate（核心 + 5 特效 + 单测 14 项） | ✅ `npm run test:effect-rs` |
| wasm 包 effect-rs/pkg（wasm-pack --target web，含 .d.ts） | ✅ `npm run build:effect-rs:wasm` |
| python wheel（abi3-py310） | ✅ `npm run build:effect-rs:py` |
| web 双后端切换（WebGPU / Rust CPU (wasm)） | ✅ typecheck + vite build + dev 端点冒烟 |
| bmf-demo 后端切换（native / socket，默认 native 回退 socket） | ✅ 端到端产出 5 个 mp4 |
| compare_backends.py 一致性对比 | ✅ 见 §2 |
| scripts/wasm-smoke.mjs（Node 下 wasm 冒烟） | ✅ |

web 侧说明：wasm 预览路径为单线程 + Uint8Array 进出各一次拷贝；浏览器内的交互验证建议人工打开 `npm run dev` 切换“Rust CPU (wasm)”后端确认。

### 4.1 web wasm 预览帧率问题与处理

首版 wasm 预览没有渲染分辨率上限，全分辨率下卡顿（旧 1664×1080 样片 ~15fps；现 2160×3840 样片 glitch 高达 698ms/帧，见下表）。原因与处理：

1. **单线程 + 无 SIMD 收益有限**：wasm 构建已启用 `+simd128`（仓库根 `.cargo/config.toml` 的 `target.wasm32-unknown-unknown` rustflags），但实测热循环向量化收益仅 ~0–12%（gather/带宽受限），不是主要杠杆。
2. **渲染分辨率上限（主要修复）**：`rs-engine.ts` 将 wasm 渲染分辨率限制为 720 宽（`MAX_RENDER_W`），视频先在 2D canvas 降采样、渲染结果再 drawImage 放大到显示画布（带信箱黑边）。渲染成本与窗口大小解耦。

实测纯渲染耗时（simd128 单线程，ms/帧）：

| 分辨率 | posterize | rgbsplit0r | glitch | glow |
|---|---|---|---|---|
| 2160×3840 | 71.3 | 490.3 | 697.8 | 1192.6 |
| 1080×1920 | 16.9 | 120.7 | 172.9 | 295.0 |
| 720×1280 | 7.5 | 54.7 | 77.4 | 131.2 |
| 640×1138（当前预览上限） | 5.9 | 42.9 | 61.3 | 102.0 |
| 540×960 | 4.4 | 30.6 | 42.8 | 73.3 |

#### Retina 掉帧问题（已修复；当前样片复测）

历史背景（旧 1664×1080@30fps 样片）：首轮 720 宽上限在 Retina（dpr=2）实测仍只有 15fps，经无头 Chrome + CDP 分阶段计时（`scripts/browser-perf.mjs`，帧内计时由 `window.__RS_TIMING=1` 开启）定位到 capture 与 upscale 两处：capture 4–7.5ms、render（glitch，720 宽）26.9ms、upscale 为 3x 插值+填充，total 31.5–35.1ms 恰好卡在 33.3ms 帧间隔边界，抖动即跌到 15fps。修复：`createImageBitmap` 一步缩放、上限降至 640 宽、显示画布固定 dpr=1。

当前样片（2160×3840@60fps）修复后分阶段实测（headless Chrome，dpr=2，渲染 640×1138 = MAX_RENDER_W 640 上限；显示画布 1046×588）：

| 阶段 | 实测 |
|---|---|
| capture（视频降采样） | 0.1–0.9ms |
| readback（getImageData） | 3.6–4.8ms |
| render（glitch wasm，640×1138） | 63.2–64.2ms |
| put / upscale | 0.3ms / ~0ms |
| **total** | **~68ms**（render 主导；60fps 帧间隔 16.7ms 下 glitch 预览 15fps） |

最终实测（headless Chrome，dpr=2，2160×3840@60fps 视频）：none 48fps、posterize 47fps、rgbsplit0r 20fps、glitch 15fps、glow 9fps（60fps 为视频帧率上限；WebGPU 后端对照 glitch 53fps）。wasm 重采样特效在新样片下掉帧明显：宽度上限 640 对竖屏视频实际是 640×1138（约为旧 640×360 的 3.2 倍像素），进一步压 glow 可引入 COOP/COEP + wasm 线程、分离 box blur，或把上限改为按总像素封顶；基准脚本 `scripts/bench-wasm.mjs`（Node）与 `scripts/browser-perf.mjs`（真实 Chrome）可复测。

## 5. 已知边界 / 后续方向

- **wasm 单线程**：web 预览 glow / rgbsplit0r / glitch 在当前 2160×3840 样片下明显掉帧（实测 9–20fps，渲染上限 640×1138）；多线程需 COOP/COEP（部署变更），暂缓。可选 `RUSTFLAGS="-C target-feature=+simd128"` 开启 wasm SIMD128 再测。
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

特效选择跟随后端：native → `effect_rs.catalog()` 与 TS 清单的交集（当前 5 个）；socket → 全量 39 个；`VGPU_FX_EFFECTS` 可进一步收窄。web 侧同样按后端展示：WebGPU 显示 39 个，Rust CPU (wasm) 显示 wasm catalog 的 5 个。
