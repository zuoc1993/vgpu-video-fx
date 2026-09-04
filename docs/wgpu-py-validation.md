# wgpu-py 后端验证手册

目标：验证「Python 预取编译产物 + wgpu-py 进程内渲染」链路（`docs/wgpu-py-backend.md`）。
本手册给执行 agent 用：**逐步执行，每步有明确通过标准；任何一步失败，先按「失败处置」处理，无法修复则停止并把报告模板填好带回**。

涉及的新文件（应已在工作区，用 `git status` 确认）：

```
scripts/export-effects.mjs        # 导出器（拍平+反射+映射检测），--dry 只验不写
scripts/wgsl-export-loader.mjs    # 导出用 WGSL loader（默认 validate off，有意为之）
bmf-demo/vgpu_fx_gpu.py           # wgpu-py 渲染器
bmf-demo/compare_wgpu.py          # Dawn vs wgpu 一致性对照
bmf-demo/vgpu_fx.py               # 已加 backend="wgpu"（pick_backend 回退链）
bmf-demo/run_demo.py              # 已支持 wgpu 的特效规划
bmf-demo/pyproject.toml           # 已加 wgpu 依赖组
package.json                      # 已加 export:effects 脚本
```

背景知识（判断失败时要知道的三件事）：

1. 导出的 `.wgsl` = vgpu 官方拍平器产物 + vgpu 运行时注入的全屏三角形顶点阶段，**逐字节等价于 vgpu 喂给 Dawn 的字符串**；Python 侧不解析 WGSL，uniform 布局读 `effects.json`（来自 vgpu 反射）。
2. 渲染语义刻意对齐 sidecar：逐帧 submit（uniform 原地写，不能合批）、clear `[0,0,0,1]`、读回 256 对齐去 padding。
3. 一致性判定基准：sidecar（Dawn/tint→MSL）是参照系；wgpu-py（wgpu/naga→MSL）是同一块 GPU 的另一条编译链。整数 hash 应位级一致，浮点滤波允许 ±1 LSB 量级差异。

---

## Step 0 · 环境就绪

```bash
cd /Users/zuoc/Documents/vscode/vgpu
node --version          # 需要 >= 22.6（TS type stripping）
uv --version
git status --short      # 应看到上面的新文件；删掉残留：rm -f .write-test-editor
```

失败处置：Node 太旧 → 升级 Node（brew）；无 uv → `brew install uv`。

## Step 1 · 导出特效产物

```bash
npm run export:effects
```

通过标准（逐条检查）：

```bash
ls packages/effect-core/dist-effects/*.wgsl | wc -l    # 期望 38
ls packages/effect-core/dist-effects/effects.json       # 存在
# 所有产物必须是标准 WGSL：无 import/export 残留
grep -rl "^\s*import \|^\s*export " packages/effect-core/dist-effects/*.wgsl   # 期望无输出
# 每个产物都含注入的顶点阶段和片元入口
grep -L "vgpu_fullscreen_vs" packages/effect-core/dist-effects/*.wgsl          # 期望无输出
grep -L "fn fs_main" packages/effect-core/dist-effects/*.wgsl                  # 期望无输出
# manifest 结构抽查：zoom-in 的 videoTime 必须是 videoTimeOrTime 映射
python3 -c "
import json
m = json.load(open('packages/effect-core/dist-effects/effects.json'))
assert m['vertexEntry'] == 'vgpu_fullscreen_vs' and m['fragmentEntry'] == 'fs_main'
assert m['format'] == 'rgba8unorm' and len(m['effects']) == 38
z = next(e for e in m['effects'] if e['id'] == 'zoom-in')
assert z['mapping']['videoTime'] == ['ctx', 'videoTimeOrTime'], z['mapping']
assert z['uniformSize'] == 48 and len(z['fields']) == 8
p = next(e for e in m['effects'] if e['id'] == 'posterize')
assert p['uniformSize'] == 32, p['uniformSize']  # uniform 地址空间结构体对齐 16：end 24 → size 32
print('manifest OK')
"
```

失败处置：

- 导出器报 `cannot auto-map uniform field` → 说明某特效 `uniforms()` 出现了导出器不认识的逻辑。**不要改导出器放过它**，把报错原文和该特效的 `index.ts` 的 `uniforms()` 片段贴进报告。
- 报 binding 形状不符（`unexpected binding shape`）→ 同上，贴报错。
- 进程退出时出现 `FATAL ERROR ... darwin-universal.dawn.node` → 已知问题（Dawn 校验设备在 hooks 线程的 teardown 竞态）。导出 loader 默认 `validate: "off"` 就是为了避开它；如果仍出现，确认没有设置 `VGPU_EXPORT_VALIDATE`。只要 artifacts 写全（38 个 wgsl + json）且后续步骤通过，可在报告中标注后忽略。

## Step 2 · 安装 wgpu-py

```bash
cd bmf-demo
uv sync --group wgpu    # 或者：uv pip install wgpu
uv run python -c "import wgpu; print('wgpu-py', wgpu.__version__)"
uv run python -c "
import wgpu
a = wgpu.gpu.request_adapter_sync(power_preference='high-performance')
d = a.request_device_sync()
print('adapter OK:', getattr(getattr(a, 'info', None), 'device', 'unknown'))
"
```

通过标准：打印版本号 + `adapter OK`。版本应 ≥ 0.20。

失败处置：

- 无 adapter（仅可能出现在 Linux 无 GPU 环境）→ 装 lavapipe（`apt install mesa-vulkan-drivers`）后重试；macOS 不可能走到这里。
- wgpu 装不上 → 贴 `uv` 报错原文。

## Step 3 · 免 bmf/免 sidecar 合成帧冒烟

```bash
cd bmf-demo
uv run vgpu_fx_gpu.py none 4            # 直通特效：最小管线验证
uv run vgpu_fx_gpu.py posterize 4       # 均匀量化
uv run vgpu_fx_gpu.py glitch 4          # 含 wgsl-std hash（pcg2d）的拍平产物
uv run vgpu_fx_gpu.py spectral-flare 4  # 含 perlin 噪声（嵌套包 import）的拍平产物
uv run vgpu_fx_gpu.py glow 4            # 9-tap 重采样
```

通过标准：5 个特效都打印 `adapter: ...` + `{effect} x4 320x180: ... checksum=...`，无异常；输出 `bytes=921600`（320×180×4×4）。

失败处置：

- **naga parse 错误（本验证最关键的风险点）**：报错会含 `Shader module` / `naga` 字样和出错的 wgsl 位置。把完整报错 + 对应 `dist-effects/{id}.wgsl` 的前 40 行贴进报告。先尝试 `uv pip install -U wgpu`（拿更新的 naga）再重试一次。
- `create_render_pipeline` 参数相关 TypeError → wgpu-py API 漂移。贴 `wgpu.__version__` 和报错；允许执行 agent 按当前 wgpu-py 文档修正 `vgpu_fx_gpu.py` 的调用（保持语义不变），并在报告中说明改了什么。
- `queue.read_buffer` 不存在 → 代码里已有 `buf.read()` 回退，不应触发；若触发说明 wgpu-py 太旧，升级。

## Step 4 · 一致性主门：sidecar(Dawn) vs wgpu-py

```bash
# 终端 A（另一个会话/窗口，仓库根目录）：
npm run sidecar
# 终端 B：
cd /Users/zuoc/Documents/vscode/vgpu && npm run smoke:sidecar   # 先确认 sidecar 健康
cd bmf-demo && uv run compare_wgpu.py
```

通过标准（对照全量 38 特效，默认 10 帧）：

- 所有特效都产出 diff 行，无 `LENGTH MISMATCH`、无异常
- `none` 必须 **mean=0.000 max=0**（直通，任何偏差都说明管线错位）
- 大多数特效 mean ≈ 0；判定阈值：**mean < 0.05 且 pct>2 < 1%** 视为通过
- 个别特效超过阈值但图案几何一致（类似 effect-rs 报告里 glitch 的边界噪声）→ 记录在案可接受

常见诊断：

| 现象 | 判断 |
|---|---|
| 全部特效所有像素大 diff | uv/y 翻转或行对齐错了 → 检查 `vgpu_fx_gpu.py` 的 `VERTEX_STAGE` 是否被改动、读回去 padding 逻辑 |
| 只有含模糊/多采样的特效（glow、spectral-flare、dust-bokeh、edgeglow、water、dissolve）有小 diff | tint/naga 浮点指令选择差异，±1 LSB 级 → 正常 |
| 某特效 mean 显著大且 pct>2 高 | 贴该行数据 + 该特效 `dist-effects/{id}.wgsl`，停止后续步骤 |
| socket 连不上 | 终端 A 的 sidecar 没起来；`npm run sidecar` 的输出贴进报告 |

顺带记录性能：`compare_wgpu.py` 每行末尾的 `dawn_ms` / `wgpu_ms` 都填进报告（wgpu 应不慢于 dawn 的 1.5 倍；若慢 10 倍以上，检查是否落到了软件渲染器）。

## Step 5 · 端到端出片

```bash
cd bmf-demo
VGPU_FX_BACKEND=wgpu uv run run_demo.py                       # 全量 38 个
ls -la output/ | wc -l                                        # 38 个 mp4 + .
# 抽样核对时长/分辨率
ffprobe -v error -show_entries stream=width,height -of csv=p=0 output/posterize.mp4   # 1664x1080
```

通过标准：38 个 mp4 生成；控制台每行是 `vgpu_fx[wgpu] {effect}: ... fps`；分辨率 1664x1080。

失败处置：BMF 报 `libavcodec` 相关错误 → 需要 FFmpeg 4（`brew install ffmpeg@4`），这是 BMF 自身的既有约束，与本次改动无关。

可选性能对照（需要 sidecar）：`VGPU_FX_BACKEND=socket uv run run_demo.py`，把两边 `run_one` 的 wall time 填入报告。

## Step 6 · 回归：确认没碰坏现有路径

```bash
npm run typecheck
npm run check:shaders
cd bmf-demo && VGPU_FX_BACKEND=native uv run run_demo.py    # 若装了 effect_rs；未装则跳过并注明
```

通过标准：typecheck / check:shaders 全绿；native 路径行为不变（只产出 effect_rs 已有的 5 个特效）。

## Step 7 · 收尾

```bash
cd /Users/zuoc/Documents/vscode/vgpu
git add packages/effect-core/dist-effects/ scripts/export-effects.mjs scripts/wgsl-export-loader.mjs \
        bmf-demo/vgpu_fx_gpu.py bmf-demo/compare_wgpu.py bmf-demo/vgpu_fx.py bmf-demo/run_demo.py \
        bmf-demo/pyproject.toml docs/wgpu-py-backend.md package.json
git diff --cached --stat
```

`dist-effects/` 应提交（Python 侧运行不依赖 Node；改 shader 后重跑导出器，`git diff` 即评审面）。

---

## 报告模板（执行完填好带回）

```
## wgpu-py 后端验证报告

### 环境
- OS/arch:
- node:
- python / wgpu-py:
- GPU（adapter OK 行）:

### Step 1 导出
- [ ] 38 个 wgsl + effects.json
- [ ] 无 import/export 残留、入口齐全、manifest 断言通过

### Step 3 冒烟（贴 5 行输出）

### Step 4 一致性（贴 compare_wgpu.py 全表）
- 超阈值特效及判定:

### Step 5 端到端
- [ ] 38 个 mp4；wgpu 后端 fps 汇总 / 与 socket 对照 wall time

### Step 6 回归
- [ ] typecheck / check:shaders / native

### 遇到的问题与处置
- （含对 vgpu_fx_gpu.py 等文件的任何修改及原因）

### 结论
- [ ] 通过 / 有条件通过（说明）/ 未通过（阻塞点）
```
