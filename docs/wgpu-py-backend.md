# wgpu-py 无头后端（进程内 GPU 渲染）

离线出片的第三条路径：**不起 Node sidecar、不走 socket**，Python 进程内直接用
[wgpu-py](https://github.com/pygfx/wgpu-py)（wgpu-native 的 Python 绑定，Rust 实现）
跑 effect-core 的 WGSL。特效 shader **零改动、零翻译**。

```
构建期（改 shader 后跑一次）                运行期（Python 进程内）
─────────────────────────────             ─────────────────────────────
npm run export:effects                    bmf decode → vgpu_fx.py backend="wgpu"
  vgpu resolveShader 拍平 import    →       numpy RGBA → queue.write_texture
  + 注入全屏三角形顶点阶段            →     → render pass（同一份 WGSL，naga 编译）
  + vgpu reflect 导出 uniform 布局    →     → copy_texture_to_buffer → numpy
  packages/effect-core/dist-effects/
    {id}.wgsl + effects.json
```

## 为什么产物是权威的

- `.wgsl` 由 vgpu 自家 `@vgpu/wgsl` runtime 拍平（和 sidecar 的 node loader 同一代码路径），
  再拼上 vgpu `effect()` 运行时注入的同一个全屏三角形顶点阶段
  （`vgpu/dist/effect.js` 的 `fullscreenSource`）——**就是 vgpu 喂给 Dawn 的那串字符**
- uniform 布局（字段偏移/总大小）来自 vgpu 的反射（naga-standard host-shareable 规则），
  Python 端不做任何 WGSL 解析，按 `effects.json` 里的偏移打包字节
- `(values, ctx) → uniform 字段` 的映射由导出器用**哨兵值求值**各特效的 `uniforms()`
  自动判定；目前全 catalog 唯一的条件表达式是
  `videoDuration > 0 ? videoTime : time`（zoom-in / zoom-out / cylinder-wrap），
  映射为 `["ctx", "videoTimeOrTime"]`。出现新逻辑时导出器会**报错而不是猜**

## 渲染语义（与 sidecar 对齐）

全屏三角形 `draw(3)`；group0 = texture_2d + linear sampler + uniform；
rgba8unorm 离屏 target，clear `[0,0,0,1]`；每帧一次 submit（uniform 原地写，
同一 submit 里的多个 pass 会都看到最后一次写入——engine.ts 同款约束）；
读回 `bytes_per_row` 按 256 对齐后去 padding。

## 用法

```bash
npm run export:effects                 # 生成 packages/effect-core/dist-effects/
cd bmf-demo && uv sync --group wgpu    # 或 uv pip install wgpu

# 自检（不需要 bmf / sidecar）：合成帧渲染
uv run vgpu_fx_gpu.py posterize 4

# 一致性对照（需要先 npm run sidecar）：Dawn/tint vs wgpu/naga 全量 diff
uv run compare_wgpu.py

# 出片
VGPU_FX_BACKEND=wgpu uv run run_demo.py
```

后端选择：`VgpuFx` 的 `backend` 选项或 `VGPU_FX_BACKEND` 环境变量接受
`native` / `wgpu` / `socket`；缺不可用时按 `wgpu→native→socket` 链回退，
未指定时 auto 顺序为 `native→wgpu→socket`（保持装了 effect_rs 时的现状）。

## 环境变量

| 变量 | 作用 |
|---|---|
| `VGPU_FX_EFFECTS_DIR` | 覆盖 dist-effects 目录位置 |
| `VGPU_EXPORT_VALIDATE` | 导出时 WGSL 校验级别（默认 `off`，目标运行时是 naga；`require` 走 Dawn） |
| `WGPU_BACKEND` | wgpu 原生后端选择（`vulkan` / `metal` / `dx12` / `gl`） |

## 无 GPU 环境

- Linux：lavapipe（Mesa Vulkan 软渲）即可——`apt install mesa-vulkan-drivers`
  或沿用 vgpu release 里那份钉死 hash 的 ICD，设 `VK_ICD_FILENAMES` 指向它
- Windows：wgpu 自动回退 WARP（D3D12 CPU）
- macOS：必有 Metal

## 一致性预期

整数 hash（pcg2d 等 u32 wrapping）与 Dawn 位级一致；浮点采样/滤波在
tint→MSL 与 naga→MSL 两条编译链间可能差 ±1 LSB——与 effect-rs 验证报告 §2
同级。判定标准：`compare_wgpu.py` 的 `mean` 应 ≈ 0，`pct>2` 应 ≈ 0%。

## 已知边界

- 仅覆盖离线出片路径（offscreen + readback）；浏览器预览仍走 vgpu TS
- `effects.json` 需与 shader 同步更新——改了 `.wgsl` 或 effect `index.ts`
  必须重跑 `npm run export:effects`（`git diff dist-effects/` 即评审面）
- wgpu-py 每帧十几次 Python API 调用的开销在 1080p 下可忽略；
  若未来要再压，可把批内循环下沉到一个 Rust PyO3 助手（届时就是完整
  effect-rs GPU 后端的形态了）
