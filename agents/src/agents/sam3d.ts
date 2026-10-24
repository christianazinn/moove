import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import { config } from '../config.js';
import { logEvent } from '../events.js';
import { loadImage, structuredCall } from '../integrations/anthropic.js';
import type { ImageInput } from '../integrations/photos.js';
import { imageSize } from '../integrations/imagesize.js';
import { compImages, IMAGE_SEARCH_ACTOR, loadWebImage, searchProductImages, type ImageSearchResult, type WebImage } from '../integrations/product-images.js';
import { reconstruct, SAM3D_MODEL, type Sam3dRequest, type Sam3dResult } from '../integrations/sam3d.js';
import { queryFor } from './pricing.js';
import {
  buildPickPrompt,
  fallbackOrder,
  isSpecificProduct,
  photoKind,
  PICK_SCHEMA,
  PICK_SYSTEM,
  rankCandidates,
  type Candidate,
  type PickOutput,
  type Ranked,
} from './sam3d-select.js';

const inFlight = new Set<bigint>();
// Items that got a new photo while their model was being built: re-queued when the build ends.
const stale = new Set<bigint>();
let spentUsd = 0;

/** Own photos sent to the picker: the scan crop plus the newest few. */
const MAX_OWN_PHOTOS = 5;

/** Everything the build talks to, so tests can swap in fakes. */
export interface Sam3dDeps {
  loadPhoto(url: string): Promise<ImageInput>;
  loadWebImage(url: string): Promise<ImageInput>;
  compImages(query: string, max: number): WebImage[];
  searchImages(query: string): Promise<ImageSearchResult>;
  pick(opts: { model: string; system: string; text: string; images: ImageInput[] }): Promise<PickOutput>;
  reconstruct(req: Sam3dRequest): Promise<Sam3dResult>;
  /** Stores the GLB and returns its public URL. */
  saveGlb(glb: Buffer): Promise<string>;
}

export const defaultDeps: Sam3dDeps = {
  loadPhoto: loadImage,
  loadWebImage: url => loadWebImage(url),
  compImages,
  searchImages: q => searchProductImages(q),
  pick: o => structuredCall({ ...o, schema: PICK_SCHEMA, effort: 'low', maxTokens: 8000 }),
  reconstruct: req => reconstruct(req),
  async saveGlb(glb) {
    const name = `${randomUUID()}.glb`;
    await writeFile(path.join(config.uploadDir, name), glb);
    return `${config.publicUploadBaseUrl}/files/${name}`;
  },
};

let currentDeps: Sam3dDeps = defaultDeps;
/** Test hook: swap the integrations the agent uses. */
export function setSam3dDeps(d: Partial<Sam3dDeps>): void {
  currentDeps = { ...defaultDeps, ...d };
}

/** Test hook: forget what this worker run has spent and what's in flight. */
export function resetSam3dState(): void {
  spentUsd = 0;
  inFlight.clear();
  stale.clear();
}

/** Items that should get a SAM 3D model: a photo, vision finished (so the prompt is the real
 *  name), no captured model, and not already being built. */
export function needsModel(it: Item): boolean {
  return (
    it.modelStatus === 'pending' &&
    it.modelSource !== 'capture' &&
    it.photoUrls.length > 0 &&
    (it.detailsStatus === 'done' || it.detailsStatus === 'failed') &&
    !inFlight.has(it.id)
  );
}

/** What to segment in the photo: the vision name, falling back to the RoomPlan category. */
export function promptFor(it: Item): string {
  // Names are short product descriptions ("IKEA Kallax 2x4 shelf, white"). Keep it short; the
  // prompt only steers segmentation.
  const text = (it.name || it.category).replace(/[^\p{L}\p{N} ,.'-]/gu, ' ').trim();
  return text.slice(0, 80) || it.category || 'object';
}

const canSpend = (usd: number) => spentUsd + usd <= config.sam3d.maxUsd + 1e-9;
const money = (usd: number) => `$${usd.toFixed(usd < 0.1 ? 3 : 2)}`;

function sizeOf(img: ImageInput) {
  return imageSize(Buffer.from(img.data.slice(0, 200_000), 'base64'));
}

/** Loads the item's own photos: the first (the scan crop, if any) and the newest few. */
async function ownCandidates(it: Item, deps: Sam3dDeps): Promise<{ list: Omit<Candidate, 'n'>[]; failed: number }> {
  const idx = it.photoUrls.map((_u, i) => i);
  const pickIdx = [...new Set([...(photoKind(it, 0) === 'scan' ? [0] : []), ...idx.slice(-MAX_OWN_PHOTOS)])].slice(-MAX_OWN_PHOTOS);
  const loaded = await Promise.allSettled(pickIdx.map(i => deps.loadPhoto(it.photoUrls[i])));
  const list: Omit<Candidate, 'n'>[] = [];
  loaded.forEach((r, k) => {
    if (r.status !== 'fulfilled') return;
    const i = pickIdx[k];
    list.push({ kind: photoKind(it, i), url: it.photoUrls[i], image: r.value, size: sizeOf(r.value), photoIndex: i });
  });
  return { list, failed: loaded.length - list.length };
}

/** Web images for an identified product: cached comp photos (free), then an image search. */
async function webCandidates(conn: Conn, it: Item, deps: Sam3dDeps): Promise<Omit<Candidate, 'n'>[]> {
  const q = queryFor(it);
  const max = config.sam3d.webImagesMax;
  const found: WebImage[] = deps.compImages(q, Math.ceil(max / 2));
  // The search is only worth it if a SAM 3D run is still affordable after it.
  if (canSpend(config.sam3d.imageSearchMaxUsd + config.sam3d.usdPerRun)) {
    try {
      const r = await deps.searchImages(q);
      spentUsd += r.costUsd;
      for (const w of r.images) if (!found.some(f => f.url === w.url)) found.push(w);
      logEvent(conn, {
        owner: it.owner, agent: 'sam3d', kind: 'tool_call',
        message: r.replayed
          ? `[REPLAYED] Product images for "${q}": ${r.images.length} cached`
          : `Image search for "${q}" (Apify ${IMAGE_SEARCH_ACTOR}): ${r.images.length} found, ${money(r.costUsd)}`,
        refTable: 'item', refId: it.id,
        data: { query: q, actor: IMAGE_SEARCH_ACTOR, replayed: r.replayed, found: r.images.length, costUsd: r.costUsd, spentUsd, capUsd: config.sam3d.maxUsd },
      });
    } catch (err) {
      logEvent(conn, { owner: it.owner, agent: 'sam3d', kind: 'error', message: `Image search for "${q}" failed, using photos${found.length ? ' and listing images' : ''}: ${String(err)}`, refTable: 'item', refId: it.id });
    }
  }
  const pickWeb = found.slice(0, max);
  const loaded = await Promise.allSettled(pickWeb.map(w => deps.loadWebImage(w.url)));
  const list: Omit<Candidate, 'n'>[] = [];
  loaded.forEach((r, k) => {
    if (r.status === 'fulfilled') list.push({ kind: 'web', url: pickWeb[k].url, image: { mediaType: r.value.mediaType, data: r.value.data }, size: sizeOf(r.value), web: pickWeb[k] });
  });
  return list;
}

/** Where a candidate came from, for events and the app. */
function describe(c: Candidate): string {
  if (c.kind === 'web') return `web image (${c.web?.source ?? 'web'})`;
  return c.kind === 'scan' ? 'scan photo' : `photo ${(c.photoIndex ?? 0) + 1}`;
}

function sourceData(c: Candidate) {
  return {
    source: c.kind, // scan | user | web
    image: c.n,
    ...(c.kind === 'web' ? { webSource: c.web?.source, imageUrl: c.url, page: c.web?.origin } : { photoIndex: c.photoIndex }),
  };
}

export async function build(conn: Conn, it: Item, deps: Sam3dDeps = currentDeps): Promise<void> {
  inFlight.add(it.id);
  stale.delete(it.id);
  const ev = (kind: 'plan' | 'tool_call' | 'result' | 'error', message: string, data?: unknown) =>
    logEvent(conn, { owner: it.owner, agent: 'sam3d', kind, message, refTable: 'item', refId: it.id, data });
  try {
    const fal = config.sam3d.usdPerRun;
    if (!canSpend(fal)) {
      ev('error', `Spend cap reached (${money(config.sam3d.maxUsd)}): not building a 3D model of "${it.name}"`, { refused: true, spentUsd, capUsd: config.sam3d.maxUsd });
      return;
    }
    conn.reducers.setItemStage({ itemId: it.id, stage: 'running', field: 'model' });
    const prompt = promptFor(it);
    const web = config.sam3d.webImages && config.sam3d.webImagesMax > 0 && isSpecificProduct(it);
    ev('plan', `Building a 3D model of "${prompt}": choosing the best of its ${it.photoUrls.length} photo(s)${web ? ' and web images of the product' : ''}`, { photos: it.photoUrls.length, webSearch: web });

    // 1. Candidates.
    const own = await ownCandidates(it, deps);
    const webList = web ? await webCandidates(conn, it, deps) : [];
    const candidates: Candidate[] = [...own.list, ...webList].map((c, i) => ({ ...c, n: i + 1 }));
    if (own.list.length === 0 && webList.length === 0) throw new Error('none of the photos could be loaded');

    // 2. Choose. One own photo and nothing else: nothing to choose between, skip Claude.
    let order: Ranked[];
    if (candidates.length === 1) {
      order = fallbackOrder(candidates);
    } else if (!canSpend(config.sam3d.selectUsd + fal)) {
      order = fallbackOrder(candidates);
      ev('error', `Spend cap nearly reached: skipping the image pick, using the newest photo`, { refused: true, spentUsd, capUsd: config.sam3d.maxUsd });
    } else {
      spentUsd += config.sam3d.selectUsd;
      ev('tool_call', `Claude (${config.models.vision}) choosing among ${candidates.length} images (${own.list.length} photo(s), ${webList.length} web), about ${money(config.sam3d.selectUsd)}`, {
        model: config.models.vision, images: candidates.length, own: own.list.length, web: webList.length, costUsd: config.sam3d.selectUsd, spentUsd, capUsd: config.sam3d.maxUsd,
      });
      try {
        const out = await deps.pick({ model: config.models.vision, system: PICK_SYSTEM, text: buildPickPrompt(it, candidates), images: candidates.map(c => c.image) });
        const { ranked, rejected } = rankCandidates(candidates, out);
        order = ranked.length ? ranked : fallbackOrder(candidates);
        const best = order[0];
        ev('result', `Best image for 3D: ${describe(best.candidate)} (${best.score}/10${best.reason ? `, ${best.reason}` : ''})${rejected.length ? `; rejected ${rejected.length} web image(s)` : ''}`, {
          chosen: sourceData(best.candidate),
          box: best.box ?? null,
          ranking: order.map(r => ({ ...sourceData(r.candidate), score: r.score, reason: r.reason })),
          rejected,
        });
      } catch (err) {
        order = fallbackOrder(candidates);
        ev('error', `Image pick failed, using the newest photo: ${String(err)}`);
      }
    }
    if (order.length === 0) throw new Error('no usable image (the web images were not verified)');

    // 3. Generate, falling back to the next-best image.
    const tries = order.slice(0, config.sam3d.maxAttempts);
    for (const [k, r] of tries.entries()) {
      if (!canSpend(fal)) {
        ev('error', `Spend cap reached (${money(config.sam3d.maxUsd)}): no more SAM 3D attempts for "${prompt}"`, { refused: true, spentUsd, capUsd: config.sam3d.maxUsd });
        break;
      }
      spentUsd += fal;
      const c = r.candidate;
      ev('tool_call', `SAM 3D Objects (${SAM3D_MODEL}) on the ${describe(c)}${r.box ? ' with a box prompt' : ''}, about ${money(fal)}`, {
        model: SAM3D_MODEL, prompt, attempt: k + 1, ...sourceData(c), box: r.box ?? null, costUsd: fal, spentUsd, capUsd: config.sam3d.maxUsd,
      });
      try {
        const result = await deps.reconstruct({ imageUrl: `data:${c.image.mediaType};base64,${c.image.data}`, prompt, box: r.box });
        const url = await deps.saveGlb(result.glb);
        conn.reducers.setItemModel({ itemId: it.id, url, source: 'sam3d' });
        ev('result', `3D model of "${prompt}" ready from the ${describe(c)} (${(result.glb.length / 1024).toFixed(0)} KB)`, {
          url, requestId: result.requestId, bytes: result.glb.length, attempt: k + 1, ...sourceData(c),
        });
        return;
      } catch (err) {
        const next = tries[k + 1];
        ev('error', `SAM 3D failed on the ${describe(c)}: ${String(err)}${next ? `; trying the ${describe(next.candidate)}` : ''}`, { attempt: k + 1, ...sourceData(c) });
      }
    }
    conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'model' });
    ev('error', `3D model of "${prompt}" failed after ${tries.length} attempt(s)`);
  } catch (err) {
    conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'model' });
    ev('error', `3D model failed: ${String(err)}`);
  } finally {
    inFlight.delete(it.id);
    // A photo added mid-build re-queued the item, but our own set_item_model / stage write landed
    // after it and cleared that. Put it back so the new photo gets considered.
    if (stale.delete(it.id)) conn.reducers.setItemStage({ itemId: it.id, stage: 'pending', field: 'model' });
  }
}

// Builds a 3D model of each photographed item with Meta SAM 3D (#65), from the best image of it
// (#84): its scan crop, photos the user took, or web images of the identified product. Object
// Capture models from the phone take precedence (set_item_model never lets a sam3d result replace
// one). Without FAL_KEY it does nothing and items stay pending, so models appear once it's added.
export const sam3dAgent: Agent = {
  name: 'sam3d',
  start(conn) {
    if (!config.sam3d.enabled) {
      console.log('[sam3d] FAL_KEY not set: 3D models from photos are off (items stay pending)');
      return;
    }
    const queue: Item[] = [];
    let running = 0;
    const pump = () => {
      while (running < config.sam3d.concurrency && queue.length > 0) {
        const it = queue.shift()!;
        if (!needsModel(it)) continue;
        running++;
        void build(conn, it, currentDeps).finally(() => {
          running--;
          pump();
        });
      }
    };
    const maybe = (it: Item) => {
      const i = queue.findIndex(q => q.id === it.id);
      if (i >= 0) queue[i] = it; // keep the newest row (name, photos)
      else if (needsModel(it)) {
        queue.push(it);
        pump();
      }
    };
    for (const it of conn.db.item.iter()) maybe(it);
    conn.db.item.onInsert((_ctx, it) => maybe(it));
    conn.db.item.onUpdate((_ctx, old, it) => {
      if (inFlight.has(it.id) && it.photoUrls.length > old.photoUrls.length && it.modelSource !== 'capture') stale.add(it.id);
      maybe(it);
    });
  },
};
