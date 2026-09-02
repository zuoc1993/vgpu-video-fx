import { existsSync, unlinkSync } from "node:fs";
import { createServer, type Socket } from "node:net";
import { init } from "vgpu/node";
import { EffectEngine } from "@vgpu-fx/effect-core/engine";
import { DEFAULT_SOCK, encodeMessage, parseRequest, pixelBytes, type RequestHeader } from "./protocol.ts";
import { sockReader, type SockReader } from "./read.ts";

const sockPath = process.env.VGPU_FX_SOCK || DEFAULT_SOCK;

const gpu = await init();
let lastGpuError: Error | undefined;
const engine = await EffectEngine.create({
  gpu,
  onError: (error) => {
    lastGpuError = error;
  },
});

let queue = Promise.resolve();
const exclusive = <T>(fn: () => Promise<T>): Promise<T> => {
  const run = queue.then(fn, fn);
  queue = run.then(() => undefined, () => undefined);
  return run;
};

if (existsSync(sockPath)) unlinkSync(sockPath);

const server = createServer({ pauseOnConnect: true }, (socket) => {
  void session(socket);
});

server.listen(sockPath, () => {
  console.log(`vgpu-fx sidecar listening on ${sockPath}`);
});

async function session(socket: Socket): Promise<void> {
  const reader = sockReader(socket);
  try {
    for (;;) {
      const tr = performance.now();
      const req = await readRequest(reader);
      const tq = performance.now();
      const res = await exclusive(() => handle(req));
      const tw = performance.now();
      await writeAll(socket, res);
      if (TIMING) console.error(`sidecar io: read ${(tq - tr).toFixed(1)}ms write ${(performance.now() - tw).toFixed(1)}ms`);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message !== "socket closed") console.error("sidecar: session", message);
    if (socket.writable && message !== "socket closed") {
      try {
        await writeAll(socket, encodeMessage({ id: "", ok: false, error: message }));
      } catch {
        // hangup
      }
    }
  } finally {
    socket.destroy();
  }
}

async function readRequest(reader: SockReader): Promise<{ header: RequestHeader; pixels: Buffer }> {
  const headerLen = (await reader.read(4)).readUInt32LE(0);
  if (headerLen < 2 || headerLen > 1_000_000) throw new Error(`bad headerLen ${headerLen}`);
  const header = parseRequest(JSON.parse((await reader.read(headerLen)).toString("utf8")));
  const pixels = await reader.read(pixelBytes(header.width, header.height, header.count));
  return { header, pixels };
}

const TIMING = !!process.env.VGPU_FX_TIMING;

async function handle(req: { header: RequestHeader; pixels: Buffer }): Promise<Buffer> {
  const { header, pixels } = req;
  lastGpuError = undefined;
  try {
    const t0 = performance.now();
    const stride = header.width * header.height * 4;
    const frames = header.times.map((time, i) => ({
      width: header.width,
      height: header.height,
      data: pixels.subarray(i * stride, (i + 1) * stride),
      time,
    }));
    const rendered = await engine.renderBatch({
      effect: header.effect,
      params: header.params,
      videoDuration: header.videoDuration,
      frames,
    });
    if (lastGpuError) throw lastGpuError;
    const t1 = performance.now();
    const out = Buffer.allocUnsafe(stride * header.count);
    for (let i = 0; i < rendered.length; i += 1) {
      const src = rendered[i]!.data;
      if (src.byteLength < stride) throw new Error("short render");
      out.set(src.subarray(0, stride), i * stride);
    }
    if (TIMING) console.error(`sidecar ${header.effect} ×${header.count}: render ${(t1 - t0).toFixed(1)}ms pack ${(performance.now() - t1).toFixed(1)}ms`);
    return encodeMessage({
      id: header.id,
      ok: true,
      width: header.width,
      height: header.height,
      count: header.count,
    }, out);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return encodeMessage({ id: header.id, ok: false, error: message });
  }
}

function writeAll(socket: Socket, data: Buffer): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.write(data, (err) => (err ? reject(err) : resolve()));
  });
}

const shutdown = () => {
  server.close();
  try {
    unlinkSync(sockPath);
  } catch {
    // already gone
  }
  engine.dispose();
  gpu.dispose();
  process.exit(0);
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
