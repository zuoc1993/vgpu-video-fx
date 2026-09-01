"""Talk to a running sidecar without BMF.

Start the sidecar first (`npm run sidecar`), then:
  uv run python test_client.py

Used by npm run smoke:sidecar.
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from vgpu_fx_protocol import VgpuFxClient


def main() -> None:
    path = os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock")
    w = h = 8
    pixel = bytes([40, 80, 120, 255] * (w * h))
    client = VgpuFxClient(path)
    try:
        one = client.render(effect="none", width=w, height=h, pixels=pixel, times=[0.0])
        if len(one) != w * h * 4:
            raise SystemExit(f"bad size {len(one)}")
        if max(abs(one[i] - pixel[i]) for i in range(len(pixel))) > 2:
            raise SystemExit("none identity failed")
        two = client.render(effect="none", width=w, height=h, pixels=pixel + pixel, times=[0.0, 0.1])
        if len(two) != w * h * 8:
            raise SystemExit(f"bad batch size {len(two)}")
    finally:
        client.close()
    print("ok python sidecar client")


if __name__ == "__main__":
    main()
