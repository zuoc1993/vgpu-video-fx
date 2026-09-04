"""In-process GPU backend: render effect-core WGSL with wgpu-py.

Artifacts come from `npm run export:effects` (packages/effect-core/dist-effects/):
  - {id}.wgsl     the exact WGSL vgpu feeds the GPU (flattened imports +
                  injected fullscreen vertex stage)
  - effects.json  param metadata/defaults, authoritative uniform layout
                  (vgpu reflection) and the per-field value mapping

Rendering semantics mirror the vgpu sidecar (packages/sidecar +
packages/effect-core/src/engine.ts):
  - fullscreen triangle, no vertex buffers, draw(3)
  - group0: binding0 texture_2d<f32>, binding1 linear sampler, binding2 uniform
  - rgba8unorm offscreen targets, clear [0, 0, 0, 1]
  - per-frame submit (uniform buffer written in place; one submit per frame,
    same as engine.ts — N passes in one submit would all see the last write)
  - readback via copy_texture_to_buffer with 256-aligned bytes_per_row

No Node process, no socket: frames go numpy -> write_texture -> GPU ->
read_buffer, all inside this Python process.

Self-test without bmf:
  uv run vgpu_fx_gpu.py posterize 4
"""

from __future__ import annotations

import json
import os
import struct
import sys
import time
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np

try:
    import wgpu
except ImportError:  # pragma: no cover - exercised only when uninstalled
    wgpu = None  # type: ignore[assignment]

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DEFAULT_EFFECTS_DIR = ROOT / "packages" / "effect-core" / "dist-effects"

# Uniform field pack formats. Exporter rejects anything outside this set.
_KIND_FMT = {
    "f32": "<f",
    "i32": "<i",
    "u32": "<I",
    "vec2f": "<2f",
    "vec3f": "<3f",
    "vec4f": "<4f",
}
_KIND_WIDTH = {"f32": 1, "i32": 1, "u32": 1, "vec2f": 2, "vec3f": 3, "vec4f": 4}

_DEVICE = None
_ADAPTER_DESC = ""


def _get_device():
    """Process-wide device singleton (like the sidecar's single Gpu)."""
    global _DEVICE, _ADAPTER_DESC
    if wgpu is None:
        raise RuntimeError(
            "wgpu-py is not installed. Run: cd bmf-demo && uv pip install wgpu"
        )
    if _DEVICE is None:
        adapter = wgpu.gpu.request_adapter_sync(power_preference="high-performance")
        if adapter is None:
            raise RuntimeError(
                "wgpu found no adapter. Headless Linux without GPU: install "
                "lavapipe (mesa-vulkan-swrast) or point VK_ICD_FILENAMES at an ICD."
            )
        _DEVICE = adapter.request_device_sync()
        try:
            info = getattr(adapter, "info", None) or getattr(adapter, "request_adapter_info", lambda: None)()
            _ADAPTER_DESC = str(getattr(info, "device", None) or info or "unknown adapter")
        except Exception:
            _ADAPTER_DESC = "unknown adapter"
    return _DEVICE


def adapter_desc() -> str:
    _get_device()
    return _ADAPTER_DESC


class WgpuFxRenderer:
    """Renders effect batches with the exported WGSL. Holds GPU resources."""

    def __init__(self, effects_dir: str | os.PathLike[str] | None = None) -> None:
        self.dir = Path(effects_dir) if effects_dir else self.effects_dir()
        manifest_path = self.dir / "effects.json"
        if not manifest_path.is_file():
            raise RuntimeError(
                f"missing {manifest_path}; run `npm run export:effects` first"
            )
        manifest = json.loads(manifest_path.read_text())
        self._manifest = manifest
        self._meta = {e["id"]: e for e in manifest["effects"]}
        self._device = None
        self._bgl = None
        self._pipeline_layout = None
        self._sampler = None
        self._entries: dict[str, dict] = {}  # id -> {pipeline, ubuf, bg}
        self._src = None  # (w, h, texture, view)
        self._outs: list = []  # [(texture, view)], recycled across batches
        self._stg: list = []  # staging buffers, recycled

    # -- manifest-only helpers (no device needed) -----------------------------

    @classmethod
    def effects_dir(cls) -> Path:
        return Path(os.environ.get("VGPU_FX_EFFECTS_DIR") or DEFAULT_EFFECTS_DIR)

    @classmethod
    def available(cls) -> bool:
        return wgpu is not None and (cls.effects_dir() / "effects.json").is_file()

    @classmethod
    def catalog_ids(cls) -> list[str]:
        manifest = json.loads((cls.effects_dir() / "effects.json").read_text())
        return [e["id"] for e in manifest["effects"]]

    def catalog(self) -> list[str]:
        return sorted(self._meta)

    # -- GPU setup --------------------------------------------------------------

    def _ensure_device(self):
        if self._device is None:
            self._device = _get_device()
            self._bgl = self._device.create_bind_group_layout(
                entries=[
                    {
                        "binding": 0,
                        "visibility": wgpu.ShaderStage.FRAGMENT,
                        "texture": {
                            "sample_type": wgpu.TextureSampleType.float,
                            "view_dimension": wgpu.TextureViewDimension.d2,
                            "multisampled": False,
                        },
                    },
                    {
                        "binding": 1,
                        "visibility": wgpu.ShaderStage.FRAGMENT,
                        "sampler": {"type": wgpu.SamplerBindingType.filtering},
                    },
                    {
                        "binding": 2,
                        "visibility": wgpu.ShaderStage.FRAGMENT,
                        "buffer": {"type": wgpu.BufferBindingType.uniform},
                    },
                ]
            )
            self._pipeline_layout = self._device.create_pipeline_layout(
                bind_group_layouts=[self._bgl]
            )
            self._sampler = self._device.create_sampler(
                min_filter="linear", mag_filter="linear"
            )
        return self._device

    def _effect_entry(self, effect: str) -> dict:
        if effect not in self._meta:
            raise KeyError(
                f"unknown effect '{effect}'; exported catalog: {', '.join(self.catalog())}"
            )
        entry = self._entries.get(effect)
        if entry is None:
            device = self._ensure_device()
            meta = self._meta[effect]
            code = (self.dir / meta["wgsl"]).read_text()
            module = device.create_shader_module(code=code)
            pipeline = device.create_render_pipeline(
                layout=self._pipeline_layout,
                vertex={
                    "module": module,
                    "entry_point": self._manifest["vertexEntry"],
                    "buffers": [],
                },
                fragment={
                    "module": module,
                    "entry_point": self._manifest["fragmentEntry"],
                    "targets": [{"format": self._manifest["format"]}],
                },
                primitive={"topology": wgpu.PrimitiveTopology.triangle_list},
            )
            ubuf = device.create_buffer(
                size=meta["uniformSize"],
                usage=wgpu.BufferUsage.UNIFORM | wgpu.BufferUsage.COPY_DST,
            )
            entry = {
                "pipeline": pipeline,
                "ubuf": ubuf,
                "uniformSize": meta["uniformSize"],
                "bg": None,
            }
            self._entries[effect] = entry
        return entry

    def _ensure_src(self, width: int, height: int):
        if self._src and self._src[0] == width and self._src[1] == height:
            return self._src
        device = self._ensure_device()
        tex = device.create_texture(
            size=(width, height, 1),
            format=self._manifest["format"],
            usage=wgpu.TextureUsage.COPY_DST | wgpu.TextureUsage.TEXTURE_BINDING,
        )
        self._src = (width, height, tex, tex.create_view())
        # bind groups reference the src view; force rebuild
        for entry in self._entries.values():
            entry["bg"] = None
        return self._src

    def _bind_group(self, entry: dict, src_view):
        if entry["bg"] is None:
            entry["bg"] = self._ensure_device().create_bind_group(
                layout=self._bgl,
                entries=[
                    {"binding": 0, "resource": src_view},
                    {"binding": 1, "resource": self._sampler},
                    {
                        "binding": 2,
                        "resource": {
                            "buffer": entry["ubuf"],
                            "offset": 0,
                            "size": entry["uniformSize"],
                        },
                    },
                ],
            )
        return entry["bg"]

    def _ensure_outs(self, width: int, height: int, count: int) -> list:
        device = self._ensure_device()
        while len(self._outs) < count:
            self._outs.append(None)
        for i in range(count):
            cur = self._outs[i]
            if cur is None or cur[0] != width or cur[1] != height:
                tex = device.create_texture(
                    size=(width, height, 1),
                    format=self._manifest["format"],
                    usage=wgpu.TextureUsage.RENDER_ATTACHMENT | wgpu.TextureUsage.COPY_SRC,
                )
                self._outs[i] = (width, height, tex, tex.create_view())
        return self._outs[:count]

    def _ensure_stg(self, byte_size: int, count: int) -> list:
        device = self._ensure_device()
        while len(self._stg) < count:
            self._stg.append(None)
        for i in range(count):
            cur = self._stg[i]
            if cur is None or cur[0] != byte_size:
                buf = device.create_buffer(
                    size=byte_size,
                    usage=wgpu.BufferUsage.MAP_READ | wgpu.BufferUsage.COPY_DST,
                )
                self._stg[i] = (byte_size, buf)
        return [buf for _, buf in self._stg[:count]]

    # -- uniform packing ---------------------------------------------------------

    @staticmethod
    def _resolve_value(spec, values: Mapping[str, float], ctx: dict):
        """spec: ["param", key] | ["ctx", key] | ["zero"] (see export-effects.mjs)."""
        kind = spec[0]
        if kind == "zero":
            return 0.0
        if kind == "param":
            return values.get(spec[1], 0.0)
        key = spec[1]
        if key == "videoTimeOrTime":
            # ctx.videoDuration > 0 ? ctx.videoTime : ctx.time (zoom/cylinder-wrap)
            return ctx["videoTime"] if ctx["videoDuration"] > 0 else ctx["time"]
        return ctx[key]

    def _pack(self, meta: dict, values: Mapping[str, float], ctx: dict) -> bytes:
        buf = bytearray(meta["uniformSize"])
        for field in meta["fields"]:
            spec = meta["mapping"].get(field["name"])
            v = self._resolve_value(spec, values, ctx) if spec else 0.0
            kind = field["kind"]
            width = _KIND_WIDTH[kind]
            if width == 1:
                v = v if isinstance(v, (int, float)) else 0.0
                struct.pack_into(_KIND_FMT[kind], buf, field["offset"], v)
            else:
                seq = list(v) if isinstance(v, (list, tuple)) else [0.0]
                seq += [0.0] * (width - len(seq))
                struct.pack_into(
                    _KIND_FMT[kind], buf, field["offset"], *[float(x) for x in seq[:width]]
                )
        return bytes(buf)

    # -- render -------------------------------------------------------------------

    def render_batch(
        self,
        effect: str,
        width: int,
        height: int,
        pixels: bytes,
        times: Sequence[float],
        params: Mapping[str, float] | None = None,
        video_duration: float = 0.0,
    ) -> bytes:
        """Render len(times) RGBA8 frames; returns concatenated RGBA8 bytes."""
        device = self._ensure_device()
        queue = device.queue
        meta = self._meta.get(effect)
        if meta is None:
            raise KeyError(f"unknown effect '{effect}'")
        count = len(times)
        stride = width * height * 4
        if len(pixels) != stride * count:
            raise ValueError(f"pixels {len(pixels)} != {stride * count}")

        entry = self._effect_entry(effect)
        _, _, src_tex, src_view = self._ensure_src(width, height)
        bind_group = self._bind_group(entry, src_view)
        outs = self._ensure_outs(width, height, count)
        bytes_per_row = (width * 4 + 255) // 256 * 256  # WebGPU copy alignment
        stg = self._ensure_stg(bytes_per_row * height, count)

        values = dict(meta["defaults"])
        if params:
            values.update({k: float(v) for k, v in params.items()})

        clear = tuple(self._manifest.get("clearColor", [0, 0, 0, 1]))
        frame_view = memoryview(pixels)
        prev_time: float | None = None
        for i, t in enumerate(times):
            t = float(t)
            ctx = {
                "time": t,
                "deltaTime": 0.0 if prev_time is None else t - prev_time,
                "videoTime": t,
                "videoDuration": float(video_duration),
                "resolution": (float(width), float(height)),
                "texel": (1.0 / width, 1.0 / height),
                "videoSize": (float(width), float(height)),
            }
            prev_time = t
            queue.write_texture(
                {"texture": src_tex, "mip_level": 0, "origin": (0, 0, 0), "aspect": "all"},
                frame_view[i * stride : (i + 1) * stride],
                {"offset": 0, "bytes_per_row": width * 4, "rows_per_image": height},
                (width, height, 1),
            )
            queue.write_buffer(entry["ubuf"], 0, self._pack(meta, values, ctx))
            encoder = device.create_command_encoder()
            render_pass = encoder.begin_render_pass(
                color_attachments=[
                    {
                        "view": outs[i][3],
                        "load_op": wgpu.LoadOp.clear,
                        "store_op": wgpu.StoreOp.store,
                        "clear_value": clear,
                    }
                ]
            )
            render_pass.set_pipeline(entry["pipeline"])
            render_pass.set_bind_group(0, bind_group)
            render_pass.draw(3)
            render_pass.end()
            queue.submit([encoder.finish()])

        # One readback submit for the whole batch (engine.ts does the same:
        # N draws first, then all reads together).
        encoder = device.create_command_encoder()
        for i in range(count):
            encoder.copy_texture_to_buffer(
                {"texture": outs[i][2], "mip_level": 0, "origin": (0, 0, 0), "aspect": "all"},
                {
                    "buffer": stg[i],
                    "offset": 0,
                    "bytes_per_row": bytes_per_row,
                    "rows_per_image": height,
                },
                (width, height, 1),
            )
        queue.submit([encoder.finish()])

        result = bytearray(stride * count)
        padded = bytes_per_row != width * 4
        for i in range(count):
            data = self._read_buffer(queue, stg[i])
            if padded:
                rows = np.frombuffer(data, dtype=np.uint8, count=bytes_per_row * height)
                rows = rows.reshape(height, bytes_per_row)[:, : width * 4]
                result[i * stride : (i + 1) * stride] = np.ascontiguousarray(rows).tobytes()
            else:
                result[i * stride : (i + 1) * stride] = data[:stride]
        return bytes(result)

    @staticmethod
    def _read_buffer(queue, buf) -> memoryview:
        # Staging buffers are MAP_READ | COPY_DST: map them in place.
        # queue.read_buffer would insert a buffer-to-buffer copy, which
        # wgpu validates as requiring COPY_SRC -- a usage a MAP_READ buffer
        # must not have -- so it cannot read our staging buffers.
        buf.map_sync(wgpu.MapMode.READ)
        try:
            return buf.read_mapped()
        finally:
            buf.unmap()


def main() -> None:
    """Synthetic smoke test: uv run vgpu_fx_gpu.py [effect] [frames]"""
    effect = sys.argv[1] if len(sys.argv) > 1 else "posterize"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    renderer = WgpuFxRenderer()
    print(f"adapter: {adapter_desc()}")
    w, h = 320, 180
    yy, xx = np.mgrid[0:h, 0:w]
    base = np.stack(
        [xx % 256, yy % 256, (xx + yy) % 256, np.full_like(xx, 255)], axis=-1
    ).astype(np.uint8)
    frames = b"".join(
        np.ascontiguousarray(np.roll(base, i * 3, axis=1)).tobytes() for i in range(n)
    )
    times = [i / 30.0 for i in range(n)]
    t0 = time.perf_counter()
    out = renderer.render_batch(
        effect, w, h, frames, times, params={}, video_duration=n / 30.0
    )
    dt = time.perf_counter() - t0
    arr = np.frombuffer(out, dtype=np.uint8)
    print(
        f"{effect} x{n} {w}x{h}: {dt * 1000:.1f}ms ({n / dt:.1f}fps) "
        f"bytes={len(out)} checksum={int(arr.sum())} mean={arr.mean():.2f}"
    )


if __name__ == "__main__":
    main()
