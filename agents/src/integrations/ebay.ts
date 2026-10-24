import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { config } from '../config.js';

export type ListingInput = {
  listingId: bigint;
  title: string;
  description: string;
  priceCents: bigint;
  condition: string;
  category: string;
  photoUrls: string[];
};

export type PublishStep = { call: string; detail: string };

export type PublishResult = { externalId: string; url: string; simulated: boolean };

// One marketplace backend. publish() reports each API step through onStep so the agent can
// log it as an agentEvent, then resolves with the live listing's id and URL.
export interface EbayPoster {
  readonly simulated: boolean;
  publish(l: ListingInput, onStep: (s: PublishStep) => void): Promise<PublishResult>;
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

// Demo backend: walks the same Sell Inventory API sequence a real post would
// (inventory item -> offer -> publish), with realistic latency, but calls nothing.
// The "listing page" is a static HTML snapshot served by the worker's upload server,
// and every result is marked simulated (CLAUDE.md hard rule).
export const simulatedEbay: EbayPoster = {
  simulated: true,
  async publish(l, onStep) {
    const sku = `MOOVE-${l.listingId}`;
    const steps: PublishStep[] = [
      { call: 'createOrReplaceInventoryItem', detail: `SKU ${sku}, ${l.photoUrls.length} photo(s), condition ${l.condition || 'used'}` },
      { call: 'createOffer', detail: `Fixed price ${dollars(l.priceCents)}, category "${l.category || 'other'}"` },
      { call: 'publishOffer', detail: `Publishing offer for ${sku}` },
    ];
    for (const s of steps) {
      await sleep(700 + Math.random() * 900);
      onStep(s);
    }
    const externalId = String(Math.floor(1e11 + Math.random() * 9e11)); // eBay-style 12-digit item number
    const name = `listing-${l.listingId}.html`;
    await writeFile(path.join(config.uploadDir, name), listingPage(l, externalId));
    return { externalId, url: `${config.publicUploadBaseUrl}/files/${name}`, simulated: true };
  },
};

export function dollars(cents: bigint): string {
  return `$${(Number(cents) / 100).toFixed(2)}`;
}

const CONDITION_LABEL: Record<string, string> = {
  new: 'New',
  like_new: 'Like new',
  good: 'Used – good',
  fair: 'Used – fair',
  poor: 'For parts or not working',
};

function esc(s: string): string {
  return s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

// Listing text comes from Claude over scraped comps, so everything is escaped.
function listingPage(l: ListingInput, externalId: string): string {
  const photos = l.photoUrls.filter(u => /^https?:\/\//.test(u));
  const hero = photos[0] ? `<img class="hero" src="${esc(photos[0])}" alt="">` : '<div class="hero empty">No photo</div>';
  const thumbs = photos.slice(1, 6).map(u => `<img src="${esc(u)}" alt="">`).join('');
  const paragraphs = l.description.split(/\n{2,}/).map(p => `<p>${esc(p).replace(/\n/g, '<br>')}</p>`).join('');
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(l.title)}</title>
<style>
:root{--bg:#fff;--fg:#191919;--muted:#707070;--line:#e5e5e5;--accent:#3665f3;--chip:#f7f7f7}
@media (prefers-color-scheme:dark){:root{--bg:#121212;--fg:#f2f2f2;--muted:#a0a0a0;--line:#2c2c2c;--accent:#7b9bff;--chip:#1e1e1e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 -apple-system,system-ui,sans-serif}
.sim{background:#fff4ce;color:#5c4400;font-size:13px;padding:8px 16px;text-align:center}
main{max-width:720px;margin:0 auto;padding:16px}
.hero{width:100%;aspect-ratio:1;object-fit:cover;border-radius:12px;background:var(--chip);display:flex;align-items:center;justify-content:center;color:var(--muted)}
.thumbs{display:flex;gap:8px;margin-top:8px;overflow-x:auto}.thumbs img{width:64px;height:64px;object-fit:cover;border-radius:8px}
h1{font-size:22px;margin:16px 0 4px}.price{font-size:28px;font-weight:700;margin:8px 0}
.chips{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0 16px}.chip{background:var(--chip);border-radius:999px;padding:4px 12px;font-size:14px}
.live{color:#1a8a3a;font-weight:600}.btn{display:block;width:100%;border:0;border-radius:999px;padding:14px;font-size:17px;font-weight:600;margin:8px 0}
.buy{background:var(--accent);color:#fff}.watch{background:transparent;color:var(--accent);border:1px solid var(--accent)}
.meta{color:var(--muted);font-size:14px;border-top:1px solid var(--line);padding-top:12px;margin-top:16px}
h2{font-size:18px;margin:24px 0 8px}
</style></head><body>
<div class="sim">Demo listing — simulated post, not live on eBay</div>
<main>
${hero}
<div class="thumbs">${thumbs}</div>
<h1>${esc(l.title)}</h1>
<div class="price">${dollars(l.priceCents)}</div>
<div class="chips"><span class="chip live">● Live</span><span class="chip">${esc(CONDITION_LABEL[l.condition] ?? 'Used')}</span><span class="chip">Local pickup or shipping</span></div>
<button class="btn buy" disabled>Buy It Now</button>
<button class="btn watch" disabled>Add to watchlist</button>
<h2>About this item</h2>
${paragraphs}
<div class="meta">Item number ${externalId} · Listed by Moove agent · ${esc(l.category || 'Other')}</div>
</main></body></html>
`;
}
