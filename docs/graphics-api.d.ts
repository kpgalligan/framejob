// Reelcut graphics — the API as TypeScript declarations (road map 10, G-11).
// The prose is `graphics-api.md` beside this file (in a package's
// `graphics/`, `API.md`); this file types it, as GLOBAL declarations: the
// standard library is already in scope in a graphic, and a module imports
// nothing.
//
// A module is one ES module in `graphics/<name>.js`:
//
//   export const meta: Meta = { name: "Lower third", durationInFrames: 150 };
//   export const schema: Schema = { title: { type: "string", default: "Hi" } };
//   export function render(frame: number, props: Record<string, any>, ctx: Ctx): string {
//     return svg(ctx, `<text x="96" y="${ctx.height - 200}">${escapeXml(props.title)}</text>`);
//   }
//
// `render` is required and must return a string starting with `<svg`;
// `meta` and `schema` are optional (`{}` when absent). `frame` is an integer
// counted from the clip's first frame.

/** What a render is drawing into. */
interface Ctx {
  /** The project's frame rate, e.g. 30 or 29.97002997. */
  readonly fps: number;
  /** `frame / fps`, in seconds. */
  readonly time: number;
  /** The clip's length in frames. */
  readonly durationInFrames: number;
  /** `frame / max(1, durationInFrames - 1)`, clamped to 0–1. */
  readonly progress: number;
  /** The graphic's width in pixels. */
  readonly width: number;
  /** The graphic's height in pixels. */
  readonly height: number;
  /** The project's canvas. */
  readonly canvas: { readonly width: number; readonly height: number };
}

/** A module's optional `meta` export. */
interface Meta {
  /** Shown in the inspector. */
  name?: string;
  /** The default length of a new clip, in frames. */
  durationInFrames?: number;
}

interface SchemaCommon {
  /** Shown in the inspector; else the key. */
  label?: string;
  /** A tooltip. */
  help?: string;
}

/** One prop: a `type` and a `default` of that type. */
type SchemaEntry =
  | (SchemaCommon & { type: "string"; default: string; multiline?: boolean })
  | (SchemaCommon & { type: "number"; default: number; min?: number; max?: number; step?: number })
  | (SchemaCommon & { type: "boolean"; default: boolean })
  | (SchemaCommon & { type: "color"; default: string })
  | (SchemaCommon & { type: "enum"; default: string; options: string[] })
  | (SchemaCommon & { type: "asset"; default: string | null; kind?: "image" });

/**
 * A module's optional `schema` export: at most 64 keys, each letters, digits
 * and `_`, starting with a letter or `_`, at most 32 characters.
 */
type Schema = Record<string, SchemaEntry>;

/** What `measureText`, `wrapText`, `fitText` and `textLines` measure with. */
interface Font {
  /**
   * Default "Montserrat". A family that is not installed throws. The CSS
   * generics "serif" (Source Serif 4), "sans-serif" (Source Sans 3) and
   * "monospace" (IBM Plex Mono) are installed; "cursive" and "fantasy" are not.
   */
  family?: string;
  /** Default 16. */
  size?: number;
  /** Default 400. */
  weight?: number;
  /** Default "normal". */
  style?: string;
  /** Default 0. */
  letterSpacing?: number;
  /**
   * Default "default": runs of spaces collapse. "preserve" counts spaces
   * beside a drawn glyph, and `textLines` writes `xml:space="preserve"`.
   */
  xmlSpace?: "default" | "preserve";
}

/** `measureText`'s answer. */
interface TextMetrics {
  /** The advance: where the next word starts. */
  width: number;
  ascent: number;
  descent: number;
  lineHeight: number;
  /** Where the drawn glyphs start. */
  inkX: number;
  /** How wide the drawn glyphs are. */
  inkWidth: number;
}

/** Takes `t` in 0–1; exact at 0 and 1. */
type EasingFunction = (t: number) => number;

type Extrapolate = "extend" | "clamp" | "identity";

declare const Easing: {
  readonly linear: EasingFunction;
  /** A cubic Bézier through (0, 0), (x1, y1), (x2, y2), (1, 1). */
  bezier(x1: number, y1: number, x2: number, y2: number): EasingFunction;
  readonly inQuad: EasingFunction;
  readonly outQuad: EasingFunction;
  readonly inOutQuad: EasingFunction;
  readonly inCubic: EasingFunction;
  readonly outCubic: EasingFunction;
  readonly inOutCubic: EasingFunction;
  readonly inQuart: EasingFunction;
  readonly outQuart: EasingFunction;
  readonly inOutQuart: EasingFunction;
  readonly inExpo: EasingFunction;
  readonly outExpo: EasingFunction;
  readonly inOutExpo: EasingFunction;
  readonly inSine: EasingFunction;
  readonly outSine: EasingFunction;
  readonly inOutSine: EasingFunction;
  readonly inBack: EasingFunction;
  readonly outBack: EasingFunction;
  readonly inOutBack: EasingFunction;
  readonly inElastic: EasingFunction;
  readonly outElastic: EasingFunction;
  readonly inOutElastic: EasingFunction;
};

/** The root `<svg>` element with the right `width`, `height` and `viewBox`. */
declare function svg(ctx: Ctx, body: string, options?: { background?: string }): string;

/**
 * Maps `value` through matching `input` and `output` ranges (two or more
 * points, `input` ascending). Outside `input` it extends the end segment
 * unless `clamp: true`.
 */
declare function interpolate(
  value: number,
  input: number[],
  output: number[],
  options?: {
    easing?: EasingFunction;
    clamp?: boolean;
    extrapolateLeft?: Extrapolate;
    extrapolateRight?: Extrapolate;
  },
): number;

/** A physical spring from `from` to `to`, starting at frame 0. */
declare function spring(options: {
  frame: number;
  fps: number;
  /** Default 100. */
  stiffness?: number;
  /** Default 10. */
  damping?: number;
  /** Default 1. */
  mass?: number;
  /** Default 0. */
  from?: number;
  /** Default 1. */
  to?: number;
}): number;

/**
 * Blends colours in OKLab; `#rrggbb`, or `#rrggbbaa` when a colour has alpha.
 * Takes `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`,
 * `hsla()` and the CSS colour names; a value out of range throws.
 */
declare function interpolateColors(value: number, input: number[], colors: string[]): string;

/** A number in [0, 1) that depends only on `seed`. `Math.random` does not exist. */
declare function random(seed: number | string): number;

/** Simplex noise in about −1..1. */
declare function noise2D(seed: number | string, x: number, y: number): number;

/** Simplex noise in about −1..1; time as the third axis drifts smoothly. */
declare function noise3D(seed: number | string, x: number, y: number, z: number): number;

/** A point on a path and the way the path is heading there. */
interface PathPoint {
  x: number;
  y: number;
  /** Degrees, as SVG's `rotate()` takes them. */
  angle: number;
}

/** The length of the SVG path data `d`; a path that cannot be read throws. */
declare function getLength(d: string): number;

/** The point `length` along `d`, clamped to the path, and the heading there. */
declare function getPointAtLength(d: string, length: number): PathPoint;

/**
 * The dash that draws `d` from its start up to `progress` 0–1; the subpaths of
 * a path with several draw at once, the longest finishing at 1.
 */
declare function evolvePath(
  progress: number,
  d: string,
): { strokeDasharray: string; strokeDashoffset: number };

/** Measures `text` in a bundled or project font; an unknown family throws. */
declare function measureText(text: string, font?: Font): TextMetrics;

/** Lines that each fit `maxWidth`; a word longer than it breaks by characters. */
declare function wrapText(text: string, maxWidth: number, font?: Font): string[];

/** The largest whole font size at which `text` fits `maxWidth` on one line. */
declare function fitText(
  text: string,
  maxWidth: number,
  font?: Font,
  options?: { /** Default 8. */ min?: number; /** Default 400. */ max?: number },
): number;

/** A `<text>` with one `<tspan>` per line, the family quoted (a CSS generic bare). */
declare function textLines(
  lines: string[],
  options?: {
    x?: number;
    y?: number;
    /** Default 1.2 × the size. */
    lineHeight?: number;
    anchor?: "start" | "middle" | "end";
    fill?: string;
    font?: Font;
  },
): string;

/** Escapes `& < > " '`. */
declare function escapeXml(s: unknown): string;

/** Groups thousands; there is no `Intl`. */
declare function formatNumber(
  n: number,
  options?: { /** Default 0. */ decimals?: number; /** Default ",". */ separator?: string },
): string;

/** The href of a file in `graphics/assets/`, for `<image href="…">`. */
declare function asset(name: string): string;
