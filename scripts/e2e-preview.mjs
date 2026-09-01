import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const APP = process.env.E2E_URL ?? "http://127.0.0.1:5173/";
const PORT = 9229;

const chrome = spawn(CHROME, [
  `--remote-debugging-port=${PORT}`,
  "--headless=new",
  "--disable-gpu-sandbox",
  "--enable-unsafe-webgpu",
  "--use-angle=metal",
  "--autoplay-policy=no-user-gesture-required",
  "--user-data-dir=/tmp/vgpu-e2e-chrome",
  "about:blank",
], { stdio: ["ignore", "pipe", "pipe"] });

const errors = [];
chrome.stderr.on("data", (chunk) => {
  const text = String(chunk);
  if (/ERROR|VGPUError|CopyDst|Surface targets/i.test(text)) errors.push(text.trim());
});

try {
  const targets = await waitJson(`http://127.0.0.1:${PORT}/json/list`);
  const page = (Array.isArray(targets) ? targets : []).find((item) => item.type === "page")
    ?? await waitJson(`http://127.0.0.1:${PORT}/json/new?${encodeURIComponent("about:blank")}`);
  if (!page?.webSocketDebuggerUrl) throw new Error("no Chrome page target");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve);
    ws.addEventListener("error", reject);
  });

  let nextId = 1;
  const pending = new Map();
  const consoleErrors = [];
  ws.addEventListener("message", (event) => {
    const msg = JSON.parse(String(event.data));
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(JSON.stringify(msg.error)));
      else resolve(msg.result);
      return;
    }
    if (msg.method === "Runtime.exceptionThrown") {
      const text = msg.params.exceptionDetails?.exception?.description
        ?? msg.params.exceptionDetails?.text
        ?? "exception";
      consoleErrors.push(text);
    }
    if (msg.method === "Runtime.consoleAPICalled" && msg.params.type === "error") {
      consoleErrors.push(msg.params.args.map((arg) => arg.value ?? arg.description ?? "").join(" "));
    }
  });

  const send = (method, params = {}) => {
    const id = nextId++;
    ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  };

  await send("Runtime.enable");
  await send("Page.enable");
  await send("Page.navigate", { url: APP });
  await delay(1500);

  const result = await send("Runtime.evaluate", {
    awaitPromise: true,
    returnByValue: true,
    expression: `(${browserFlow})()`,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  }
  const value = result.result?.value;
  if (!value?.ok) throw new Error(value?.error ?? "e2e failed");

  const fatal = consoleErrors.filter((text) =>
    /VGPUError|Surface targets|CopyDst|RenderAttachment|Uncaught/i.test(text),
  );
  if (fatal.length) throw new Error(`console: ${fatal.join(" | ")}`);
  console.log(`ok e2e: ${value.status} · ${value.meta} · ${value.effects} effects`);
  ws.close();
} finally {
  chrome.kill("SIGTERM");
}

async function waitJson(url) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.json();
    } catch {
      // chrome is still booting
    }
    await delay(150);
  }
  throw new Error(`Chrome DevTools not ready (${url})`);
}

async function browserFlow() {
  const status = () => document.querySelector("#status")?.textContent ?? "";
  const waitStatus = async (re, ms = 15000) => {
    const start = Date.now();
    while (Date.now() - start < ms) {
      if (re.test(status())) return status();
      await new Promise((r) => setTimeout(r, 100));
    }
    throw new Error(`timeout waiting for ${re}: ${status()}`);
  };

  await waitStatus(/WebGPU 就绪|特效：/);
  const sample = document.querySelector("#sample-btn");
  if (!(sample instanceof HTMLButtonElement)) throw new Error("missing sample button");
  sample.click();
  const loaded = await waitStatus(/视频已加载|示例视频加载失败|无法解码|视频加载超时/);
  if (!/视频已加载/.test(loaded)) {
    const video = document.querySelector("video");
    throw new Error(`${loaded} · readyState=${video?.readyState} · err=${video?.error?.message ?? ""}`);
  }

  const buttons = [...document.querySelectorAll(".effect-item")];
  if (buttons.length < 2) throw new Error("effect list empty");
  for (const btn of buttons) {
    btn.click();
    await new Promise((r) => setTimeout(r, 80));
  }

  const play = document.querySelector("#play-btn");
  if (!(play instanceof HTMLButtonElement) || play.disabled) throw new Error("play disabled");
  play.click();
  await new Promise((r) => setTimeout(r, 400));
  if (play.textContent !== "暂停") throw new Error(`play did not start: ${play.textContent}`);
  play.click();

  return {
    ok: true,
    status: status(),
    meta: document.querySelector("#video-meta")?.textContent ?? "",
    effects: buttons.length,
  };
}
