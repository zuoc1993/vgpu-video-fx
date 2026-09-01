"""Unix-socket framing for the vgpu-fx sidecar: u32le headerLen + JSON + RGBA8."""

from __future__ import annotations

import json
import os
import socket
import struct
from typing import Mapping, Sequence

DEFAULT_SOCK = os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock")


def encode_message(header: Mapping[str, object], pixels: bytes = b"") -> bytes:
    raw = json.dumps(header, separators=(",", ":")).encode("utf-8")
    return struct.pack("<I", len(raw)) + raw + pixels


def read_exact(sock: socket.socket, n: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < n:
        piece = sock.recv(n - len(chunks))
        if not piece:
            raise ConnectionError("socket closed")
        chunks.extend(piece)
    return bytes(chunks)


def read_message(sock: socket.socket, expect_pixels: bool) -> tuple[dict, bytes]:
    header_len = struct.unpack("<I", read_exact(sock, 4))[0]
    if header_len < 2 or header_len > 1_000_000:
        raise ValueError(f"bad headerLen {header_len}")
    header = json.loads(read_exact(sock, header_len).decode("utf-8"))
    if not expect_pixels or not header.get("ok"):
        return header, b""
    need = int(header["width"]) * int(header["height"]) * int(header["count"]) * 4
    return header, read_exact(sock, need)


class VgpuFxClient:
    def __init__(self, path: str = DEFAULT_SOCK) -> None:
        self.path = path
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            self._sock.connect(path)
        except OSError as err:
            self._sock.close()
            raise ConnectionError(
                f"sidecar not listening on {path}; start it with: npm run sidecar"
            ) from err
        self._seq = 0

    def close(self) -> None:
        try:
            self._sock.close()
        except OSError:
            pass

    def render(
        self,
        *,
        effect: str,
        width: int,
        height: int,
        pixels: bytes,
        times: Sequence[float],
        params: Mapping[str, float] | None = None,
        video_duration: float = 0,
        req_id: str | int | None = None,
    ) -> bytes:
        count = len(times)
        expect = width * height * count * 4
        if len(pixels) != expect:
            raise ValueError(f"pixels {len(pixels)} != {expect}")
        self._seq += 1
        header = {
            "id": req_id if req_id is not None else str(self._seq),
            "effect": effect,
            "params": dict(params or {}),
            "width": width,
            "height": height,
            "count": count,
            "times": [float(t) for t in times],
            "videoDuration": float(video_duration),
        }
        self._sock.sendall(encode_message(header, pixels))
        reply, out = read_message(self._sock, expect_pixels=True)
        if not reply.get("ok"):
            raise RuntimeError(reply.get("error") or "sidecar error")
        return out
