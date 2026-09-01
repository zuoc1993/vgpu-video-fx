import type { Socket } from "node:net";

export type SockReader = {
  read(n: number): Promise<Buffer>;
};

export function sockReader(socket: Socket): SockReader {
  const chunks: Buffer[] = [];
  let needed = 0;
  let waiter: { resolve: (buf: Buffer) => void; reject: (err: Error) => void } | null = null;

  const take = (n: number): Buffer => {
    const all = Buffer.concat(chunks);
    chunks.length = 0;
    if (all.length > n) chunks.push(all.subarray(n));
    return all.subarray(0, n);
  };

  const available = (): number => chunks.reduce((sum, chunk) => sum + chunk.length, 0);

  const flush = (): void => {
    if (!waiter || available() < needed) return;
    const { resolve } = waiter;
    waiter = null;
    resolve(take(needed));
  };

  socket.on("data", (chunk: Buffer) => {
    chunks.push(chunk);
    flush();
  });
  socket.on("end", () => waiter?.reject(new Error("socket closed")));
  socket.on("error", (err: Error) => waiter?.reject(err));
  socket.resume();

  return {
    read(n: number) {
      if (n === 0) return Promise.resolve(Buffer.alloc(0));
      return new Promise((resolve, reject) => {
        needed = n;
        waiter = { resolve, reject };
        flush();
      });
    },
  };
}
