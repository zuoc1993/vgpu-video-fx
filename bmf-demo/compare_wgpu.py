"""Compare sidecar GPU (Dawn/tint) vs wgpu-py GPU (wgpu/naga) pixel outputs.

Same methodology as compare_backends.py, but the second backend is the
in-process wgpu-py renderer running the exported WGSL (same flattened shaders
the sidecar executes). This is the conformance gate for the wgpu backend:
integer-hash effects must be bit-identical; float filtering may differ by
±1 LSB between tint and naga on the same GPU.

Requires: npm run sidecar (socket backend), `npm run export:effects`, and
wgpu-py installed (uv pip install wgpu). Frames are decoded with ffmpeg CLI.

Env:
  VGPU_FX_COMPARE_FRAMES  frame count (default 10)
  VGPU_FX_EFFECTS         comma-separated subset (default: whole exported catalog)
  VGPU_FX_SOCK            sidecar socket (default /tmp/vgpu-fx.sock)
"""

from __future__ import annotations

import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from compare_backends import decode_frames, probe  # noqa: E402
from vgpu_fx_gpu import WgpuFxRenderer  # noqa: E402
from vgpu_fx_protocol import VgpuFxClient  # noqa: E402


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

    renderer = WgpuFxRenderer()
    effects = renderer.catalog()
    wanted = [e.strip() for e in os.environ.get("VGPU_FX_EFFECTS", "").split(",") if e.strip()]
    if wanted:
        effects = [e for e in effects if e in wanted]

    sock = os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock")
    client = VgpuFxClient(sock)
    print(f"frames={n} size={w}x{h} fps={info['fps']:.3f} duration={info['duration']:.3f}s")
    print(f"{'effect':16s} {'mean':>8s} {'max':>4s} {'pct>2':>7s} {'dawn_ms':>8s} {'wgpu_ms':>8s}")
    worst = ("", -1.0)
    for effect in effects:
        t0 = time.perf_counter()
        ref = client.render(
            effect=effect, width=w, height=h, pixels=pixels, times=times,
            params={}, video_duration=info["duration"],
        )
        dawn_ms = (time.perf_counter() - t0) * 1000
        t0 = time.perf_counter()
        got = renderer.render_batch(
            effect, w, h, pixels, times, params={}, video_duration=info["duration"],
        )
        wgpu_ms = (time.perf_counter() - t0) * 1000
        if len(ref) != len(got):
            print(f"{effect:16s} LENGTH MISMATCH dawn={len(ref)} wgpu={len(got)}")
            continue
        ra = np.frombuffer(ref, dtype=np.uint8)
        ga = np.frombuffer(got, dtype=np.uint8)
        diff = np.abs(ra.astype(np.int16) - ga.astype(np.int16))
        mean = float(diff.mean())
        mx = int(diff.max())
        pct = float((diff > 2).mean() * 100)
        if mean > worst[1]:
            worst = (effect, mean)
        print(
            f"{effect:16s} {mean:8.3f} {mx:4d} {pct:6.2f}% {dawn_ms:8.1f} {wgpu_ms:8.1f}",
            flush=True,
        )
    print(f"worst mean diff: {worst[0]} {worst[1]:.3f} / 255")


if __name__ == "__main__":
    main()
