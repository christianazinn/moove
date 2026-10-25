// Fixtures that belong to the building, not to the person moving: RoomPlan detects them, and vision
// names them, but they're never sold, moved or priced. Shared by the sort and pricing agents.
// Accessories that only mention one (a sink caddy, a toilet brush, an oil radiator heater, a door
// mat, a window fan) are items.
const FIXTURE = /\b(toilets?|bathtubs?|bath tubs?|sinks?|washbasins?|fireplaces?|stairs?|staircases?|radiators?|showers?|shower stalls?|built-?ins?|doors?|windows?|blinds?|shutters?|outlets?|vents?|countertops?)\b/i;
// Always part of the building, whatever else the name says (Rio's rooms, Oct 24: a ceiling fan
// with light kit, wall-mounted hotel towel racks and hair dryers).
const ALWAYS = /\b(ceiling (fans?|lights?)|light fixtures?|recessed lights?|curtain rods?|smoke detectors?|thermostats?|grab bars?)\b|\bwall[- ]mounted\b[^,;(]*\b(towel (bars?|racks?)|hair ?dryers?|soap dispensers?)\b/i;
const ACCESSORY = /\b(caddy|caddies|mats?|organizers?|strainers?|stoppers?|paper|brush(es)?|plungers?|cleaners?|towels?|racks?|shelf|shelves|curtains?|heads?|heaters?|portable|oil|covers?|seats? covers?|tools?|screens?|gates?|fans?|ac|air conditioners?|hangers?|hooks?|stops?|wedges?|knobs?|locks?)\b/i;

export function isBuiltInFixture(it: { name?: string; category?: string }): boolean {
  const name = it.name ?? '', category = it.category ?? '';
  // Accessory words only count in the head noun phrase: "bathtub with shower curtain" is a tub,
  // "shower curtain with rod" is a curtain.
  if (ALWAYS.test(`${name} ${category}`)) return true;
  const head = name.split(/\b(?:with|and|plus)\b|[,;(]/i)[0];
  return FIXTURE.test(`${name} ${category}`) && !ACCESSORY.test(`${head} ${category}`);
}
