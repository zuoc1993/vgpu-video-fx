// Drive a real headless Chrome via CDP to measure the web preview fps.
// Usage: node scripts/browser-perf.mjs [seconds-per-sample]
import { spawn } from "node:child_process";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const APP = "http://127.0.0.1:5173";
const PORT = 9223;
const SAMPLE_S = Number(process.argv[2] || 5);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class CDP {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id && this.pending.has(m.id)) {
        this.pending.get(m.id)(m);
        this.pending.delete(m.id);
      }
    };
  }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((res) => this.pending.set(id, res));
  }
  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
    return new CDP(ws);
  }
}

async function targetWs() {
  for (let i = 0; i < 40; i += 1) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json/list`);
      const list = await res.json();
      const page = list.find((t) => t.type === "page" && t.url.startsWith(APP));
      if (page) return page.webSocketDebuggerUrl;
    } catch { /* chrome still booting */ }
    await sleep(500);
  }
  throw new Error("no CDP page target");
}

const chrome = spawn(CHROME, [
  "--headless=new",
  `--remote-debugging-port=${PORT}`,
  "--no-first-run",
  "--autoplay-policy=no-user-gesture-required",
  "--user-data-dir=/tmp/vgpu-chrome-prof",
  "--window-size=1600,900",
  "--force-device-scale-factor=2",
  "--hide-scrollbars",
  APP,
], { stdio: "ignore" });

try {
  const cdp = await CDP.connect(await targetWs());
  await cdp.send("Runtime.enable");
  const evalJs = async (expression) => {
    const r = await cdp.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails));
    return r.result?.result?.value;
  };

  const logs = [];
  cdp.ws.addEventListener("message", (ev) => {
    const m = JSON.parse(ev.data);
    if (m.method === "Runtime.exceptionThrown") logs.push("EXC: " + JSON.stringify(m.params.exceptionDetails?.text || m.params));
    if (m.method === "Runtime.consoleAPICalled") {
      const text = m.params.args.map((a) => a.value ?? a.description).join(" ");
      if (["error", "warning"].includes(m.params.type) || text.startsWith("rs-timing")) {
        logs.push("CONSOLE: " + text);
      }
    }
  });
  await cdp.send("Runtime.enable");

  const waitFor = async (expression, what) => {
    for (let i = 0; i < 60; i += 1) {
      const v = await evalJs(expression);
      if (v) return v;
      await sleep(500);
    }
    throw new Error("timeout waiting for " + what);
  };
  await waitFor(`(() => { const b = document.querySelector('#sample-btn'); return b ? 'ready' : ''; })()`, "#sample-btn");
  await sleep(1500);
  console.log("status:", await evalJs(`document.querySelector('#status')?.textContent`));
  console.log("backends disabled:", await evalJs(`document.querySelector('#backend-select')?.disabled`));

  // load sample video
  await evalJs(`document.querySelector('#sample-btn').click(); 'clicked'`);
  await sleep(4000);
  console.log("video-meta:", await evalJs(`document.querySelector('#video-meta')?.textContent`));
  console.log("status-after-sample:", await evalJs(`document.querySelector('#status')?.textContent`));
  console.log("video-ready:", await evalJs(`(() => { const v = document.querySelector('video'); return v ? [v.readyState, v.videoWidth, v.videoHeight, v.error?.message] : 'no video el'; })()`));
  if (logs.length) console.log(logs.join("\n"));

  const setBackend = async (kind) => {
    await evalJs(`(() => {
      const sel = document.querySelector('#backend-select');
      sel.value = '${kind}';
      sel.dispatchEvent(new Event('change'));
      return sel.value;
    })()`);
    await sleep(500);
    await evalJs(`(() => {
      const btn = [...document.querySelectorAll('#effect-list button')].find((b) => b.textContent.includes('Glitch'));
      btn?.click();
      return btn?.textContent ?? 'no-glitch';
    })()`);
    await sleep(500);
  };
  const play = async () => {
    await evalJs(`(() => {
      const b = document.querySelector('#play-btn');
      if (b && !b.disabled) b.click();
      return b?.textContent ?? 'none';
    })()`);
  };
  const readFps = async (label) => {
    await sleep(SAMPLE_S * 1000);
    const fps = await evalJs(`document.querySelector('#fps')?.textContent`);
    const status = await evalJs(`document.querySelector('#status')?.textContent`);
    console.log(`${label}: fps=${fps} status=${status}`);
  };

  console.log("dpr:", await evalJs(`window.devicePixelRatio`));
  console.log("canvas backing:", await evalJs(`(() => { const c = document.querySelector('#preview-cpu'); return [c.width, c.height]; })()`));

  await setBackend("webgpu");
  await play();
  await readFps("webgpu/glitch");
  await play(); // pause

  await setBackend("rs");
  await evalJs(`window.__RS_TIMING = true; 'on'`);
  await play();
  const rsTiming = logs.filter((l) => l.startsWith("CONSOLE: rs-timing")).slice(-3);
  console.log(rsTiming.join("\n"));
  console.log("canvas-after-render:", await evalJs(`(() => { const c = document.querySelector('#preview-cpu'); return [c.width, c.height, c.clientWidth, c.clientHeight]; })()`));

  // sweep all rs effects (already playing; just switch effect and read fps)
  const rsCatalog = await evalJs(`window.__rs ?? [...document.querySelectorAll('#effect-list button')].map((b) => b.textContent.trim()).filter((t) => t.includes('·')).map((t) => t.split('·')[0])`);
  const names = ["原片", "Posterize", "Rgb split0r", "Glitch", "Glow"];
  for (const name of names) {
    await evalJs(`(() => {
      const btn = [...document.querySelectorAll('#effect-list button')].find((b) => b.textContent.includes('${name}'));
      btn?.click();
      return btn?.textContent ?? 'missing';
    })()`);
    await sleep(400);
    await readFps("rs/" + name);
  }

  console.log("done");
} finally {
  chrome.kill();
}
