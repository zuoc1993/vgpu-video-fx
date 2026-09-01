export const DEFAULT_SOCK = "/tmp/vgpu-fx.sock";

export type RequestHeader = {
  id: string | number;
  effect: string;
  params?: Record<string, number>;
  width: number;
  height: number;
  count: number;
  times: number[];
  videoDuration?: number;
};

export type OkHeader = {
  id: string | number;
  ok: true;
  width: number;
  height: number;
  count: number;
};

export type ErrHeader = {
  id: string | number;
  ok: false;
  error: string;
};

export type ResponseHeader = OkHeader | ErrHeader;

export function pixelBytes(width: number, height: number, count: number): number {
  return width * height * count * 4;
}

export function encodeMessage(header: object, pixels?: Uint8Array): Buffer {
  const json = Buffer.from(JSON.stringify(header), "utf8");
  const out = Buffer.allocUnsafe(4 + json.length + (pixels?.byteLength ?? 0));
  out.writeUInt32LE(json.length, 0);
  json.copy(out, 4);
  if (pixels && pixels.byteLength) out.set(pixels, 4 + json.length);
  return out;
}

export function parseRequest(header: unknown): RequestHeader {
  if (!header || typeof header !== "object") throw new Error("invalid header");
  const h = header as Record<string, unknown>;
  const width = Number(h.width);
  const height = Number(h.height);
  const count = Number(h.count);
  const times = Array.isArray(h.times) ? h.times.map(Number) : [];
  if (!Number.isInteger(width) || width < 1) throw new Error("invalid width");
  if (!Number.isInteger(height) || height < 1) throw new Error("invalid height");
  if (!Number.isInteger(count) || count < 1) throw new Error("invalid count");
  if (times.length !== count) throw new Error("times length must equal count");
  if (typeof h.effect !== "string" || !h.effect) throw new Error("missing effect");
  const params = h.params && typeof h.params === "object" && !Array.isArray(h.params)
    ? Object.fromEntries(Object.entries(h.params).map(([k, v]) => [k, Number(v)]))
    : undefined;
  return {
    id: (h.id as string | number) ?? "",
    effect: h.effect,
    params,
    width,
    height,
    count,
    times,
    videoDuration: h.videoDuration === undefined ? undefined : Number(h.videoDuration),
  };
}
