"""Decode sample.mp4 through every catalog effect → output/{effect}.mp4.

Start the sidecar first:
  npm run sidecar

Then:
  uv run run_demo.py

Default batch is 15 frames per sidecar roundtrip (VGPU_FX_BATCH).
"""

from __future__ import annotations

import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# Keep in sync with packages/effect-core/src/effects/registry.ts
EFFECTS = (
    "none",
    "handheld-cam",
    "camera-shake",
    "local-push",
    "glitch",
    "screen-shake",
    "zoom-in",
    "zoom-out",
)


def attach_fx(video, option: dict):
    return video.py_module("vgpu_fx", option, HERE, "vgpu_fx.VgpuFx")


def probe_duration(path: str) -> float:
    try:
        raw = subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
            text=True,
        ).strip()
        return float(raw)
    except Exception:
        return 0.0


def load_bmf():
    try:
        import bmf
        return bmf
    except ImportError as err:
        msg = str(err)
        if "libavcodec" in msg or "libavformat" in msg or "libavutil" in msg:
            raise SystemExit("BabitMF needs FFmpeg 4 (libavcodec.58). On macOS: brew install ffmpeg@4") from err
        raise SystemExit("need BabitMF: uv sync") from err


def run_one(bmf, inp: str, effect: str, duration: float, sock: str, batch: int, out_dir: str) -> str:
    out = os.path.join(out_dir, f"{effect}.mp4")
    option = {
        "effect": effect,
        "socket": sock,
        "batch": batch,
        "params": {},
        "videoDuration": duration,
    }
    t0 = time.perf_counter()
    graph = bmf.graph()
    video = attach_fx(graph.decode({"input_path": inp})["video"], option)
    video.encode(
        None,
        {
            "output_path": out,
            "video_params": {"codec": "h264", "crf": "23", "preset": "veryfast"},
        },
    ).run()
    print(f"wrote {out}  wall {time.perf_counter() - t0:.2f}s")
    return out


def main() -> None:
    bmf = load_bmf()
    inp = os.path.join(ROOT, "public", "sample.mp4")
    if not os.path.isfile(inp):
        raise SystemExit(f"missing input {inp}")
    duration = probe_duration(inp)
    out_dir = os.path.join(HERE, "output")
    os.makedirs(out_dir, exist_ok=True)
    sock = os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock")
    batch = int(os.environ.get("VGPU_FX_BATCH", "15"))
    for effect in EFFECTS:
        run_one(bmf, inp, effect, duration, sock, batch, out_dir)


if __name__ == "__main__":
    main()
