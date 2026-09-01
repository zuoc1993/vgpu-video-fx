import { fileURLToPath } from "node:url";
import { resolveShader } from "@vgpu/wgsl/runtime";

export async function resolve(specifier, context, nextResolve) {
  if (!specifier.endsWith(".wgsl")) return nextResolve(specifier, context);
  return { url: new URL(specifier, context.parentURL).href, shortCircuit: true };
}

export async function load(url, context, nextLoad) {
  if (!url.endsWith(".wgsl")) return nextLoad(url, context);
  const resolved = await resolveShader({ entry: fileURLToPath(url), validate: "require" });
  const source = `export default { version: 1, wgsl: ${JSON.stringify(resolved.wgsl)} };\n`;
  return { format: "module", shortCircuit: true, source };
}
