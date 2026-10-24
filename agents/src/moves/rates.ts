// Mover rate table for POST /moves/quotes. Deterministic, no network: every quote built here is an
// ESTIMATE from typical published rates, never a real quote (kind "estimate", estimate: true).
// Mirrored on the phone in ios/MooveKit/Sources/MooveKit/Packing/MoverRates.swift (offline fallback).
// Keep the two in sync: both test suites check the same golden numbers (test/mover-quotes.test.ts,
// MoverRatesTests.swift).
//
// Sources (typical published rates, looked up 2026-10-24; real prices vary by city, date and access):
//   - DIY truck: U-Haul "In-Town" rates, $19.95 (cargo van, 10 ft), $29.95 (15 ft), $39.95 (20/26 ft)
//     per day plus a per-mile fee, about $0.79-$1.59 a mile by market (uhaul.com/Trucks). Fuel at
//     ~10 mpg and $3.50-$5.00/gal; damage protection $15-$30.
//   - Labor-only crew: HireAHelper city pages list ~$74-$93 an hour for a 2-person loading crew
//     (hireahelper.com/movers/...), so $35-$50 per mover-hour, 2 h minimum. You rent and drive the truck.
//   - Full-service local movers: $110-$180 an hour for 2 movers and a truck (Bellhops, Taskrabbit and
//     2026 cost guides), so $60-$90 per mover-hour with the truck included, 3 h minimum, plus about an
//     hour of travel time.

export type TruckSize = 'cargoVan' | 'ft10' | 'ft15' | 'ft20' | 'ft26';
export const TRUCK_SIZES: readonly TruckSize[] = ['cargoVan', 'ft10', 'ft15', 'ft20', 'ft26'];
export const TRUCK_LABEL: Record<TruckSize, string> = {
  cargoVan: 'cargo van',
  ft10: '10 ft truck',
  ft15: '15 ft truck',
  ft20: '20 ft truck',
  ft26: '26 ft truck',
};

export const MOVER_RATES = {
  asOf: '2026-10-24',
  /** Truck rental day rate in cents, by size. */
  truckDayCents: { cargoVan: 1995, ft10: 1995, ft15: 2995, ft20: 3995, ft26: 3995 } as Record<TruckSize, number>,
  /** Per-mile fee range in cents. */
  mileCents: [79, 159] as const,
  /** Fuel: miles per gallon and price per gallon (cents). */
  mpg: 10,
  fuelCentsPerGal: [350, 500] as const,
  /** Damage protection per truck (cents). */
  protectionCents: [1500, 3000] as const,
  /** Miles driven when the request doesn't say (pickup, both homes, return). */
  defaultMiles: 25,
  labor: { perMoverHourCents: [3500, 5000] as const, minHours: 2 },
  full: { perMoverHourCents: [6000, 9000] as const, minHours: 3, travelHours: 1 },
  sources: [
    { name: 'U-Haul in-town truck rates', url: 'https://www.uhaul.com/Trucks' },
    { name: 'HireAHelper labor-only rates', url: 'https://www.hireahelper.com/movers/los-angeles_ca/move-help' },
    { name: 'Taskrabbit mover cost guide', url: 'https://www.taskrabbit.com/cost-guides/help-moving' },
  ],
};

export interface QuoteInput {
  volumeM3: number;
  truckSize: TruckSize;
  trucks: number;
  crew: number;
  hours: number;
  miles?: number;
}

export type MoverType = 'diy' | 'labor' | 'full';
export interface MoverQuote {
  id: string;
  kind: 'estimate' | 'listed rate';
  moverType: MoverType;
  provider: string;
  lowCents: number;
  highCents: number;
  includes: string[];
  assumptions: string[];
  /** Always true here: nothing from this endpoint is a booked or binding quote. */
  estimate: true;
  /** Nothing is made up, so never simulated; estimates are labeled by `kind` / `estimate`. */
  simulated: false;
  source: { name: string; url?: string };
}

/** Low down, high up, to the nearest $10, so a range never looks more precise than it is. */
export const roundLow = (cents: number) => Math.floor(cents / 1000) * 1000;
export const roundHigh = (cents: number) => Math.ceil(cents / 1000) * 1000;

const hrs = (h: number) => `${Number.isInteger(h) ? h : h.toFixed(1)} h`;

/** DIY truck cost range in cents (unrounded): day rate + miles + fuel + protection, per truck. */
export function truckCostCents(q: QuoteInput): [number, number] {
  const r = MOVER_RATES;
  const miles = q.miles ?? r.defaultMiles;
  const n = Math.max(1, q.trucks);
  const one = (i: 0 | 1) => r.truckDayCents[q.truckSize] + miles * r.mileCents[i] + (miles * r.fuelCentsPerGal[i]) / r.mpg + r.protectionCents[i];
  return [n * one(0), n * one(1)];
}

/** The three rate-table estimates: DIY truck rental, labor-only movers, full-service local movers. */
export function estimateQuotes(q: QuoteInput): MoverQuote[] {
  const r = MOVER_RATES;
  const miles = q.miles ?? r.defaultMiles;
  const n = Math.max(1, q.trucks);
  const truck = n > 1 ? `${n} × ${TRUCK_LABEL[q.truckSize]}` : TRUCK_LABEL[q.truckSize];
  const [tLow, tHigh] = truckCostCents(q);
  const milesNote = `${miles} miles of driving${q.miles === undefined ? ' (assumed, local move)' : ''}`;
  const laborH = Math.max(q.hours, r.labor.minHours);
  const fullH = Math.max(q.hours + r.full.travelHours, r.full.minHours);
  const src = (i: number) => ({ name: r.sources[i].name, url: r.sources[i].url });
  return [
    {
      id: 'estimate-diy',
      kind: 'estimate',
      moverType: 'diy',
      provider: 'DIY truck rental',
      lowCents: roundLow(tLow),
      highCents: roundHigh(tHigh),
      includes: [`${truck} for a day`, 'Mileage, fuel and damage protection', 'You load, drive and unload'],
      assumptions: [milesNote, `$${(r.mileCents[0] / 100).toFixed(2)}-$${(r.mileCents[1] / 100).toFixed(2)} a mile`],
      estimate: true,
      simulated: false,
      source: src(0),
    },
    {
      id: 'estimate-labor',
      kind: 'estimate',
      moverType: 'labor',
      provider: 'Labor-only movers',
      lowCents: roundLow(q.crew * laborH * r.labor.perMoverHourCents[0] + tLow),
      highCents: roundHigh(q.crew * laborH * r.labor.perMoverHourCents[1] + tHigh),
      includes: [`${q.crew} movers load and unload, ~${hrs(laborH)}`, `${truck} rental (you drive)`],
      assumptions: [`$${r.labor.perMoverHourCents[0] / 100}-$${r.labor.perMoverHourCents[1] / 100} per mover-hour, ${r.labor.minHours} h minimum`, milesNote],
      estimate: true,
      simulated: false,
      source: src(1),
    },
    {
      id: 'estimate-full',
      kind: 'estimate',
      moverType: 'full',
      provider: 'Full-service local movers',
      lowCents: roundLow(q.crew * fullH * r.full.perMoverHourCents[0]),
      highCents: roundHigh(q.crew * fullH * r.full.perMoverHourCents[1]),
      includes: [`${q.crew} movers and their truck, ~${hrs(fullH)} with travel`, 'Loading, driving, unloading', 'Furniture pads and basic coverage'],
      assumptions: [`$${r.full.perMoverHourCents[0] / 100}-$${r.full.perMoverHourCents[1] / 100} per mover-hour, ${r.full.minHours} h minimum`, `${r.full.travelHours} h travel time`],
      estimate: true,
      simulated: false,
      source: src(2),
    },
  ];
}
