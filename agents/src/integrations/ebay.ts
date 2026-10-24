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
  itemName: string;
  brand: string;
  material: string;
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

// ---------- real eBay (sandbox by default) ----------
// Plain fetch against the Sell Inventory / Account / Taxonomy REST APIs. Paths and fields were
// checked against eBay's OpenAPI specs (developer.ebay.com/develop/api/spec/*.json, Oct 2026).
// One-time seller setup (consent -> refresh token, business policies, location) lives in
// scripts/ebay-setup.ts; this module only needs the resulting env keys.

const env = (k: string) => process.env[k] ?? '';

export const ebayEnv = {
  production: env('EBAY_ENV') === 'production',
  get api() {
    return this.production ? 'https://api.ebay.com' : 'https://api.sandbox.ebay.com';
  },
  get site() {
    return this.production ? 'https://www.ebay.com' : 'https://sandbox.ebay.com';
  },
  marketplaceId: env('EBAY_MARKETPLACE_ID') || 'EBAY_US',
};

const SCOPE = 'https://api.ebay.com/oauth/api_scope';
export const USER_SCOPES = [SCOPE, `${SCOPE}/sell.inventory`, `${SCOPE}/sell.account`];

const REQUIRED_KEYS = [
  'EBAY_CLIENT_ID',
  'EBAY_CLIENT_SECRET',
  'EBAY_REFRESH_TOKEN',
  'EBAY_FULFILLMENT_POLICY_ID',
  'EBAY_PAYMENT_POLICY_ID',
  'EBAY_RETURN_POLICY_ID',
  'EBAY_LOCATION_KEY',
];

export function missingEbayKeys(): string[] {
  return REQUIRED_KEYS.filter(k => !env(k));
}

export class EbayError extends Error {
  constructor(
    readonly status: number,
    readonly body: unknown,
    what: string
  ) {
    const errs = (body as { errors?: { errorId?: number; message?: string; longMessage?: string }[] })?.errors;
    const detail = errs?.length ? errs.map(e => `${e.errorId}: ${e.longMessage ?? e.message}`).join('; ') : JSON.stringify(body).slice(0, 300);
    super(`${what} -> HTTP ${status}: ${detail}`);
  }
}

type Token = { value: string; expiresAt: number };
const tokens = new Map<string, Token>();

// grant_type=refresh_token (user token, for Sell APIs) or client_credentials (app token, for Taxonomy).
export async function oauthToken(body: Record<string, string>): Promise<{ access_token: string; expires_in: number; refresh_token?: string; refresh_token_expires_in?: number }> {
  const basic = Buffer.from(`${env('EBAY_CLIENT_ID')}:${env('EBAY_CLIENT_SECRET')}`).toString('base64');
  const res = await fetch(`${ebayEnv.api}/identity/v1/oauth2/token`, {
    method: 'POST',
    headers: { authorization: `Basic ${basic}`, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new EbayError(res.status, json, `oauth ${body.grant_type}`);
  return json as never;
}

async function accessToken(kind: 'user' | 'app'): Promise<string> {
  const cached = tokens.get(kind);
  if (cached && cached.expiresAt > Date.now() + 60_000) return cached.value;
  const t =
    kind === 'user'
      ? await oauthToken({ grant_type: 'refresh_token', refresh_token: env('EBAY_REFRESH_TOKEN'), scope: USER_SCOPES.join(' ') })
      : await oauthToken({ grant_type: 'client_credentials', scope: SCOPE });
  tokens.set(kind, { value: t.access_token, expiresAt: Date.now() + t.expires_in * 1000 });
  return t.access_token;
}

export async function ebayCall<T = unknown>(
  method: string,
  pathAndQuery: string,
  opts: { body?: unknown; token?: 'user' | 'app' | string; okStatuses?: number[] } = {}
): Promise<T> {
  const token = opts.token === 'app' || opts.token === 'user' || opts.token === undefined ? await accessToken(opts.token ?? 'user') : opts.token;
  const res = await fetch(`${ebayEnv.api}${pathAndQuery}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/json',
      'accept-language': 'en-US',
      'content-language': 'en-US',
      ...(opts.body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok && !opts.okStatuses?.includes(res.status)) throw new EbayError(res.status, json, `${method} ${pathAndQuery.split('?')[0]}`);
  return json as T;
}

// ---- category: pick a leaf from the marketplace's real category tree ----
// getCategorySuggestions isn't supported in sandbox, and sandbox trees can lag production, so
// we pull a few subtrees once and match leaves by name. IDs never need to be hardcoded.
const PARENT_CATEGORIES = ['3197' /* Furniture */, '11700' /* Home & Garden */, '293' /* Consumer Electronics */];

// RoomPlan / vision categories -> words that appear in matching eBay leaf names.
const CATEGORY_HINTS: Record<string, string[]> = {
  chair: ['chairs', 'office chairs'],
  sofa: ['sofas', 'loveseats', 'bean bags'],
  table: ['desks', 'tables', 'home office desks'],
  desk: ['desks', 'home office desks'],
  storage: ['bookcases', 'cabinets', 'dressers', 'shelving'],
  bookshelf: ['bookcases', 'shelving'],
  dresser: ['dressers', 'chests of drawers'],
  nightstand: ['nightstands', 'night stands'],
  bench: ['benches'],
  ottoman: ['ottomans', 'footstools'],
  bed: ['beds', 'bed frames'],
  lamp: ['lamps', 'floor lamps'],
  appliance: ['refrigerators', 'mini fridges', 'fans', 'appliances'],
  refrigerator: ['refrigerators', 'mini fridges'],
  stove: ['ranges', 'stoves', 'ovens'],
  microwave: ['microwaves'],
  dishwasher: ['dishwashers'],
  washerdryer: ['washers', 'dryers'],
  television: ['televisions'],
  decor: ['decor', 'mirrors', 'wall art'],
  furniture: ['furniture'],
  electronics: ['electronics'],
};

type Leaf = { id: string; name: string; path: string };
let leavesPromise: Promise<Leaf[]> | undefined;

type TreeNode = { category: { categoryId: string; categoryName: string }; leafCategoryTreeNode?: boolean; childCategoryTreeNodes?: TreeNode[] };

async function loadLeaves(): Promise<Leaf[]> {
  const { categoryTreeId } = await ebayCall<{ categoryTreeId: string }>(
    'GET',
    `/commerce/taxonomy/v1/get_default_category_tree_id?marketplace_id=${ebayEnv.marketplaceId}`,
    { token: 'app' }
  );
  const leaves: Leaf[] = [];
  const walk = (n: TreeNode, path: string) => {
    const p = path ? `${path} > ${n.category.categoryName}` : n.category.categoryName;
    if (n.leafCategoryTreeNode) leaves.push({ id: n.category.categoryId, name: n.category.categoryName, path: p });
    n.childCategoryTreeNodes?.forEach(c => walk(c, p));
  };
  for (const id of PARENT_CATEGORIES) {
    try {
      const sub = await ebayCall<{ categorySubtreeNode: TreeNode }>(
        'GET',
        `/commerce/taxonomy/v1/category_tree/${categoryTreeId}/get_category_subtree?category_id=${id}`,
        { token: 'app' }
      );
      walk(sub.categorySubtreeNode, '');
    } catch (err) {
      console.warn(`[ebay] category subtree ${id} unavailable: ${String(err)}`);
    }
  }
  if (leaves.length === 0) throw new Error('no eBay leaf categories could be loaded');
  return [...new Map(leaves.map(l => [l.id, l])).values()];
}

const words = (s: string) => s.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 2);

export function pickLeaf(leaves: Leaf[], category: string, itemName: string): Leaf {
  const hints = CATEGORY_HINTS[category.toLowerCase()] ?? [];
  const want = new Set([...words(itemName), ...words(category), ...hints.flatMap(words)]);
  let best = leaves[0];
  let bestScore = -1;
  for (const l of leaves) {
    const nameWords = words(l.name);
    let score = nameWords.filter(w => want.has(w) || want.has(w.replace(/s$/, ''))).length * 3;
    score += words(l.path).filter(w => want.has(w)).length;
    if (hints.some(h => l.name.toLowerCase() === h)) score += 5;
    if (score > bestScore || (score === bestScore && l.path.length < best.path.length)) {
      best = l;
      bestScore = score;
    }
  }
  return best;
}

// ---- item specifics: fill every required aspect so publish doesn't fail ----
type AspectMeta = {
  localizedAspectName: string;
  aspectConstraint: { aspectRequired?: boolean; aspectMode?: 'FREE_TEXT' | 'SELECTION_ONLY' };
  aspectValues?: { localizedValue: string }[];
};

async function requiredAspects(categoryId: string, l: ListingInput): Promise<Record<string, string[]>> {
  const { categoryTreeId } = await ebayCall<{ categoryTreeId: string }>(
    'GET',
    `/commerce/taxonomy/v1/get_default_category_tree_id?marketplace_id=${ebayEnv.marketplaceId}`,
    { token: 'app' }
  );
  const meta = await ebayCall<{ aspects?: AspectMeta[] }>(
    'GET',
    `/commerce/taxonomy/v1/category_tree/${categoryTreeId}/get_item_aspects_for_category?category_id=${categoryId}`,
    { token: 'app', okStatuses: [204] }
  );
  const known: Record<string, string> = { brand: l.brand || 'Unbranded', material: l.material, type: l.itemName };
  const text = `${l.itemName} ${l.material} ${l.title}`.toLowerCase();
  const out: Record<string, string[]> = {};
  for (const a of meta.aspects ?? []) {
    if (!a.aspectConstraint.aspectRequired) continue;
    const name = a.localizedAspectName;
    const values = (a.aspectValues ?? []).map(v => v.localizedValue);
    if (a.aspectConstraint.aspectMode === 'SELECTION_ONLY' && values.length) {
      out[name] = [values.find(v => text.includes(v.toLowerCase())) ?? values.find(v => v === known[name.toLowerCase()]) ?? values[0]];
    } else {
      out[name] = [(known[name.toLowerCase()] || values.find(v => text.includes(v.toLowerCase())) || 'Does not apply').slice(0, 65)];
    }
  }
  if (!out.Brand) out.Brand = [l.brand || 'Unbranded'];
  return out;
}

// Vision agent condition -> Inventory API ConditionEnum. Most furniture/home leaves accept only
// NEW or "Used" (USED_EXCELLENT = condition ID 3000), so used grades collapse to that; the
// real grade is in the description.
function conditionEnum(c: string): string {
  return c === 'new' ? 'NEW' : 'USED_EXCELLENT';
}

function imageUrls(l: ListingInput): string[] {
  const https = l.photoUrls.filter(u => u.startsWith('https://')).slice(0, 12);
  if (https.length) return https;
  if (env('EBAY_FALLBACK_IMAGE_URL')) return [env('EBAY_FALLBACK_IMAGE_URL')];
  throw new Error('eBay needs at least one public https photo URL: set PUBLIC_UPLOAD_BASE_URL to an https tunnel, or EBAY_FALLBACK_IMAGE_URL');
}

type OfferSummary = { offerId: string; status?: string; listing?: { listingId?: string } };

export const sandboxEbay: EbayPoster = {
  simulated: false,
  async publish(l, onStep) {
    const sku = `MOOVE-${l.listingId}`;
    const images = imageUrls(l);
    leavesPromise ??= loadLeaves().catch(err => {
      leavesPromise = undefined;
      throw err;
    });
    const leaf = pickLeaf(await leavesPromise, l.category, l.itemName);
    const aspects = await requiredAspects(leaf.id, l);
    onStep({ call: 'getItemAspectsForCategory', detail: `${leaf.path} (#${leaf.id}), ${Object.keys(aspects).length} required item specific(s)` });

    await ebayCall('PUT', `/sell/inventory/v1/inventory_item/${encodeURIComponent(sku)}`, {
      body: {
        availability: { shipToLocationAvailability: { quantity: 1 } },
        condition: conditionEnum(l.condition),
        product: { title: l.title.slice(0, 80), description: l.description, aspects, imageUrls: images },
      },
    });
    onStep({ call: 'createOrReplaceInventoryItem', detail: `SKU ${sku}, ${images.length} photo(s), ${conditionEnum(l.condition)}` });

    const offer = {
      sku,
      marketplaceId: ebayEnv.marketplaceId,
      format: 'FIXED_PRICE',
      availableQuantity: 1,
      categoryId: leaf.id,
      listingDescription: l.description,
      listingDuration: 'GTC',
      merchantLocationKey: env('EBAY_LOCATION_KEY'),
      pricingSummary: { price: { value: (Number(l.priceCents) / 100).toFixed(2), currency: 'USD' } },
      listingPolicies: {
        fulfillmentPolicyId: env('EBAY_FULFILLMENT_POLICY_ID'),
        paymentPolicyId: env('EBAY_PAYMENT_POLICY_ID'),
        returnPolicyId: env('EBAY_RETURN_POLICY_ID'),
      },
    };
    // Retries reuse the SKU's existing offer (a second createOffer for the same SKU fails).
    const existing = await ebayCall<{ offers?: OfferSummary[] }>('GET', `/sell/inventory/v1/offer?sku=${encodeURIComponent(sku)}&marketplace_id=${ebayEnv.marketplaceId}`, {
      okStatuses: [404],
    });
    let offerId = existing.offers?.[0]?.offerId;
    const publishedId = existing.offers?.[0]?.status === 'PUBLISHED' ? existing.offers[0].listing?.listingId : undefined;
    if (publishedId) {
      onStep({ call: 'getOffers', detail: `SKU ${sku} is already live as #${publishedId}` });
      return { externalId: publishedId, url: `${ebayEnv.site}/itm/${publishedId}`, simulated: false };
    }
    if (offerId) {
      await ebayCall('PUT', `/sell/inventory/v1/offer/${offerId}`, { body: offer });
    } else {
      offerId = (await ebayCall<{ offerId: string }>('POST', '/sell/inventory/v1/offer', { body: offer })).offerId;
    }
    onStep({ call: 'createOffer', detail: `Offer ${offerId}: fixed price ${dollars(l.priceCents)} in ${leaf.name}` });

    const { listingId } = await ebayCall<{ listingId: string }>('POST', `/sell/inventory/v1/offer/${offerId}/publish`);
    onStep({ call: 'publishOffer', detail: `Live on eBay${ebayEnv.production ? '' : ' sandbox'} as #${listingId}` });
    return { externalId: listingId, url: `${ebayEnv.site}/itm/${listingId}`, simulated: false };
  },
};

// Real eBay when every key from scripts/ebay-setup.ts is set, otherwise the labeled simulation.
export function chooseEbay(): EbayPoster {
  const missing = missingEbayKeys();
  if (missing.length === 0) {
    console.log(`[ebay] using real eBay ${ebayEnv.production ? 'PRODUCTION' : 'sandbox'}`);
    return sandboxEbay;
  }
  console.log(`[ebay] simulated posting (missing ${missing.join(', ')})`);
  return simulatedEbay;
}
