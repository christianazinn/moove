// Does a name fit the box the scan measured? (#267)
//
// The photo sweep and the vision agent rename scanned items. A wrong rename sticks: on a real
// iPad scan a 1.5 m tall floor lamp came back as "pillow". Before an agent renames a scanned
// item, `renameMisfit()` checks the proposed name/category against the item's measured size and
// the agent keeps the old name when it can't be that thing. `scannedTwin()` stops the sweep from
// adding an object the scan already has under another name. Both are pure and make no model calls.

/** Typical size (m): the footprint's short and long side, and height. A missing bound isn't checked. */
export type SizeRange = { short?: [number, number]; long?: [number, number]; height?: [number, number] };

/** Slack on every bound, same as MooveKit ObjectSanity.tolerance, so a loose box still fits. */
export const TOLERANCE = 0.15;

// Mirrors MooveKit ObjectSanity.ranges (RoomPlan's categories). Keep in sync by hand.
const ROOMPLAN: Record<string, SizeRange> = {
  table: { short: [0.3, 1.8], long: [0.35, 3.6], height: [0.3, 1.2] },
  chair: { short: [0.3, 1.0], long: [0.35, 1.3], height: [0.4, 1.4] },
  sofa: { short: [0.5, 2.2], long: [0.8, 4.2], height: [0.35, 1.3] },
  bed: { short: [0.6, 2.3], long: [1.2, 2.6], height: [0.1, 2.0] },
  storage: { short: [0.1, 1.3], long: [0.25, 3.6], height: [0.15, 2.7] },
  refrigerator: { short: [0.4, 1.0], long: [0.45, 1.3], height: [0.45, 2.1] },
  television: { short: [0.02, 0.6], long: [0.4, 2.3], height: [0.25, 1.5] },
  stove: { short: [0.4, 1.0], long: [0.45, 1.6], height: [0.3, 1.2] },
  oven: { short: [0.4, 1.0], long: [0.45, 1.2], height: [0.3, 1.2] },
  dishwasher: { short: [0.4, 0.8], long: [0.45, 0.9], height: [0.55, 0.95] },
  washerdryer: { short: [0.4, 0.95], long: [0.5, 1.1], height: [0.6, 2.0] },
  sink: { short: [0.3, 1.0], long: [0.35, 2.6], height: [0.1, 1.2] },
  toilet: { short: [0.3, 0.9], long: [0.4, 1.0], height: [0.35, 1.1] },
  bathtub: { short: [0.5, 1.3], long: [0.9, 2.3], height: [0.25, 0.9] },
};

// Mirrors MooveKit StructureCheck.heightRange (the detector's extra classes): height only.
const DETECTOR_HEIGHT: Record<string, [number, number]> = {
  vacuum: [0.08, 1.4], bicycle: [0.5, 1.4], scooter: [0.3, 1.45], motorcycle: [0.8, 1.7], bench: [0.3, 1.1],
  'bean bag': [0.25, 1.2], suitcase: [0.3, 1.1], backpack: [0.2, 0.75], plant: [0.1, 2.6], microwave: [0.18, 0.55],
  laptop: [0.01, 0.45], lamp: [0.2, 2.2], basket: [0.08, 0.8], box: [0.05, 1.2], bin: [0.1, 1.0], 'trash can': [0.2, 1.2],
  stool: [0.3, 1.0], monitor: [0.2, 0.8], printer: [0.1, 0.7], fan: [0.2, 1.6], heater: [0.2, 1.0], guitar: [0.6, 1.4],
  piano: [0.8, 1.6], treadmill: [0.9, 1.8], 'exercise bike': [0.8, 1.6], stroller: [0.6, 1.3], 'room divider': [1.0, 2.2],
  'coat rack': [1.2, 2.0], 'clothes rack': [1.0, 2.0], 'shoe rack': [0.2, 1.2], speaker: [0.1, 1.3], toy: [0.05, 1.2],
};

// Agent-side additions: names the sweep/vision use that MooveKit has no range for. Generous on
// purpose; they only have to catch a name that clearly can't be the measured thing.
const EXTRA: Record<string, SizeRange> = {
  pillow: { short: [0.03, 0.8], long: [0.2, 1.6], height: [0.03, 0.5] },
  lamp: { long: [0.1, 1.8], height: [0.2, 2.2] },
  desk: { short: [0.3, 1.2], long: [0.6, 3.0], height: [0.5, 1.3] },
  nightstand: { short: [0.25, 0.75], long: [0.3, 0.9], height: [0.3, 0.9] },
  dresser: { short: [0.3, 0.8], long: [0.4, 2.2], height: [0.5, 1.9] },
  bookshelf: { short: [0.15, 0.6], long: [0.3, 2.5], height: [0.3, 2.6] },
  ottoman: { short: [0.25, 1.2], long: [0.3, 1.8], height: [0.2, 0.6] },
  mattress: { short: [0.6, 2.0], long: [1.2, 2.3], height: [0.05, 1.4] },
  rug: { height: [0.0, 0.15] },
  clock: { long: [0.1, 0.8], height: [0.1, 2.2] },
  vase: { long: [0.05, 0.6], height: [0.05, 1.0] },
};

export const RANGES: Record<string, SizeRange> = {
  ...Object.fromEntries(Object.entries(DETECTOR_HEIGHT).map(([k, h]) => [k, { height: h }])),
  ...ROOMPLAN,
  ...EXTRA,
};

// Words that mean one of the kinds above.
const ALIASES: Record<string, string> = {
  tv: 'television', fridge: 'refrigerator', 'mini fridge': 'refrigerator', freezer: 'refrigerator',
  washer: 'washerdryer', dryer: 'washerdryer', 'washing machine': 'washerdryer',
  couch: 'sofa', loveseat: 'sofa', sectional: 'sofa', futon: 'sofa', armchair: 'chair', recliner: 'chair',
  cushion: 'pillow', 'throw pillow': 'pillow', bookcase: 'bookshelf', shelf: 'bookshelf', shelves: 'bookshelf',
  'bedside table': 'nightstand', 'night stand': 'nightstand', 'chest of drawers': 'dresser',
  cabinet: 'storage', wardrobe: 'storage', 'trash bin': 'trash can', 'floor lamp': 'lamp', 'desk lamp': 'lamp',
  carpet: 'rug', mat: 'rug', pouf: 'ottoman', footstool: 'ottoman', luggage: 'suitcase', bike: 'bicycle', escooter: 'scooter',
  'coffee table': 'table', 'side table': 'table', 'end table': 'table', 'dining table': 'table',
  'office chair': 'chair', 'desk chair': 'chair', 'tv stand': 'storage', 'media console': 'storage',
};

// Trailing words that don't name the thing ("dining chair set", "speaker pair").
const FILLER = new Set(['set', 'pair', 'combo', 'unit', 'piece', 'pieces']);

function canon(word: string): string | undefined {
  if (ALIASES[word]) return ALIASES[word];
  if (RANGES[word]) return word;
  // plural: lamps -> lamp, shelves handled by ALIASES
  if (word.endsWith('s') && word.length > 3) return canon(word.slice(0, -1));
  return undefined;
}

/**
 * The kind a name or category names, or undefined if it isn't one we know a size for. English
 * puts the head noun last ("desk lamp" is a lamp, "lamp table" a table), so only the last one or
 * two words count; "(set of 2)", ", about 30" and "with ..." tails are cut first.
 */
export function kindOf(text: string): string | undefined {
  const s = text.toLowerCase().replace(/\(.*?\)/g, ' ').split(/,| with | for /)[0];
  let words = s.replace(/[^a-z\s]/g, ' ').split(/\s+/).filter(Boolean);
  while (words.length > 1 && FILLER.has(words.at(-1)!)) words = words.slice(0, -1);
  if (words.length === 0) return undefined;
  if (words.length >= 2) {
    const two = canon(words.slice(-2).join(' '));
    if (two) return two;
  }
  return canon(words.at(-1)!);
}

export type Box = { widthM: number; depthM: number; heightM: number };

const cm = (m: number) => (m < 1 ? `${Math.round(m * 100)} cm` : `${m.toFixed(2)} m`);
export const boxText = (b: Box) => `${b.widthM.toFixed(2)}×${b.depthM.toFixed(2)}×${b.heightM.toFixed(2)} m`;

function hasSize(b: Box): boolean {
  return [b.widthM, b.depthM, b.heightM].every(v => Number.isFinite(v) && v > 0.02);
}

/** Why a box can't be `kind` ("1.50 m height is too big"), or null if it fits or we can't tell. */
export function outOfRange(kind: string, b: Box): string | null {
  const r = RANGES[kind];
  if (!r || !hasSize(b)) return null;
  const short = Math.min(b.widthM, b.depthM);
  const long = Math.max(b.widthM, b.depthM);
  const check = (v: number, range: [number, number] | undefined, what: string) => {
    if (!range) return null;
    if (v < range[0] * (1 - TOLERANCE)) return `${cm(v)} ${what} is too small`;
    if (v > range[1] * (1 + TOLERANCE)) return `${cm(v)} ${what} is too big`;
    return null;
  };
  return check(short, r.short, 'footprint') ?? check(long, r.long, 'length') ?? check(b.heightM, r.height, 'height');
}

/**
 * Null when renaming `current` to `proposed` is plausible for its measured box; otherwise the
 * event message saying the old name is kept. A rename that keeps the kind (lamp -> "black floor
 * lamp") always passes, as does one to a kind with no known size.
 */
export function renameMisfit(
  current: Box & { name: string; category: string },
  proposed: { name: string; category: string }
): { message: string; kind: string; reason: string } | null {
  const before = new Set([kindOf(current.name), kindOf(current.category)].filter(Boolean));
  for (const kind of new Set([kindOf(proposed.name), kindOf(proposed.category)])) {
    if (!kind || before.has(kind)) continue;
    const reason = outOfRange(kind, current);
    if (reason) {
      const label = proposed.name || proposed.category;
      return {
        kind,
        reason: `${reason} for a ${kind}`,
        message: `Kept "${current.name}": "${label}" doesn't fit a ${boxText(current)} box (${reason} for a ${kind})`,
      };
    }
  }
  return null;
}

// Kinds the scanner and the sweep may name differently for one object (RoomPlan has no ottoman,
// nightstand or desk: those come out as table or storage).
const GROUPS: string[][] = [
  ['sofa', 'bench', 'ottoman', 'bean bag'],
  ['chair', 'stool', 'bench', 'ottoman'],
  ['table', 'desk', 'nightstand', 'ottoman'],
  ['storage', 'dresser', 'bookshelf', 'nightstand', 'ottoman', 'box', 'basket', 'bin'],
  ['bed', 'mattress'],
  ['television', 'monitor'],
  ['washerdryer', 'dishwasher'],
  ['stove', 'oven'],
];

function sameGroup(a: string, b: string): boolean {
  return a === b || GROUPS.some(g => g.includes(a) && g.includes(b));
}

function similarSize(a: Box, b: Box): boolean {
  if (!hasSize(a) || !hasSize(b)) return false;
  const close = (x: number, y: number) => Math.abs(x - y) <= 0.3 || Math.max(x, y) / Math.min(x, y) <= 1.6;
  return (
    close(Math.min(a.widthM, a.depthM), Math.min(b.widthM, b.depthM)) &&
    close(Math.max(a.widthM, a.depthM), Math.max(b.widthM, b.depthM)) &&
    close(a.heightM, b.heightM)
  );
}

const kindOrWord = (name: string, category: string) =>
  kindOf(name) ?? kindOf(category) ?? category.trim().toLowerCase();

/** True for an item that came from the scan (RoomPlan or the detector), not the photo sweep or the user. */
export const isScanned = (it: { scanObjectId: string }) => !!it.scanObjectId && !it.scanObjectId.startsWith('photo:');

/**
 * The scanned item a sweep find most likely duplicates: same kind (or kinds the scanner confuses,
 * see GROUPS) and a similar size (each of footprint short/long side and height within 0.3 m or
 * 1.6x). `taken` holds ids already explained (matched by the sweep or claimed by an earlier find),
 * so each scanned item absorbs at most one find. Undefined when the find looks new.
 */
export function scannedTwin<T extends Box & { id: bigint; name: string; category: string; scanObjectId: string }>(
  find: Box & { name: string; category: string },
  items: T[],
  taken: Set<bigint>
): T | undefined {
  const kind = kindOrWord(find.name, find.category);
  if (!kind) return undefined;
  return items.find(
    it => isScanned(it) && !taken.has(it.id) && sameGroup(kind, kindOrWord(it.name, it.category)) && similarSize(find, it)
  );
}
