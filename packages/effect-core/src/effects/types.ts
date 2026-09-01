import type { ShaderSource } from "vgpu";

export type ParamDef = {
  readonly key: string;
  readonly label: string;
  readonly type: "range";
  readonly min: number;
  readonly max: number;
  readonly step: number;
  readonly default: number;
};

export type ParamValues = Record<string, number>;

export type FrameContext = {
  readonly time: number;
  readonly deltaTime: number;
  readonly videoTime: number;
  readonly videoDuration: number;
  readonly resolution: readonly [number, number];
  readonly texel: readonly [number, number];
  readonly videoSize: readonly [number, number];
};

export type UniformBag = {
  readonly params: Record<string, number | readonly number[]>;
};

export type EffectDefinition = {
  readonly id: string;
  readonly name: string;
  readonly category: string;
  readonly description: string;
  readonly params: readonly ParamDef[];
  readonly shader: ShaderSource;
  uniforms(values: ParamValues, ctx: FrameContext): UniformBag;
};

export function defaultsFrom(params: readonly ParamDef[]): ParamValues {
  const values: ParamValues = {};
  for (const param of params) values[param.key] = param.default;
  return values;
}
