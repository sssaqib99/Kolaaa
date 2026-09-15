// Procedural hovercraft definitions for the web hangar preview.
// Mirrors hyperdrift/scripts/ship_factory.gd 1:1 (same primitives, sizes,
// positions, rotations, colors) so the browser preview matches the game.

export type PartKind = "box" | "cyl" | "sphere" | "torus";

export interface ShipPart {
  kind: PartKind;
  /** box:[w,h,d] cyl:[rTop,rBottom,h,seg] sphere:[r] torus:[inner,outer,rings,tubeSeg] */
  size: number[];
  pos: [number, number, number];
  /** degrees, applied in YXZ order like Godot */
  rot: [number, number, number];
  mat: string;
  scale?: [number, number, number];
  /** engine glow ring (pulsed every frame) */
  glow?: boolean;
}

export interface FlareDef {
  pos: [number, number, number];
  size: number;
  style: number;
}

export interface ShipDef {
  id: number;
  name: string;
  tagline: string;
  desc: string;
  accent: string;
  engine: string;
  specs: [string, string][];
  parts: ShipPart[];
  modelScale?: [number, number, number];
}

export const FLARE_LAYOUT: FlareDef[] = [
  { pos: [0, 0.0, 2.35], size: 2.5, style: 0 },
  { pos: [-1.95, 0.1, 0.8], size: 1.15, style: 1 },
  { pos: [1.95, 0.1, 0.8], size: 1.15, style: 2 },
  { pos: [-0.7, 0.48, 1.55], size: 0.72, style: 3 },
  { pos: [0.7, 0.48, 1.55], size: 0.72, style: 0 },
  { pos: [0, 0.42, -1.8], size: 0.6, style: 1 },
];

function vectorParts(): ShipPart[] {
  const parts: ShipPart[] = [
    { kind: "cyl", size: [0.0, 0.5, 2.0, 10], pos: [0, 0, -1.55], rot: [-90, 0, 0], mat: "hullV" },
    { kind: "cyl", size: [0.5, 0.44, 1.9, 10], pos: [0, 0, 0.4], rot: [-90, 0, 0], mat: "hullV" },
    {
      kind: "sphere", size: [0.4], pos: [0, 0.24, -0.35], rot: [0, 0, 0],
      mat: "glassV", scale: [0.85, 0.52, 1.5],
    },
  ];
  for (const s of [-1, 1]) {
    parts.push(
      { kind: "box", size: [1.7, 0.11, 1.05], pos: [s * 1.05, -0.04, 0.35], rot: [0, s * -9, s * 11], mat: "hullV" },
      { kind: "box", size: [0.16, 0.42, 0.9], pos: [s * 1.85, 0.1, 0.45], rot: [0, 0, s * 11], mat: "accentV" },
      { kind: "box", size: [1.3, 0.045, 0.16], pos: [s * 1.0, 0.035, 0.2], rot: [0, s * -9, s * 11], mat: "trimV" },
      { kind: "cyl", size: [0.26, 0.3, 1.25, 10], pos: [s * 0.62, -0.02, 1.05], rot: [-90, 0, 0], mat: "hullV" },
      {
        kind: "torus", size: [0.2, 0.3, 14, 6], pos: [s * 0.62, -0.02, 1.68],
        rot: [90, 0, 0], mat: "glowCyan", glow: true,
      },
    );
  }
  parts.push(
    { kind: "box", size: [0.1, 0.75, 0.9], pos: [0, 0.45, 1.05], rot: [-14, 0, 0], mat: "accentV" },
    { kind: "box", size: [0.6, 0.06, 2.4], pos: [0, -0.33, 0.1], rot: [0, 0, 0], mat: "glowCyanSoft" },
  );
  return parts;
}

function phantomParts(): ShipPart[] {
  const parts: ShipPart[] = [
    { kind: "box", size: [2.15, 0.46, 3.8], pos: [0, -0.05, 0.15], rot: [0, 0, 0], mat: "hullP" },
    { kind: "cyl", size: [0.0, 0.78, 2.2, 4], pos: [0, 0, -2.05], rot: [-90, 45, 0], mat: "hullP" },
    { kind: "box", size: [1.35, 0.46, 1.78], pos: [0, 0.3, -0.25], rot: [0, 0, 0], mat: "glassP" },
  ];
  for (const s of [-1, 1]) {
    parts.push(
      { kind: "box", size: [1.95, 0.09, 1.55], pos: [s * 1.5, -0.02, 0.3], rot: [0, s * -14, s * 13], mat: "hullP" },
      { kind: "box", size: [1.72, 0.05, 0.11], pos: [s * 1.48, 0.06, -0.08], rot: [0, s * -14, s * 13], mat: "chromeP" },
      { kind: "box", size: [0.11, 0.64, 0.86], pos: [s * 2.25, 0.25, 0.76], rot: [0, 0, s * 8], mat: "violetP" },
      { kind: "cyl", size: [0.3, 0.34, 1.15, 10], pos: [s * 0.78, -0.05, 1.58], rot: [-90, 0, 0], mat: "hullP" },
      {
        kind: "torus", size: [0.24, 0.34, 16, 6], pos: [s * 0.78, -0.05, 2.15],
        rot: [90, 0, 0], mat: "glowViolet", glow: true,
      },
    );
  }
  parts.push(
    { kind: "box", size: [0.22, 0.62, 1.4], pos: [0, 0.36, 1.08], rot: [-8, 0, 0], mat: "violetP" },
    { kind: "box", size: [0.32, 0.05, 2.55], pos: [0, -0.3, 0.1], rot: [0, 0, 0], mat: "chromeP" },
  );
  return parts;
}

export const SHIPS: ShipDef[] = [
  {
    id: 0,
    name: "VECTOR",
    tagline: "Agile neon interceptor  •  cyan engines",
    desc: "The original neon dart: cone nose, glass canopy, magenta winglets and twin cyan pods. Same fair collision and handling as Phantom — pure agility.",
    accent: "#2ef2ff",
    engine: "#2ef2ff",
    specs: [
      ["CLASS", "INTERCEPTOR"],
      ["HULL", "NEON DART"],
      ["ENGINES", "TWIN CYAN"],
      ["ACCENT", "MAGENTA + CYAN"],
      ["HANDLING", "IDENTICAL"],
    ],
    parts: vectorParts(),
  },
  {
    id: 1,
    name: "PHANTOM",
    tagline: "Art Deco heavy cruiser  •  violet engines",
    desc: "A lower, broader Art Deco cruiser: long wedge hull, swept chrome-edged wings, violet engine pods and an exhaust spine. Same fair collision and handling as Vector — pure presence.",
    accent: "#9e5cff",
    engine: "#9e5cff",
    specs: [
      ["CLASS", "HEAVY CRUISER"],
      ["HULL", "DECO WEDGE"],
      ["ENGINES", "TWIN VIOLET"],
      ["ACCENT", "CHROME + VIOLET"],
      ["HANDLING", "IDENTICAL"],
    ],
    parts: phantomParts(),
    modelScale: [1.08, 0.94, 1.06],
  },
];

export const SHIP_COUNT = SHIPS.length;
