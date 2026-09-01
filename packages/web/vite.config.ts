import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import { wgslVitePlugin } from "@vgpu/wgsl/loader-vite";

const root = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  plugins: [wgslVitePlugin()],
  publicDir: path.resolve(root, "../../public"),
  resolve: {
    alias: {
      "@vgpu-fx/effect-core": path.resolve(root, "../effect-core/src/index.ts"),
    },
  },
  server: {
    fs: { allow: [path.resolve(root, "../..")] },
  },
});
