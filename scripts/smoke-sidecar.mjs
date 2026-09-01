import { spawn, spawnSync } from "node:child_process";
import { createConnection } from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { encodeMessage, parseRequest, pixelBytes } from "../packages/sidecar/src/protocol.ts";
import { sockReader } from "../packages/sidecar/src/read.ts";

const root = path.join(fileURLToPath(new URL(".", import.meta.url)), "..");
const sockPath = process.env.VGPU_FX_SOCK || "/tmp/vgpu-fx-smoke.sock";

const child = spawn(process.execPath, ["src/start.mjs"], {
  cwd: path.join(root, "packages/sidecar"),
  env: { ...process.env, VGPU_FX_SOCK: sockPath },
  stdio: ["ignore", "pipe", "pipe"],
});

let ready = false;
const onLine = (buf) => {
  const text = String(buf);
  if (text.includes("listening")) ready = true;
};
child.stdout.on("data", onLine);
child.stderr.on("data", onLine);

try {
  const deadline = Date.now() + 20_000;
  while (!ready) {
    if (Date.now() > deadline || child.exitCode !== null) throw new Error("sidecar did not start");
    await delay(50);
  }

  const w = 8;
  const h = 8;
  const pixel = Buffer.alloc(w * h * 4);
  for (let i = 0; i < pixel.length; i += 4) {
    pixel[i] = 40;
    pixel[i + 1] = 80;
    pixel[i + 2] = 120;
    pixel[i + 3] = 255;
  }

  const one = await roundtrip({
    id: "1",
    effect: "none",
    width: w,
    height: h,
    count: 1,
    times: [0],
  }, pixel);
  assertNear(one, pixel, "none identity");

  const two = await roundtrip({
    id: "2",
    effect: "none",
    width: w,
    height: h,
    count: 2,
    times: [0, 0.1],
  }, Buffer.concat([pixel, pixel]));
  if (two.length !== pixel.length * 2) throw new Error("batch size");

  const boom = await roundtripRaw({
    id: "3",
    effect: "no-such-fx",
    width: w,
    height: h,
    count: 1,
    times: [0],
  }, pixel);
  if (boom.header.ok) throw new Error("expected unknown effect");

  parseRequest({
    id: "x",
    effect: "glitch",
    width: 2,
    height: 2,
    count: 1,
    times: [0],
  });
  if (pixelBytes(2, 2, 3) !== 2 * 2 * 3 * 4) throw new Error("pixelBytes");

  const py = spawnSync("uv", ["run", "--no-dev", "--no-default-groups", "python", "test_client.py"], {
    cwd: path.join(root, "bmf-demo"),
    env: { ...process.env, VGPU_FX_SOCK: sockPath },
    encoding: "utf8",
  });
  if (py.status !== 0) {
    console.error(py.stdout);
    console.error(py.stderr);
    throw new Error("python client failed");
  }
  console.log(py.stdout.trim());
  console.log("ok smoke-sidecar");
} finally {
  child.kill("SIGTERM");
}

function assertNear(actual, expected, label) {
  let max = 0;
  for (let i = 0; i < expected.length; i += 1) {
    const delta = Math.abs(actual[i] - expected[i]);
    if (delta > max) max = delta;
  }
  if (max > 2) throw new Error(`${label}: maxByte ${max}`);
}

function connect() {
  return new Promise((resolve, reject) => {
    const socket = createConnection({ path: sockPath });
    socket.once("connect", () => resolve(socket));
    socket.once("error", reject);
  });
}

async function roundtrip(header, pixels) {
  const { header: reply, pixels: out } = await roundtripRaw(header, pixels);
  if (!reply.ok) throw new Error(reply.error || "sidecar error");
  return out;
}

async function roundtripRaw(header, pixels) {
  const socket = await connect();
  const reader = sockReader(socket);
  socket.write(encodeMessage(header, pixels));
  const headerLen = (await reader.read(4)).readUInt32LE(0);
  const head = JSON.parse((await reader.read(headerLen)).toString("utf8"));
  const body = head.ok
    ? await reader.read(pixelBytes(head.width, head.height, head.count))
    : Buffer.alloc(0);
  socket.end();
  return { header: head, pixels: body };
}
