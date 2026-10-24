// Fixtures that belong to the building, not to the person moving: RoomPlan detects them, and vision
// names them, but they're never sold, moved or priced. Shared by the sort and pricing agents.
// Accessories that only mention one (a sink caddy, a toilet brush, an oil radiator heater) are items.
const FIXTURE = /\b(toilets?|bathtubs?|bath tubs?|sinks?|washbasins?|fireplaces?|stairs?|staircases?|radiators?|showers?|shower stalls?|built-?ins?)\b/i;
const ACCESSORY = /\b(caddy|caddies|mats?|organizers?|strainers?|stoppers?|paper|brush(es)?|plungers?|cleaners?|towels?|racks?|shelf|shelves|curtains?|heads?|heaters?|portable|oil|covers?|seats? covers?|tools?|screens?|gates?)\b/i;

export function isBuiltInFixture(it: { name: string; category: string }): boolean {
  const text = `${it.name} ${it.category}`;
  return FIXTURE.test(text) && !ACCESSORY.test(text);
}
