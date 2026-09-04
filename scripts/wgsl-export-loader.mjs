// Node module-hooks loader for scripts/export-effects.mjs.
// Same shape as packages/sidecar/src/wgsl-loader.mjs, but WGSL validation
// defaults to "off": the export consumer is naga (wgpu-py), which validates
// strictly at pipeline creation, and Dawn's napi teardown is flaky when its
// validation device lives in the module-hooks worker thread (intermittent
// exit-time abort). Set VGPU_EXPORT_VALIDATE=require to validate through Dawn.
import { fileURLToPath } from "node:url";
import { resolveShader } from "@vgpu/wgsl/runtime";

export async function resolve(specifier, context, nextResolve) {
  if (!specifier.endsWith(".wgsl")) return nextResolve(specifier, context);
  return { url: new URL(specifier, context.parentURL).href, shortCircuit: true };
}

export async function load(url, context, nextLoad) {
  if (!url.endsWith(".wgsl")) return nextLoad(url, context);
  const validate = process.env.VGPU_EXPORT_VALIDATE ?? "off";
  const resolved = await resolveShader({ entry: fileURLToPath(url), validate });
  const source = `export default { version: 1, wgsl: ${JSON.stringify(resolved.wgsl)} };\n`;
  return { format: "module", shortCircuit: true, source };
}
