import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import { config } from '../config.js';
import { logEvent } from '../events.js';
import { loadImage } from '../integrations/anthropic.js';
import { reconstruct, SAM3D_MODEL } from '../integrations/sam3d.js';
import { meshyClaimsModels } from './meshy.js';

const inFlight = new Set<bigint>();
let spentUsd = 0;

/** Items that should get a SAM 3D model: a photo, vision finished (so the prompt is the real
 *  name), no captured model, and not already queued. */
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
  // prompt only steers segmentation, and scraped/user text never reaches an LLM here.
  const text = (it.name || it.category).replace(/[^\p{L}\p{N} ,.'-]/gu, ' ').trim();
  return text.slice(0, 80) || it.category || 'object';
}

async function build(conn: Conn, it: Item): Promise<void> {
  inFlight.add(it.id);
  const cost = config.sam3d.usdPerRun;
  if (spentUsd + cost > config.sam3d.maxUsd) {
    logEvent(conn, { owner: it.owner, agent: 'sam3d', kind: 'error', message: `Spend cap reached ($${config.sam3d.maxUsd.toFixed(2)}): not building a 3D model of "${it.name}"`, refTable: 'item', refId: it.id, data: { refused: true, spentUsd, capUsd: config.sam3d.maxUsd } });
    inFlight.delete(it.id);
    return;
  }
  spentUsd += cost;
  conn.reducers.setItemStage({ itemId: it.id, stage: 'running', field: 'model' });
  const prompt = promptFor(it);
  logEvent(conn, { owner: it.owner, agent: 'sam3d', kind: 'plan', message: `Building a 3D model of "${prompt}" from its photo`, refTable: 'item', refId: it.id });
  try {
    const photo = await loadImage(it.photoUrls[it.photoUrls.length - 1]);
    logEvent(conn, { owner: it.owner, agent: 'sam3d', kind: 'tool_call', message: `SAM 3D Objects (${SAM3D_MODEL}), about $${cost.toFixed(2)}`, refTable: 'item', refId: it.id, data: { model: SAM3D_MODEL, prompt, costUsd: cost, spentUsd, capUsd: config.sam3d.maxUsd } });
    const result = await reconstruct({ imageUrl: `data:${photo.mediaType};base64,${photo.data}`, prompt });
    const name = `${randomUUID()}.glb`;
    await writeFile(path.join(config.uploadDir, name), result.glb);
    const url = `${config.publicUploadBaseUrl}/files/${name}`;
    conn.reducers.setItemModel({ itemId: it.id, url, source: 'sam3d' });
    logEvent(conn, { owner: it.owner, agent: 'sam3d', kind: 'result', message: `3D model of "${prompt}" ready (${(result.glb.length / 1024).toFixed(0)} KB)`, refTable: 'item', refId: it.id, data: { url, requestId: result.requestId, bytes: result.glb.length } });
  } catch (err) {
    conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'model' });
    logEvent(conn, { owner: it.owner, agent: 'sam3d', kind: 'error', message: `3D model failed: ${String(err)}`, refTable: 'item', refId: it.id });
  } finally {
    inFlight.delete(it.id);
  }
}

// Builds a 3D model of each photographed item with Meta SAM 3D (#65), so the app's room view
// can show the real object instead of a box. Object Capture models from the phone take
// precedence (set_item_model never lets a sam3d result replace one). Without FAL_KEY it does
// nothing and items stay pending, so models appear once the key is added.
export const sam3dAgent: Agent = {
  name: 'sam3d',
  start(conn) {
    if (!config.sam3d.enabled) {
      console.log('[sam3d] FAL_KEY not set: 3D models from photos are off (items stay pending)');
      return;
    }
    if (meshyClaimsModels()) {
      console.log('[sam3d] Meshy is enabled and builds the 3D models: SAM 3D stands down');
      return;
    }
    const queue: Item[] = [];
    let running = 0;
    const pump = () => {
      while (running < config.sam3d.concurrency && queue.length > 0) {
        const it = queue.shift()!;
        if (!needsModel(it)) continue;
        running++;
        void build(conn, it).finally(() => {
          running--;
          pump();
        });
      }
    };
    const maybe = (it: Item) => {
      if (needsModel(it) && !queue.some(q => q.id === it.id)) {
        queue.push(it);
        pump();
      }
    };
    for (const it of conn.db.item.iter()) maybe(it);
    conn.db.item.onInsert((_ctx, it) => maybe(it));
    conn.db.item.onUpdate((_ctx, _old, it) => maybe(it));
  },
};
