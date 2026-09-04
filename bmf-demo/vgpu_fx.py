"""BMF module: render frames through the vgpu-fx catalog and emit the result.

Backends (option "backend" or VGPU_FX_BACKEND):
  - "native": effect_rs CPU (PyO3), no sidecar
  - "wgpu":   wgpu-py GPU in this process, runs the exported WGSL
              (`npm run export:effects` first), no sidecar
  - "socket": Node sidecar with Dawn over a unix socket
"""

from __future__ import annotations

import os
import time

import numpy as np

from vgpu_fx_protocol import DEFAULT_SOCK, VgpuFxClient

try:
    import effect_rs

    NATIVE_AVAILABLE = True
except ImportError:
    effect_rs = None  # type: ignore[assignment]
    NATIVE_AVAILABLE = False

try:
    from vgpu_fx_gpu import WgpuFxRenderer

    WGPU_AVAILABLE = WgpuFxRenderer.available()
except Exception:  # wgpu-py missing, or artifacts not exported yet
    WgpuFxRenderer = None  # type: ignore[assignment]
    WGPU_AVAILABLE = False


def pick_backend(requested: str) -> str:
    """Resolve backend with availability fallback. "wgpu" = in-process GPU via
    wgpu-py (no sidecar); "native" = effect_rs CPU; "socket" = Node sidecar."""
    if requested == "wgpu":
        if WGPU_AVAILABLE:
            return "wgpu"
        return "native" if NATIVE_AVAILABLE else "socket"
    if requested == "native":
        if NATIVE_AVAILABLE:
            return "native"
        return "wgpu" if WGPU_AVAILABLE else "socket"
    if requested == "socket":
        return "socket"
    # auto: in-process backends first, sidecar last
    if NATIVE_AVAILABLE:
        return "native"
    if WGPU_AVAILABLE:
        return "wgpu"
    return "socket"

try:
    from bmf import Log, LogLevel, Module, Packet, ProcessResult, Timestamp, VideoFrame
    import bmf.hmp as mp
except ImportError:  # pragma: no cover
    Module = object  # type: ignore[misc,assignment]


class VgpuFx(Module):
    def __init__(self, node=None, option=None):
        self.node_ = node
        option = option or {}
        self.effect = str(option.get("effect") or "none")
        self.params = option.get("params") or {}
        backend = str(option.get("backend") or os.environ.get("VGPU_FX_BACKEND") or "")
        self.backend = pick_backend(backend)
        self.socket_path = str(option.get("socket") or os.environ.get("VGPU_FX_SOCK") or DEFAULT_SOCK)
        self.video_duration = float(option.get("videoDuration") or 0)
        self.batch = max(1, int(option.get("batch") or 15))
        self.client: VgpuFxClient | None = None
        self.renderer = None
        self.pending: list[tuple[object, object, np.ndarray, float]] = []
        self.frames = 0
        self.batches = 0
        self.render_s = 0.0
        self.cvt_in_s = 0.0
        self.cvt_out_s = 0.0
        self._reported = False

    def init(self):
        if self.backend == "socket" and self.client is None:
            self.client = VgpuFxClient(self.socket_path)
        if self.backend == "wgpu" and self.renderer is None:
            self.renderer = WgpuFxRenderer()

    def close(self):
        self._report()
        if self.client:
            self.client.close()
            self.client = None

    def process(self, task):
        if self.client is None:
            self.init()
        for input_id, incoming in task.get_inputs().items():
            outgoing = task.get_outputs().get(input_id)
            if outgoing is None:
                continue
            while not incoming.empty():
                pkt = incoming.get()
                if pkt.timestamp == Timestamp.EOF:
                    self._flush(outgoing)
                    self._report()
                    outgoing.put(Packet.generate_eof_packet())
                    task.timestamp = Timestamp.DONE
                    return ProcessResult.OK
                if not pkt.defined() or pkt.timestamp == Timestamp.UNSET:
                    continue
                vf = pkt.get(VideoFrame)
                tc = time.perf_counter()
                rgba = vf_to_rgba(vf)
                self.cvt_in_s += time.perf_counter() - tc
                self.pending.append((pkt, vf, rgba, vf_pts_sec(vf, pkt)))
                if len(self.pending) >= self.batch:
                    self._flush(outgoing)
        return ProcessResult.OK

    def _flush(self, outgoing):
        if not self.pending or (self.backend == "socket" and self.client is None):
            self.pending = []
            return
        height, width = self.pending[0][2].shape[:2]
        pixels = b"".join(np.ascontiguousarray(item[2]).tobytes() for item in self.pending)
        times = [item[3] for item in self.pending]
        t0 = time.perf_counter()
        if self.backend == "native":
            out = effect_rs.render_batch(  # type: ignore[union-attr]
                self.effect,
                width,
                height,
                pixels,
                times,
                params=dict(self.params),
                video_duration=self.video_duration,
            )
        elif self.backend == "wgpu":
            out = self.renderer.render_batch(
                self.effect,
                width,
                height,
                pixels,
                times,
                params=dict(self.params),
                video_duration=self.video_duration,
            )
        else:
            out = self.client.render(
                effect=self.effect,
                width=width,
                height=height,
                pixels=pixels,
                times=times,
                params=self.params,
                video_duration=self.video_duration,
            )
        self.render_s += time.perf_counter() - t0
        self.batches += 1
        self.frames += len(self.pending)
        stride = width * height * 4
        tc = time.perf_counter()
        for i, (pkt, vf, _, _) in enumerate(self.pending):
            rgba = np.frombuffer(out[i * stride : (i + 1) * stride], dtype=np.uint8).reshape(height, width, 4)
            out_vf = rgba_to_vf(rgba, vf)
            out_pkt = Packet(out_vf)
            out_pkt.timestamp = pkt.timestamp
            outgoing.put(out_pkt)
        self.cvt_out_s += time.perf_counter() - tc
        self.pending = []

    def _report(self):
        if self._reported or self.frames == 0:
            return
        self._reported = True
        fps = self.frames / self.render_s if self.render_s else 0
        print(
            f"vgpu_fx[{self.backend}] {self.effect}: {self.frames} frames / {self.batches} batches×{self.batch} "
            f"/ {self.render_s:.3f}s render = {fps:.1f} fps "
            f"| cvt-in {self.cvt_in_s:.3f}s cvt-out {self.cvt_out_s:.3f}s",
            flush=True,
        )


def vf_to_rgba(vf) -> np.ndarray:
    rgb = vf.reformat(mp.PixelInfo(mp.kPF_RGB24)).frame().plane(0).numpy()
    # ponytail: per-channel strided writes vectorize (1.6ms); a 3-channel
    # slice assign does not (7.2ms)
    out = np.empty((rgb.shape[0], rgb.shape[1], 4), dtype=np.uint8)
    out[:, :, 0] = rgb[:, :, 0]
    out[:, :, 1] = rgb[:, :, 1]
    out[:, :, 2] = rgb[:, :, 2]
    out[:, :, 3] = 255
    return out


def rgba_to_vf(rgba: np.ndarray, src_vf):
    rgb = np.empty(rgba.shape[:2] + (3,), dtype=np.uint8)
    rgb[:, :, 0] = rgba[:, :, 0]
    rgb[:, :, 1] = rgba[:, :, 1]
    rgb[:, :, 2] = rgba[:, :, 2]
    frame = mp.Frame(mp.from_numpy(rgb), mp.PixelInfo(mp.kPF_RGB24))
    out = VideoFrame(frame)
    if hasattr(out, "copy_props"):
        out.copy_props(src_vf)
    else:
        out.pts = src_vf.pts
        if hasattr(src_vf, "time_base"):
            out.time_base = src_vf.time_base
    return out


def vf_pts_sec(vf, pkt) -> float:
    try:
        tb = vf.time_base
        num = getattr(tb, "numerator", getattr(tb, "num", 0))
        den = getattr(tb, "denominator", getattr(tb, "den", 1))
        if den:
            return float(vf.pts) * float(num) / float(den)
    except Exception:
        Log.log(LogLevel.DEBUG, "vgpu_fx pts fallback")
    ts = getattr(pkt, "timestamp", 0) or 0
    return float(ts) / 1_000_000.0 if ts > 0 else 0.0
