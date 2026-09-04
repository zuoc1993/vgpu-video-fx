"""Decode sample.mp4 through the catalog → output/{effect}.mp4.

Effect selection follows the backend:
  - native (effect_rs): only the effects ported to Rust (effect_rs.catalog())
  - socket (sidecar):   the full TS catalog (EFFECTS below)

Start the sidecar first for the socket backend:
  npm run sidecar

Then:
  VGPU_FX_BACKEND=native uv run run_demo.py   # effect-rs subset
  VGPU_FX_BACKEND=socket uv run run_demo.py   # all effects
  uv run run_demo.py                          # auto: native if installed, else socket

Default batch is 15 frames per roundtrip (VGPU_FX_BATCH).
VGPU_FX_EFFECTS=a,b,c further narrows the selection.
VGPU_FX_LIST_ONLY=1 prints the plan without rendering.
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
    "cylinder-wrap",
    "pixeliz0r",
    "squigglevision",
    "colorhalftone",
    "sobel",
    "water",
    "defish0r",
    "vignette",
    "heatmap0r",
    "glitch0r",
    "pixels0rt",
    "kaleid0sc0pe",
    "distort0r",
    "rgbsplit0r",
    "emboss",
    "posterize",
    "pixs0r",
    "dither",
    "ntsc",
    "edgeglow",
    "scanline0r",
    "glow",
    "crt",
    "spectral-flare",
    "dust-bokeh",
    "spacetime-lens",
    "retro-quantize",
    "grade",
    "light-leak",
    "dissolve",
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


def run_one(bmf, inp: str, effect: str, duration: float, sock: str, batch: int, backend: str, out_dir: str) -> str:
    out = os.path.join(out_dir, f"{effect}.mp4")
    option = {
        "effect": effect,
        "socket": sock,
        "batch": batch,
        "backend": backend,
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


def resolve_backend() -> str:
    backend = os.environ.get("VGPU_FX_BACKEND", "")
    if backend not in ("native", "socket", "wgpu"):
        try:
            import effect_rs  # noqa: F401
            backend = "native"
        except ImportError:
            backend = "socket"
    return backend


def plan_effects(backend: str) -> list[str]:
    """native → effect_rs subset; wgpu → exported WGSL catalog; socket → full TS catalog."""
    if backend == "native":
        try:
            import effect_rs
            available = {e["id"] for e in effect_rs.catalog()}
        except ImportError:
            available = set()
        targets = [e for e in EFFECTS if e in available]
    elif backend == "wgpu":
        try:
            from vgpu_fx_gpu import WgpuFxRenderer
            available = set(WgpuFxRenderer.catalog_ids())
        except Exception:
            available = set()
        targets = [e for e in EFFECTS if e in available]
    else:
        targets = list(EFFECTS)
    wanted = [e.strip() for e in os.environ.get("VGPU_FX_EFFECTS", "").split(",") if e.strip()]
    if wanted:
        targets = [e for e in targets if e in wanted]
    return targets


def main() -> None:
    inp = os.path.join(ROOT, "public", "sample.mp4")
    if not os.path.isfile(inp):
        raise SystemExit(f"missing input {inp}")
    duration = probe_duration(inp)
    out_dir = os.path.join(HERE, "output")
    os.makedirs(out_dir, exist_ok=True)
    sock = os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock")
    batch = int(os.environ.get("VGPU_FX_BATCH", "15"))
    backend = resolve_backend()
    targets = plan_effects(backend)
    print(f"backend={backend} effects=({len(targets)}) {','.join(targets)}", flush=True)
    if os.environ.get("VGPU_FX_LIST_ONLY"):
        return
    bmf = load_bmf()
    for effect in targets:
        run_one(bmf, inp, effect, duration, sock, batch, backend, out_dir)


if __name__ == "__main__":
    main()
