"""BMF module: send each video frame to the vgpu-fx sidecar and emit the result."""

from __future__ import annotations

import os
import time

import numpy as np

from vgpu_fx_protocol import DEFAULT_SOCK, VgpuFxClient

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
        self.socket_path = str(option.get("socket") or os.environ.get("VGPU_FX_SOCK") or DEFAULT_SOCK)
        self.video_duration = float(option.get("videoDuration") or 0)
        self.batch = max(1, int(option.get("batch") or 15))
        self.client: VgpuFxClient | None = None
        self.pending: list[tuple[object, object, np.ndarray, float]] = []
        self.frames = 0
        self.batches = 0
        self.render_s = 0.0
        self._reported = False

    def init(self):
        self.client = VgpuFxClient(self.socket_path)

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
                rgba = vf_to_rgba(vf)
                self.pending.append((pkt, vf, rgba, vf_pts_sec(vf, pkt)))
                if len(self.pending) >= self.batch:
                    self._flush(outgoing)
        return ProcessResult.OK

    def _flush(self, outgoing):
        if not self.pending or self.client is None:
            self.pending = []
            return
        height, width = self.pending[0][2].shape[:2]
        pixels = b"".join(np.ascontiguousarray(item[2]).tobytes() for item in self.pending)
        times = [item[3] for item in self.pending]
        t0 = time.perf_counter()
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
        for i, (pkt, vf, _, _) in enumerate(self.pending):
            rgba = np.frombuffer(out[i * stride : (i + 1) * stride], dtype=np.uint8).reshape(height, width, 4)
            out_vf = rgba_to_vf(rgba, vf)
            out_pkt = Packet(out_vf)
            out_pkt.timestamp = pkt.timestamp
            outgoing.put(out_pkt)
        self.pending = []

    def _report(self):
        if self._reported or self.frames == 0:
            return
        self._reported = True
        fps = self.frames / self.render_s if self.render_s else 0
        print(
            f"vgpu_fx {self.effect}: {self.frames} frames / {self.batches} batches×{self.batch} "
            f"/ {self.render_s:.3f}s sidecar = {fps:.1f} fps",
            flush=True,
        )


def vf_to_rgba(vf) -> np.ndarray:
    rgb = vf.reformat(mp.PixelInfo(mp.kPF_RGB24)).frame().plane(0).numpy()
    out = np.empty((rgb.shape[0], rgb.shape[1], 4), dtype=np.uint8)
    out[:, :, :3] = rgb
    out[:, :, 3] = 255
    return out


def rgba_to_vf(rgba: np.ndarray, src_vf):
    rgb = np.ascontiguousarray(rgba[:, :, :3])
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
