# vgpu Video FX

English | [简体中文](README.zh-CN.md)

One catalog of WebGPU video effects (39 total): real-time preview in the browser, plus offline rendering via BMF with three interchangeable backends — in-process wgpu-py (recommended, no sidecar needed), a Node sidecar (Dawn), and effect_rs (CPU, 5 effects).

## Documentation

| Doc | Contents |
|---|---|
| [Architecture](docs/architecture.md) | Module responsibilities, data flow, protocols, performance |
| [Usage Guide](docs/usage.md) | Preview, rendering, parameters, troubleshooting |
| [Development](docs/development.md) | Adding effects, clocks, tests, constraints |
| [wgpu-py Backend](docs/wgpu-py-backend.md) | Exported artifact design, render semantics, parity benchmarks |
| [wgpu-py Validation Manual](docs/wgpu-py-validation.md) | Backend acceptance steps and report template |
| [effect-rs Validation](docs/effect-rs-validation.md) | CPU backend acceptance records |

## Quick Start

```sh
npm install
npm run dev          # http://127.0.0.1:5173/
```

Render a video (wgpu backend, no sidecar required):

```sh
npm run export:effects                       # export WGSL artifacts (checked in; re-run after shader changes)
cd bmf-demo && uv sync --group wgpu
VGPU_FX_BACKEND=wgpu uv run run_demo.py
```

Rendering via the sidecar: run `npm run sidecar` first, then `cd bmf-demo && uv sync && VGPU_FX_BACKEND=socket uv run run_demo.py`. See the usage guide for details.

```sh
npm test
```

## Effects

`none` · `handheld-cam` · `camera-shake` · `local-push` · `glitch` · `screen-shake` · `zoom-in` · `zoom-out` · `cylinder-wrap` · `pixeliz0r` · `squigglevision` · `colorhalftone` · `sobel` · `water` · `defish0r` · `vignette` · `heatmap0r` · `glitch0r` · `pixels0rt` · `kaleid0sc0pe` · `distort0r` · `rgbsplit0r` · `emboss` · `posterize` · `pixs0r` · `dither` · `ntsc` · `edgeglow` · `scanline0r` · `glow` · `crt` · `spectral-flare` · `dust-bokeh` · `spacetime-lens` · `retro-quantize` · `grade` · `light-leak` · `dissolve` · `curtain-wind`

## License

[MIT](LICENSE)
