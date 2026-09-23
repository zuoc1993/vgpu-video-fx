/**
 * AE Fixture Export - After Effects ScriptUI panel
 * ============================================================================
 * 把一个 AE 特效导出成「可移植的实验包」：元数据 JSON + 配对的输入/输出帧。
 * 目的是让 coding agent 能照着写 WGSL，并用数值 diff 验证（mean / max / pct>2）。
 *
 * 安装（面板会出现在 Window 菜单底部）：
 *   macOS: ~/Library/Preferences/Adobe/After Effects/<版本>/Scripts/ScriptUI Panels/
 *   Win:   %APPDATA%\Adobe\After Effects\<版本>\Scripts\ScriptUI Panels\
 *   （<版本> 目录在 AE 第一次启动后才会生成）
 *
 * 前置条件：
 *   Preferences > General > "Allow Scripts To Write Files And Access Network" 必须勾上，
 *   否则写文件会静默失败。
 *
 * 输出结构：
 *   <OUT>/effect.json          元数据 + 用例清单
 *   <OUT>/export.log           运行日志（面板停靠时 UI 可能不刷新，看这个文件）
 *   <OUT>/case00/params.json   这一组参数值 + 实际渲出的帧号
 *   <OUT>/case00/in_0000.png   特效关闭时的画面 = 特效真正的输入
 *   <OUT>/case00/out_0000.png  特效打开时的画面 = 期望输出
 *   <OUT>/case00/in_0000.raw   紧凑 RGBA8（可选，给 engine.render() 直接吃）
 *
 * 注意：ExtendScript 是 ES3。不要用 let/const、箭头函数、模板字符串、
 * Array.map/forEach/indexOf、JSON。这个文件刻意保持 ES3 风格。
 */

var APP_TITLE = "AE Fixture Export";
var EXPORTER_VERSION = "0.1.0";
var SCHEMA_VERSION = 1;
var MAX_CASES = 40;
var DEFAULT_FFMPEG = "/opt/homebrew/bin/ffmpeg";

// ---------------------------------------------------------------- JSON (ES3)
// ExtendScript 的 JSON 支持在各版本上不一致，自己写一个，行为确定。

function jsonEscape(s) {
  s = String(s);
  var out = "";
  for (var i = 0; i < s.length; i += 1) {
    var c = s.charAt(i);
    var code = s.charCodeAt(i);
    if (c === '"') out += '\\"';
    else if (c === "\\") out += "\\\\";
    else if (c === "\n") out += "\\n";
    else if (c === "\r") out += "\\r";
    else if (c === "\t") out += "\\t";
    else if (code < 32) {
      var hex = code.toString(16);
      while (hex.length < 4) hex = "0" + hex;
      out += "\\u" + hex;
    } else out += c;
  }
  return out;
}

function jsonWrite(v, indent, pad) {
  if (v === null || typeof v === "undefined") return "null";
  var t = typeof v;
  if (t === "number") return isFinite(v) ? String(v) : "null";
  if (t === "boolean") return v ? "true" : "false";
  if (t === "string") return '"' + jsonEscape(v) + '"';
  var nl = indent ? "\n" : "";
  var inner = pad + (indent ? indent : "");
  if (v instanceof Array) {
    if (v.length === 0) return "[]";
    var items = [];
    for (var i = 0; i < v.length; i += 1) items.push(inner + jsonWrite(v[i], indent, inner));
    return "[" + nl + items.join("," + nl) + nl + pad + "]";
  }
  var keys = [];
  for (var k in v) {
    if (v.hasOwnProperty(k) && typeof v[k] !== "undefined") keys.push(k);
  }
  if (keys.length === 0) return "{}";
  var pairs = [];
  for (var j = 0; j < keys.length; j += 1) {
    pairs.push(inner + '"' + jsonEscape(keys[j]) + '": ' + jsonWrite(v[keys[j]], indent, inner));
  }
  return "{" + nl + pairs.join("," + nl) + nl + pad + "}";
}

function toJson(v) {
  return jsonWrite(v, "  ", "");
}

// ----------------------------------------------------------------- utilities

function trim(s) {
  s = String(s);
  var a = 0;
  var b = s.length;
  while (a < b && s.charCodeAt(a) <= 32) a += 1;
  while (b > a && s.charCodeAt(b - 1) <= 32) b -= 1;
  return s.substring(a, b);
}

function round6(v) {
  if (typeof v !== "number" || !isFinite(v)) return null;
  return Math.round(v * 1000000) / 1000000;
}

function cloneMap(m) {
  var out = {};
  for (var k in m) if (m.hasOwnProperty(k)) out[k] = m[k];
  return out;
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n;
}

function stamp() {
  var d = new Date();
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) +
    " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
}

// ------------------------------------------------------------------ files

function ensureFolder(folder) {
  if (!folder.exists) folder.create();
  return folder;
}

function writeText(file, text) {
  file.encoding = "UTF-8";
  file.open("w");
  file.write(text);
  file.close();
}

function baseName(fileName, ext) {
  if (fileName.length > ext.length && fileName.substring(fileName.length - ext.length).toLowerCase() === ext) {
    return fileName.substring(0, fileName.length - ext.length);
  }
  return fileName;
}

// ------------------------------------------------------- property inspection

var VALUE_TYPE_KEYS = ["OneD", "TwoD", "ThreeD", "COLOR", "LAB", "NO_VALUE", "CUSTOM_VALUE", "MARKER", "SHAPE", "TEXT_DOCUMENT"];
var INTERP_KEYS = ["LINEAR", "BEZIER", "HOLD"];

function valueTypeName(v) {
  for (var i = 0; i < VALUE_TYPE_KEYS.length; i += 1) {
    var name = VALUE_TYPE_KEYS[i];
    try {
      if (v === PropertyValueType[name]) return name;
    } catch (e) { /* enum member missing in this AE version */ }
  }
  return "UNKNOWN";
}

function interpName(v) {
  for (var i = 0; i < INTERP_KEYS.length; i += 1) {
    var name = INTERP_KEYS[i];
    try {
      if (v === KeyframeInterpolationType[name]) return name;
    } catch (e) { /* ignore */ }
  }
  return "UNKNOWN";
}

function safe(fn, fallback) {
  try { return fn(); } catch (e) { return fallback; }
}

function readParam(prop, index) {
  var info = {
    index: index,
    name: safe(function () { return prop.name; }, ""),
    matchName: safe(function () { return prop.matchName; }, ""),
    valueType: valueTypeName(safe(function () { return prop.propertyValueType; }, null)),
    readable: false,
    value: null,
    min: null,
    max: null,
    animated: false,
    numKeys: 0,
    keys: [],
    expression: "",
    expressionEnabled: false,
    sweepable: false
  };
  var v = safe(function () { return prop.value; }, undefined);
  if (typeof v !== "undefined" && v !== null) {
    info.readable = true;
    info.value = (v instanceof Array) ? v : round6(v);
  }
  info.min = safe(function () { var m = prop.minValue; return (typeof m === "number" && isFinite(m)) ? round6(m) : null; }, null);
  info.max = safe(function () { var m = prop.maxValue; return (typeof m === "number" && isFinite(m)) ? round6(m) : null; }, null);
  info.numKeys = safe(function () { return prop.numKeys; }, 0);
  info.animated = safe(function () { return prop.isTimeVarying; }, false) === true && info.numKeys > 0;
  info.expressionEnabled = safe(function () { return prop.expressionEnabled; }, false) === true;
  info.expression = safe(function () { return prop.expression; }, "");
  if (info.numKeys > 0) {
    var limit = Math.min(info.numKeys, 200);
    for (var k = 1; k <= limit; k += 1) {
      var kv = safe(function () { return prop.keyValue(k); }, null);
      info.keys.push({
        time: safe(function () { return round6(prop.keyTime(k)); }, null),
        value: (kv instanceof Array) ? kv : round6(kv),
        inType: interpName(safe(function () { return prop.keyInInterpolationType(k); }, null)),
        outType: interpName(safe(function () { return prop.keyOutInterpolationType(k); }, null))
      });
    }
  }
  // 只有「一维 + 可读 + 有有限范围 + 无关键帧」的参数才进扫描网格。
  // 有关键帧的参数 setValue 会被 AE 忽略，静默扫出 27 组一样的图。
  info.sweepable = (info.valueType === "OneD") && info.readable && typeof info.value === "number" &&
    info.min !== null && info.max !== null && info.numKeys === 0 && !info.expressionEnabled;
  return info;
}

function readEffect(comp, layerIndex, fxIndex) {
  var layer = comp.layer(layerIndex);
  var parade = safe(function () { return layer.property("ADBE Effect Parade"); }, null);
  if (!parade) return null;
  var fx = parade.property(fxIndex);
  if (!fx) return null;
  var params = [];
  var n = safe(function () { return fx.numProperties; }, 0);
  for (var i = 1; i <= n; i += 1) {
    params.push(readParam(fx.property(i), i));
  }
  return {
    layerIndex: layerIndex,
    layerName: safe(function () { return layer.name; }, ""),
    fxIndex: fxIndex,
    fx: fx,
    name: safe(function () { return fx.name; }, ""),
    matchName: safe(function () { return fx.matchName; }, ""),
    enabled: safe(function () { return fx.enabled; }, true) === true,
    params: params
  };
}

function listEffects(comp) {
  var out = [];
  for (var li = 1; li <= comp.numLayers; li += 1) {
    var layer = comp.layer(li);
    var parade = safe(function () { return layer.property("ADBE Effect Parade"); }, null);
    if (!parade) continue;
    var n = safe(function () { return parade.numProperties; }, 0);
    for (var ei = 1; ei <= n; ei += 1) {
      out.push({ layerIndex: li, fxIndex: ei, label: layer.name + " / " + safe(function () { return parade.property(ei).name; }, "?") });
    }
  }
  return out;
}

// -------------------------------------------------------------- case grid

function buildCases(params, withExtremes) {
  var defaults = {};
  var sweepable = [];
  var skipped = [];
  for (var i = 0; i < params.length; i += 1) {
    var p = params[i];
    if (p.sweepable) {
      defaults[p.matchName] = p.value;
      sweepable.push(p);
    } else if (p.valueType === "OneD" && p.numKeys > 0) {
      skipped.push(p.name + "（有关键帧）");
    } else if (p.valueType === "OneD" && p.expressionEnabled) {
      skipped.push(p.name + "（有表达式）");
    } else if (p.valueType !== "OneD" && p.readable) {
      skipped.push(p.name + "（" + p.valueType + "）");
    }
  }
  var cases = [];
  cases.push({ id: "case00", label: "全部默认值", params: cloneMap(defaults) });
  for (var j = 0; j < sweepable.length; j += 1) {
    var q = sweepable[j];
    var lo = cloneMap(defaults);
    lo[q.matchName] = q.min;
    cases.push({ id: "", label: q.name + " = min", params: lo });
    var hi = cloneMap(defaults);
    hi[q.matchName] = q.max;
    cases.push({ id: "", label: q.name + " = max", params: hi });
  }
  if (withExtremes && sweepable.length > 0) {
    var allMin = cloneMap(defaults);
    var allMax = cloneMap(defaults);
    for (var m = 0; m < sweepable.length; m += 1) {
      allMin[sweepable[m].matchName] = sweepable[m].min;
      allMax[sweepable[m].matchName] = sweepable[m].max;
    }
    cases.push({ id: "", label: "全部 = min", params: allMin });
    cases.push({ id: "", label: "全部 = max", params: allMax });
  }
  var kept = [];
  for (var c = 0; c < cases.length && kept.length < MAX_CASES; c += 1) {
    cases[c].id = "case" + (kept.length < 10 ? "0" : "") + kept.length;
    kept.push(cases[c]);
  }
  return { cases: kept, defaults: defaults, sweepable: sweepable, skipped: skipped, truncated: cases.length > kept.length };
}

// ------------------------------------------------------------- rendering

// 从可用模板里挑一个 PNG 模板：先精确匹配，再退回「名字里带 png 的」。
function applyPngTemplate(om, wanted) {
  var names = safe(function () { return om.templates; }, []) || [];
  var pick = "";
  var i;
  for (i = 0; i < names.length; i += 1) if (names[i] === wanted) pick = names[i];
  if (!pick) for (i = 0; i < names.length; i += 1) if (/png/i.test(names[i])) { pick = names[i]; break; }
  if (!pick) pick = wanted;
  om.applyTemplate(pick);
  return pick;
}

// 把用户本来就排好队的条目先按下去，只让我们新加的这条进入渲染。
function quietQueue(rq, upTo, log) {
  for (var i = 1; i <= upTo && i <= rq.numItems; i += 1) {
    try { rq.items[i].render = false; } catch (e) { log("  ! 无法取消排队 item " + i + ": " + e); }
  }
}

function renderOneFrame(comp, fx, enabled, outFile, frame, templateName, preCount, log) {
  var rq = app.project.renderQueue;
  fx.enabled = enabled;
  var item = rq.items.add(comp);
  var fd = comp.frameDuration;
  item.timeSpanStart = frame * fd;
  item.timeSpanDuration = fd;
  var om = item.outputModule(1);
  om.file = outFile;
  var used = applyPngTemplate(om, templateName);
  quietQueue(rq, preCount, log);
  rq.render();
  try { item.render = false; } catch (e) { /* 老版本没有这个 setter 就随它去 */ }
  return used;
}

function convertToRaw(folder, ffmpeg, log) {
  var files = folder.getFiles("*.png");
  var made = 0;
  for (var i = 0; i < files.length; i += 1) {
    var png = files[i];
    var raw = new File(folder.fsName + "/" + baseName(png.name, ".png") + ".raw");
    var cmd = '"' + ffmpeg + '" -y -v error -i "' + png.fsName + '" -f rawvideo -pix_fmt rgba "' + raw.fsName + '"';
    system.callSystem(cmd);
    if (raw.exists && raw.length > 0) made += 1;
    else log("  ! ffmpeg 转换失败：" + png.name + "（检查 ffmpeg 路径）");
  }
  return made;
}

// ------------------------------------------------------------------- export

function runExport(state, mode) {
  var log = state.log;
  log.length = 0;
  function say(line) { log.push(line); refreshUI(state); }

  var comp = app.project ? app.project.activeItem : null;
  if (!comp || !(comp instanceof CompItem)) {
    say("请先在时间轴里激活一个合成，然后点「刷新」。");
    return;
  }
  var sel = state.ddl.selection;
  var pick = (state.effects.length > 0 && sel) ? state.effects[sel.index] : null;
  if (!pick) {
    say("这个合成里没有找到任何特效。");
    return;
  }

  var outRoot = new Folder(trim(state.outField.text));
  if (!outRoot) { say("输出目录无效。"); return; }
  ensureFolder(outRoot);

  var info = readEffect(comp, pick.layerIndex, pick.fxIndex);
  if (!info) { say("读取特效失败。"); return; }

  var templateName = trim(state.templateField.text) || "PNG Sequence";
  var grid = buildCases(info.params, state.extremes.value === true);
  var frames = parseFrames(state.framesField.text, comp);
  if (frames.length === 0) { say("帧号无法解析，示例：0 或 0,12,30"); return; }

  say(APP_TITLE + " v" + EXPORTER_VERSION + " @ " + stamp());
  say("合成: " + comp.name + "  " + comp.width + "x" + comp.height +
      "  " + comp.frameRate + "fps  " + round6(comp.duration) + "s");
  say("特效: " + info.name + "  [" + info.matchName + "]  在图层 " + info.layerName);
  say("项目位深: " + safe(function () { return app.project.bitsPerChannel; }, "?") + " bpc" +
      (safe(function () { return app.project.bitsPerChannel; }, 8) === 8 ? "" : "  <-- 建议 8 bpc，否则和 vgpu 的 RGBA8 管线对不上"));
  say("可扫描参数: " + grid.sweepable.length + "，用例: " + grid.cases.length + "，帧: " + frames.join(","));
  if (grid.skipped.length) say("跳过（不扫描）: " + grid.skipped.join("；"));
  if (grid.truncated) say("用例数超过上限 " + MAX_CASES + "，已截断。");

  // 快照，结束后原样还原
  var snapshot = [];
  for (var i = 0; i < info.params.length; i += 1) {
    var p = info.params[i];
    if (p.readable) snapshot.push({ prop: info.fx.property(p.index), value: p.value });
  }
  var wasEnabled = info.enabled;

  var rq = app.project.renderQueue;
  var preCount = rq.numItems;
  var savedQueued = [];
  for (var q = 1; q <= preCount; q += 1) {
    savedQueued.push(safe(function () { return rq.items[q].render; }, false));
    try { rq.items[q].render = false; } catch (e) { /* ignore */ }
  }

  var exif = {
    schemaVersion: SCHEMA_VERSION,
    exporter: APP_TITLE + " " + EXPORTER_VERSION,
    generatedAt: stamp(),
    aeVersion: safe(function () { return app.version; }, ""),
    projectFile: safe(function () { return app.project.file ? app.project.file.fsName : null; }, null),
    projectBitsPerChannel: safe(function () { return app.project.bitsPerChannel; }, null),
    comp: {
      name: comp.name,
      width: comp.width,
      height: comp.height,
      frameRate: comp.frameRate,
      frameDuration: round6(comp.frameDuration),
      duration: round6(comp.duration),
      pixelAspect: round6(safe(function () { return comp.pixelAspect; }, 1))
    },
    layer: { index: info.layerIndex, name: info.layerName },
    effect: {
      name: info.name,
      matchName: info.matchName,
      enabled: info.enabled,
      numParams: info.params.length,
      params: info.params
    },
    sampling: {
      frames: frames,
      strategy: state.extremes.value === true ? "default + per-param min/max + all-min/all-max" : "default + per-param min/max",
      note: "params 的 key 是 AE 参数的 matchName（稳定，不随语言变）"
    },
    cases: []
  };

  app.beginUndoGroup(APP_TITLE);
  try {
    say(mode === "full" ? "开始导出元数据 + 帧…" : "只导出元数据，不渲染…");

    for (var c = 0; c < grid.cases.length; c += 1) {
      var kase = grid.cases[c];
      var caseDir = ensureFolder(new Folder(outRoot.fsName + "/" + kase.id));
      var applied = applyCase(info, kase.params);
      var rec = { id: kase.id, label: kase.label, params: applied, frames: [] };

      if (mode === "full") {
        for (var f = 0; f < frames.length; f += 1) {
          var fr = frames[f];
          var usedTemplate = renderOneFrame(comp, info.fx, false, new File(caseDir.fsName + "/in_[####].png"), fr, templateName, preCount, say);
          renderOneFrame(comp, info.fx, true, new File(caseDir.fsName + "/out_[####].png"), fr, templateName, preCount, say);
          if (c === 0 && f === 0) say("  输出模块模板: " + usedTemplate);
          rec.frames.push(fr);
        }
        info.fx.enabled = wasEnabled;
        var pngs = caseDir.getFiles("*.png");
        if (pngs.length === 0) {
          say("  ! " + kase.id + " 没有产生任何 PNG —— 十有八九是输出模块模板不对。");
          say("    当前用的模板名：'" + state.templateField.text + "'。面板里换一个再试。");
        } else {
          say("  " + kase.id + "  " + kase.label + "  -> " + pngs.length + " 个 PNG");
          if (state.rawBox.value === true) convertToRaw(caseDir, trim(state.ffmpegField.text) || DEFAULT_FFMPEG, say);
        }
      }
      writeText(new File(caseDir.fsName + "/params.json"), toJson(rec));
      exif.cases.push(rec);
      writeText(new File(outRoot.fsName + "/export.log"), log.join("\n"));
    }
  } finally {
    // 还原用户工程
    for (var s = 0; s < snapshot.length; s += 1) {
      try { snapshot[s].prop.setValue(snapshot[s].value); } catch (e) { /* ignore */ }
    }
    try { info.fx.enabled = wasEnabled; } catch (e) { /* ignore */ }
    for (var b = 1; b <= preCount && b <= rq.numItems; b += 1) {
      try { rq.items[b].render = savedQueued[b - 1]; } catch (e) { /* ignore */ }
    }
    app.endUndoGroup();
  }

  exif.renderedFrames = mode === "full";
  writeText(new File(outRoot.fsName + "/effect.json"), toJson(exif));
  writeText(new File(outRoot.fsName + "/export.log"), log.join("\n"));

  say("");
  say("完成 -> " + outRoot.fsName);
  say("  effect.json + " + exif.cases.length + " 个 case 目录");
  var leftover = rq.numItems - preCount;
  if (leftover > 0) {
    say("  渲染队列里多了 " + leftover + " 个条目：AE 脚本 API 不支持删除渲染队列项（RQItemCollection 只有 add），");
    say("  已在渲染时把它们置为未排队，不会影响你之后渲染。介意的话在渲染队列面板里手动全选删掉。");
  }
  say("  面板停靠时日志可能不刷新 —— 完整日志在上面那个 export.log 里。");
}

function applyCase(info, values) {
  var applied = {};
  for (var i = 0; i < info.params.length; i += 1) {
    var p = info.params[i];
    if (!values.hasOwnProperty(p.matchName)) continue;
    var v = values[p.matchName];
    try {
      info.fx.property(p.index).setValue(v);
      applied[p.matchName] = { name: p.name, value: v };
    } catch (e) {
      applied[p.matchName] = { name: p.name, value: v, error: String(e) };
    }
  }
  return applied;
}

function parseFrames(text, comp) {
  var parts = trim(text).split(",");
  var out = [];
  var last = Math.max(0, Math.round(comp.duration * comp.frameRate) - 1);
  for (var i = 0; i < parts.length; i += 1) {
    var s = trim(parts[i]);
    if (s === "") continue;
    var n = parseInt(s, 10);
    if (isNaN(n)) continue;
    if (n < 0) n = 0;
    if (n > last) n = last;
    out.push(n);
  }
  return out;
}

// ----------------------------------------------------------------------- UI

function refreshUI(state) {
  try { if (state.logBox) state.logBox.text = state.log.join("\n"); } catch (e) { /* ignore */ }
  try { if (state.pal.update) state.pal.update(); } catch (e) { /* dockable Panel 没有 update */ }
}

function label(parent, text, width) {
  var t = parent.add("statictext", undefined, text);
  if (width) t.preferredSize.width = width;
  return t;
}

function buildUI(thisObj) {
  var pal = (thisObj instanceof Panel) ? thisObj : new Window("palette", APP_TITLE, undefined, { resizeable: true });
  pal.orientation = "column";
  pal.alignChildren = "fill";
  pal.margins = 10;
  pal.spacing = 6;

  var state = {
    pal: pal,
    log: [],
    effects: [],
    outField: null,
    framesField: null,
    ffmpegField: null,
    templateField: null,
    ddl: null,
    logBox: null,
    rawBox: null,
    extremes: null
  };

  // --- 合成 / 效果
  var g1 = pal.add("group");
  g1.orientation = "column";
  g1.alignChildren = "fill";
  var r1 = g1.add("group");
  r1.alignment = ["fill", "top"];
  r1.add("statictext", undefined, "合成:");
  var compText = r1.add("statictext", undefined, "（未激活）");
  compText.alignment = ["fill", "center"];
  var refreshBtn = r1.add("button", undefined, "刷新");
  refreshBtn.preferredSize.width = 60;

  var r2 = g1.add("group");
  r2.alignment = ["fill", "top"];
  r2.add("statictext", undefined, "特效:");
  var ddl = r2.add("dropdownlist", undefined, []);
  ddl.alignment = ["fill", "center"];
  state.ddl = ddl;

  // --- 输出
  var r3 = pal.add("group");
  r3.alignment = ["fill", "top"];
  r3.add("statictext", undefined, "输出:");
  var outField = r3.add("edittext", undefined, defaultOutPath());
  outField.alignment = ["fill", "center"];
  state.outField = outField;
  var pickBtn = r3.add("button", undefined, "选择");
  pickBtn.preferredSize.width = 60;

  var r4 = pal.add("group");
  r4.alignment = ["fill", "top"];
  label(r4, "帧:", 36);
  var framesField = r4.add("edittext", undefined, "0");
  framesField.preferredSize.width = 80;
  state.framesField = framesField;
  label(r4, "输出模块模板:", 90);
  var templateField = r4.add("edittext", undefined, "PNG Sequence");
  templateField.alignment = ["fill", "center"];
  state.templateField = templateField;

  var r5 = pal.add("group");
  r5.alignment = ["fill", "top"];
  label(r5, "ffmpeg:", 52);
  var ffmpegField = r5.add("edittext", undefined, DEFAULT_FFMPEG);
  ffmpegField.alignment = ["fill", "center"];
  state.ffmpegField = ffmpegField;

  var r6 = pal.add("group");
  r6.alignment = ["left", "top"];
  var rawBox = r6.add("checkbox", undefined, "同时转 raw RGBA");
  rawBox.value = true;
  state.rawBox = rawBox;
  var extremes = r6.add("checkbox", undefined, "含全 min / 全 max");
  extremes.value = false;
  state.extremes = extremes;

  // --- 动作
  var r7 = pal.add("group");
  r7.alignment = ["fill", "top"];
  var metaBtn = r7.add("button", undefined, "仅导出元数据");
  var fullBtn = r7.add("button", undefined, "导出元数据 + 帧");

  // --- 日志
  var logBox = pal.add("edittext", undefined, "", { multiline: true, readonly: true, scrolling: true });
  logBox.alignment = ["fill", "fill"];
  logBox.minimumSize.height = 160;
  state.logBox = logBox;

  pal.alignment = "fill";

  // --- 行为
  function rescan() {
    var comp = app.project ? app.project.activeItem : null;
    state.effects = [];
    while (ddl.items.length > 0) ddl.remove(ddl.items[0]);
    if (!comp || !(comp instanceof CompItem)) {
      compText.text = "（未激活）";
      state.log = ["请先在时间轴里激活一个合成。"];
      refreshUI(state);
      return;
    }
    compText.text = comp.name + "  " + comp.width + "x" + comp.height + "  " + comp.frameRate + "fps";
    state.effects = listEffects(comp);
    for (var i = 0; i < state.effects.length; i += 1) ddl.add("item", state.effects[i].label);
    if (state.effects.length === 0) {
      state.log = ["这个合成里没有特效。给某个图层加一个效果，再点刷新。"];
    } else {
      ddl.selection = 0;
      state.log = ["找到 " + state.effects.length + " 个特效。选一个，填输出目录，然后导出。"];
    }
    refreshUI(state);
  }

  refreshBtn.onClick = rescan;
  pickBtn.onClick = function () {
    var f = Folder.selectDialog("选择输出目录");
    if (f) outField.text = f.fsName;
  };
  metaBtn.onClick = function () { runExport(state, "meta"); };
  fullBtn.onClick = function () { runExport(state, "full"); };

  refreshUI(state);
  rescan();

  pal.layout.layout(true);
  pal.layout.resize();
  pal.onResizing = pal.onResize = function () { this.layout.resize(); };

  if (pal instanceof Window) {
    pal.center();
    pal.show();
  }
  return pal;
}

function defaultOutPath() {
  var base = null;
  try { if (app.project && app.project.file) base = app.project.file.parent; } catch (e) { base = null; }
  if (!base) base = Folder.desktop;
  return base.fsName + "/ae-fixtures";
}

buildUI(this);
