"""Time one 15-frame batch roundtrip against the sidecar (no BMF)."""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from vgpu_fx_protocol import VgpuFxClient

W, H = 1664, 1080
N = int(sys.argv[1]) if len(sys.argv) > 1 else 15
frame = os.urandom(W * H * 4)
pixels = frame * N
times = [i / 30 for i in range(N)]

c = VgpuFxClient(os.environ.get("VGPU_FX_SOCK", "/tmp/vgpu-fx.sock"))
for effect in ("none", "glitch"):
    for warm in range(2):
        c.render(effect=effect, width=W, height=H, pixels=pixels, times=times)
    ts = []
    for _ in range(3):
        t0 = time.perf_counter()
        c.render(effect=effect, width=W, height=H, pixels=pixels, times=times)
        ts.append(time.perf_counter() - t0)
    mb = len(pixels) / 1e6
    print(f"{effect}: {min(ts)*1e3:.0f}ms per {N}-frame batch ({mb:.0f}MB each way) = {N/min(ts):.1f} fps")
c.close()
