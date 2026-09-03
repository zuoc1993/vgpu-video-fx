"""Compare GPU (sidecar/WebGPU) vs native effect_rs pixel outputs.

Decodes the first N frames of public/sample.mp4 once, renders them through both
backends for each effect, and reports per-pixel diff metrics.

Requires: npm run sidecar (socket backend) and the effect_rs module installed
(maturin develop). Frames are decoded with ffmpeg CLI.

Env:
  VGPU_FX_COMPARE_FRAMES  frame count (default 10)
  VGPU_FX_SOCK            sidecar socket (default /tmp/vgpu-fx.sock)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import effect_rs
from vgpu_fx_protocol import VgpuFxClient

EFFECTS = ("none", "posterize", "rgbsplit0r", "glitch", "glow")


def ff_bin(name: str) -> str:
    """Prefer FFmpeg 4 (the version BabitMF links against), then PATH."""
    for base in (
        os.environ.get("FFMPEG_DIR"),
        "/opt/homebrew/opt/ffmpeg@4/bin",
        "/usr/local/opt/ffmpeg@4/bin",
    ):
        if base and os.path.isfile(os.path.join(base, name)):
            return os.path.join(base, name)
    return name


def probe(path: str) -> dict:
    out = subprocess.check_output(
        [
            ff_bin("ffprobe"), "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,avg_frame_rate:format=duration",
            "-of", "json", path,
        ],
        text=True,
    )
    info = json.loads(out)
    stream = info["streams"][0]
    num, den = stream["avg_frame_rate"].split("/")
    fps = float(num) / float(den) if float(den) else 30.0
    return {
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "fps": fps,
        "duration": float(info["format"].get("duration") or 0.0),
    }


def decode_frames(path: str, n: int) -> bytes:
    raw = subprocess.check_output(
        [ff_bin("ffmpeg"), "-v", "error", "-i", path, "-frames:v", str(n), "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
    )
    return bytes(raw)


def main() -> None:
    inp = os.path.join(ROOT, "public", "sample.mp4")
    if not os.path.isfile(inp):
        raise SystemExit(f"missing input {inp}")
    n = int(os.environ.get("VGPU_FX_COMPARE_FRAMES", "10"))
    info = probe(inp)
    w, h = info["width"], info["height"]
    times = [i / info["fps"] for i in range(n)]
    pixels = decode_frames(inp, n)
    need = w * h * 4 * n
    if len(pixels) < need:
        raise SystemExit(f"decoded {len(pixels)} bytes < {need}")
    pixels = pixels[:need]

    sock = os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock")
    client = VgpuFxClient(sock)
    print(f"frames={n} size={w}x{h} fps={info['fps']:.3f} duration={info['duration']:.3f}s")
    print(f"{'effect':12s} {'mean':>8s} {'max':>4s} {'pct>2':>7s} {'gpu_ms':>8s} {'rs_ms':>8s}")
    for effect in EFFECTS:
        t0 = time.perf_counter()
        gpu = client.render(
            effect=effect, width=w, height=h, pixels=pixels, times=times,
            params={}, video_duration=info["duration"],
        )
        gpu_ms = (time.perf_counter() - t0) * 1000
        t0 = time.perf_counter()
        nat = effect_rs.render_batch(
            effect, w, h, pixels, times, params={}, video_duration=info["duration"],
        )
        rs_ms = (time.perf_counter() - t0) * 1000
        if len(gpu) != len(nat):
            print(f"{effect:12s} LENGTH MISMATCH gpu={len(gpu)} rs={len(nat)}")
            continue
        ga = np.frombuffer(gpu, dtype=np.uint8)
        na = np.frombuffer(nat, dtype=np.uint8)
        diff = np.abs(ga.astype(np.int16) - na.astype(np.int16))
        mean = float(diff.mean())
        mx = int(diff.max())
        pct = float((diff > 2).mean() * 100)
        print(
            f"{effect:12s} {mean:8.3f} {mx:4d} {pct:6.2f}% {gpu_ms:8.1f} {rs_ms:8.1f}",
            flush=True,
        )


if __name__ == "__main__":
    main()
