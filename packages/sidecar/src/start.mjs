#!/usr/bin/env node
import { register } from "node:module";

register(new URL("./wgsl-loader.mjs", import.meta.url));
await import("./server.ts");
