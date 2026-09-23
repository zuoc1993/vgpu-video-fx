#!/usr/bin/env node
/**
 * AE parity check —— 把 AE 导出的 fixture 拿 vgpu 的 WGSL 跑一遍，逐像素比。
 *
 *   node scripts/check-ae-parity.mjs <fixturesDir> [options]
 *
 * <fixturesDir> 由 tools/ae-export/ae-fixture-export.jsx 产出：
 *   effect.json         AE 侧元数据（comp 尺寸/帧率、effect、全部 case）
 *   map.json            人手/agent 写的映射（AE matchName -> vgpu param key）
 *   caseNN/params.json  该组参数值
 *   caseNN/in_XXXX.raw  特效关闭时的画面 = 真正的输入（紧凑 RGBA8）
 *   caseNN/out_XXXX.raw 特效打开时的画面 = 期望输出
 *
 * 传一个父目录（下面有多个 effect.json）就整批跑。
 *
 * Options:
 *   --effect <id>      覆盖 map.json 里的 vgpuEffect
 *   --max-mean <n>     平均绝对差上限（0-255 尺度），默认 2
 *   --max-pct <n>      pct>over 的百分比上限，默认 2
 *   --over <n>         单通道差超过它算「这个像素不一样」，默认 8
 *   --max-pixel <n>    最坏单像素上限，默认 32
 *   --list             只列 fixture，不渲染
 *   --json             输出 JSON 摘要（给 agent 解析用）
 *
 * 退出码：0 全过；1 有 case 超预算；2 用法/fixture 有问题。
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { register } from "node:module";

register(new URL("./wgsl-export-loader.mjs", import.meta.url));

const { init } = await import("vgpu/node");
const { EffectEngine } = await import("../packages/effect-core/src/engine.ts");

const USAGE = "用法: node scripts/check-ae-parity.mjs <fixturesDir> [--effect id] [--max-mean 2] [--max-pct 2] [--over 8] [--max-pixel 32] [--list] [--json]";

// ---------------------------------------------------------------- args

const argv = process.argv.slice(2);
const opts = { maxMean: 2, maxPct: 2, over: 8, maxPixel: 32, effect: null, list: false, json: false };
const positional = [];
for (let i = 0; i < argv.length; i += 1) {
  const a = argv[i];
  if (a === "--effect") opts.effect = argv[++i];
  else if (a === "--max-mean") opts.maxMean = Number(argv[++i]);
  else if (a === "--max-pct") opts.maxPct = Number(argv[++i]);
  else if (a === "--over") opts.over = Number(argv[++i]);
  else if (a === "--max-pixel") opts.maxPixel = Number(argv[++i]);
  else if (a === "--list") opts.list = true;
  else if (a === "--json") opts.json = true;
  else if (a.startsWith("--")) fail("未知参数 " + a);
  else positional.push(a);
}
if (positional.length !== 1) fail(USAGE);
const root = path.resolve(positional[0]);
if (!existsSync(root)) fail("目录不存在: " + root);

function fail(message) {
  console.error(message);
  process.exit(2);
}

// ---------------------------------------------------------------- fixture discovery

function hasEffectJson(dir) {
  return existsSync(path.join(dir, "effect.json"));
}

// 要么这个目录本身是一个 fixture，要么往下找（最多 3 层）所有带 effect.json 的目录。
function discover(dir, depth = 0) {
  if (hasEffectJson(dir)) return [dir];
  if (depth >= 3) return [];
  const found = [];
  for (const name of readdirSync(dir).sort()) {
    if (name.startsWith(".")) continue;
    const sub = path.join(dir, name);
    if (!statSync(sub).isDirectory()) continue;
    found.push(...discover(sub, depth + 1));
  }
  return found;
}

function discoverOrFail(dir) {
  const found = discover(dir);
  if (found.length === 0) fail("这里没有 effect.json，往下三层也没找到: " + dir);
  return found;
}

function readJson(file) {
  try { return JSON.parse(readFileSync(file, "utf8")); }
  catch (e) { fail("解析失败 " + file + ": " + e.message); }
}

// AE 的输出文件名是 in_0000.raw 这种（[####] 模式，位数可能不止 4 位）
function rawFrames(caseDir, kind) {
  const out = [];
  for (const name of readdirSync(caseDir)) {
    const m = name.match(new RegExp("^" + kind + "_(\\d+)\\.raw$"));
    if (m) out.push({ frame: Number(m[1]), file: path.join(caseDir, name) });
  }
  out.sort((a, b) => a.frame - b.frame);
  return out;
}

// ---------------------------------------------------------------- metrics

function compare(got, want, over) {
  const px = got.length / 4;
  let sum = 0;
  let max = 0;
  let maxAlpha = 0;
  let overPixels = 0;
  if (got.length !== want.length) fail("像素长度不一致: got " + got.length + " want " + want.length);
  for (let i = 0; i < got.length; i += 4) {
    let pixelOver = false;
    for (let c = 0; c < 3; c += 1) {
      const d = Math.abs(got[i + c] - want[i + c]);
      sum += d;
      if (d > max) max = d;
      if (d > over) pixelOver = true;
    }
    const da = Math.abs(got[i + 3] - want[i + 3]);
    if (da > maxAlpha) maxAlpha = da;
    if (pixelOver) overPixels += 1;
  }
  return { mean: sum / (px * 3), max, maxAlpha, pctOver: (overPixels * 100) / px };
}

function numOr(value, fallback) {
  return typeof value === "number" && isFinite(value) ? value : fallback;
}

function pad(s, n) {
  s = String(s);
  return s.length >= n ? s : s + " ".repeat(n - s.length);
}
function padLeft(s, n) {
  s = String(s);
  return s.length >= n ? s : " ".repeat(n - s.length) + s;
}

// ---------------------------------------------------------------- run one fixture

async function runFixture(engine, dir) {
  const exif = readJson(path.join(dir, "effect.json"));
  const mapFile = path.join(dir, "map.json");
  if (!existsSync(mapFile)) {
    fail("缺 map.json（" + mapFile + "）。它把 AE 参数的 matchName 映射到 vgpu 的 param key，形如:\n" +
      '  { "vgpuEffect": "glow", "params": { "0001": "blur", "0002": "amount" } }\n' +
      "AE 参数清单见 effect.json 的 effect.params[].matchName。");
  }
  const map = readJson(mapFile);
  const effectId = opts.effect ?? map.vgpuEffect;
  if (!effectId) fail("map.json 里没有 vgpuEffect，也没有 --effect");

  // map.json 可以按 fixture 覆盖阈值：放宽要写在这里，别偷偷改命令行
  const budget = {
    over: numOr(map.budget && map.budget.over, opts.over),
    maxMean: numOr(map.budget && map.budget.mean, opts.maxMean),
    maxPct: numOr(map.budget && map.budget.pct, opts.maxPct),
    maxPixel: numOr(map.budget && map.budget.maxPixel, opts.maxPixel),
  };

  const width = exif.comp.width;
  const height = exif.comp.height;
  const frameDuration = exif.comp.frameDuration ?? (1 / exif.comp.frameRate);
  const def = engine.getEffect(effectId);
  const known = new Set(def.params.map((p) => p.key));

  for (const key of Object.values(map.params ?? {})) {
    if (!known.has(key)) {
      console.error("  警告: map.json 把参数映射到了 " + key + "，但 " + effectId + " 没有这个 param（已知: " + [...known].join(", ") + "）");
    }
  }

  const caseDirs = readdirSync(dir)
    .filter((n) => /^case\d+$/.test(n) && statSync(path.join(dir, n)).isDirectory())
    .sort();
  if (caseDirs.length === 0) fail("没有 caseNN 目录: " + dir);

  // 基线：case00 的参数值。凡是偏离基线的 AE 参数都必须有映射，否则这个 case 什么都没测到。
  const baseline = {};
  const firstParams = path.join(dir, caseDirs[0], "params.json");
  if (existsSync(firstParams)) {
    const p = readJson(firstParams).params ?? {};
    for (const [k, v] of Object.entries(p)) baseline[k] = v.value;
  }

  const rows = [];
  let failed = 0;
  for (const name of caseDirs) {
    const caseDir = path.join(dir, name);
    const paramsFile = path.join(caseDir, "params.json");
    if (!existsSync(paramsFile)) { console.error("  跳过 " + name + ": 没有 params.json"); continue; }
    const record = readJson(paramsFile);

    const params = {};
    const unmapped = [];
    for (const [aeKey, entry] of Object.entries(record.params ?? {})) {
      const value = entry.value;
      const vgpuKey = map.params ? map.params[aeKey] : undefined;
      if (typeof value !== "number") continue;
      if (baseline[aeKey] !== undefined && value !== baseline[aeKey] && !vgpuKey) unmapped.push(aeKey + "(" + entry.name + ")");
      if (vgpuKey) params[vgpuKey] = value;
    }
    if (unmapped.length) {
      console.error("  " + name + ": 这些参数偏离了基线却没有映射，这个 case 测不到东西: " + unmapped.join(", "));
      console.error("          在 map.json 的 params 里补上它们。");
      failed += 1;
      continue;
    }

    const ins = rawFrames(caseDir, "in");
    const outs = rawFrames(caseDir, "out");
    if (ins.length === 0 || outs.length === 0) {
      console.error("  " + name + ": 缺 in_*.raw / out_*.raw。" +
        "面板导出时勾上「同时转 raw RGBA」，或对目录里的 PNG 跑一遍 " +
        "ffmpeg -i x.png -f rawvideo -pix_fmt rgba x.raw");
      failed += 1;
      continue;
    }

    for (const inFrame of ins) {
      const outFrame = outs.find((o) => o.frame === inFrame.frame) ?? outs[0];
      const inData = new Uint8Array(readFileSync(inFrame.file));
      const want = new Uint8Array(readFileSync(outFrame.file));
      const expected = width * height * 4;
      if (inData.length !== expected) fail(name + "/" + path.basename(inFrame.file) + " 大小 " + inData.length + "，按 comp " + width + "x" + height + " 应该是 " + expected);
      const time = inFrame.frame * frameDuration;
      const result = await engine.render({
        effect: effectId,
        params,
        time,
        videoTime: time,
        videoDuration: exif.comp.duration ?? 0,
        frame: { width, height, data: inData, time },
      });
      const m = compare(result.data, want, budget.over);
      const ok = m.mean <= budget.maxMean && m.pctOver <= budget.maxPct && m.max <= budget.maxPixel;
      if (!ok) failed += 1;
      rows.push({ case: name, frame: inFrame.frame, label: record.label ?? "", ...m, ok });
    }
  }

  return {
    dir,
    effect: effectId,
    comp: exif.comp,
    budget,
    aeEffect: exif.effect.name + " [" + exif.effect.matchName + "]",
    rows,
    failed,
  };
}

// ---------------------------------------------------------------- main

const dirs = discoverOrFail(root);
if (opts.list) {
  for (const d of dirs) {
    const exif = readJson(path.join(d, "effect.json"));
    console.log(d + "  <- " + exif.effect.name + " [" + exif.effect.matchName + "]  " +
      exif.comp.width + "x" + exif.comp.height + "  " + (exif.cases ?? []).length + " cases");
  }
  process.exit(0);
}

const gpu = await init();
const engine = await EffectEngine.create({ gpu });
const results = [];
let totalFailed = 0;

for (const dir of dirs) {
  const result = await runFixture(engine, dir);
  results.push(result);
  totalFailed += result.failed;
  if (!opts.json) {
    console.log("");
    console.log(path.relative(process.cwd(), dir) + "  ->  vgpu effect '" + result.effect + "'   " +
      result.comp.width + "x" + result.comp.height + " @ " + result.comp.frameRate + "fps   AE: " + result.aeEffect);
    console.log("  预算: mean<=" + result.budget.maxMean + "  pct>" + result.budget.over + "<=" + result.budget.maxPct + "%  max<=" + result.budget.maxPixel);
    console.log("  " + pad("case", 10) + pad("frame", 7) + padLeft("mean", 9) + padLeft("max", 7) +
      padLeft("pct>" + result.budget.over, 10) + "   verdict");
    for (const row of result.rows) {
      const verdict = row.ok ? "ok" : "FAIL";
      console.log("  " + pad(row.case, 10) + pad(row.frame, 7) +
        padLeft(row.mean.toFixed(3), 9) + padLeft(row.max, 7) +
        padLeft(row.pctOver.toFixed(2) + "%", 10) + "   " + verdict +
        (row.ok ? "" : " (" + row.label + ")"));
    }
    if (result.rows.length === 0) console.log("  （没有可比较的 case）");
    let worstAlpha = 0;
    for (const row of result.rows) if (row.maxAlpha > worstAlpha) worstAlpha = row.maxAlpha;
    if (worstAlpha > 0) {
      console.log("  注意: alpha 通道最大差 " + worstAlpha + "。AE 的 PNG 带 alpha 时是预乘的，");
      console.log("        这边管线是不透明的 —— 检查 AE 侧是不是把 alpha 关掉了。");
    }
  }
}

if (opts.json) {
  console.log(JSON.stringify({ budget: opts, results }, null, 2));
} else {
  console.log("");
  console.log(totalFailed === 0
    ? "全部通过（各 fixture 的预算见上）"
    : totalFailed + " 个 case 没通过（超预算或无法比较），预算见上");
}

engine.dispose();
gpu.dispose();
process.exit(totalFailed === 0 ? 0 : 1);
