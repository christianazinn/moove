import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import { config } from '../config.js';
import { logEvent } from '../events.js';
import { loadImage } from '../integrations/anthropic.js';
import { fixtureUsdz, generateModel, MESHY_MODEL } from '../integrations/meshy.js';

const inFlight = new Set<bigint>();
let spentUsd = 0;

/** True when the Meshy agent owns 3D models for this worker run. The SAM 3D agent then stands
 *  down, so an item is never sent to both (one paid model per item). */
export function meshyClaimsModels(): boolean {
  return config.meshy.enabled;
}

/** Items that should get a Meshy model: a photo, vision finished, no captured model, not queued. */
export function needsMeshyModel(it: Item): boolean {
  return (
    it.modelStatus === 'pending' &&
    it.modelSource !== 'capture' &&
    it.photoUrls.length > 0 &&
    (it.detailsStatus === 'done' || it.detailsStatus === 'failed') &&
    !inFlight.has(it.id)
  );
}

/** Builds one item's model: spend check, photo -> Meshy -> USDZ in uploads/ -> set_item_model.
 *  Exported for tests; the agent calls it from its queue. */
export async function buildMeshyModel(conn: Conn, it: Item): Promise<void> {
  inFlight.add(it.id);
  const simulated = config.meshy.simulated;
  const cost = simulated ? 0 : config.meshy.usdPerRun;
  const capUsd = config.meshy.maxUsd;
  if (cost > 0 && spentUsd + cost > capUsd) {
    logEvent(conn, { owner: it.owner, agent: 'meshy', kind: 'error', message: `Spend cap reached ($${capUsd.toFixed(2)}): not building a 3D model of "${it.name}"`, refTable: 'item', refId: it.id, data: { refused: true, spentUsd, capUsd } });
    inFlight.delete(it.id);
    return;
  }
  spentUsd += cost;
  conn.reducers.setItemStage({ itemId: it.id, stage: 'running', field: 'model' });
  const label = it.name || it.category || 'item';
  logEvent(conn, { owner: it.owner, agent: 'meshy', kind: 'plan', message: `${simulated ? '[SIMULATED] ' : ''}Building a 3D model of "${label}" from its photo`, refTable: 'item', refId: it.id, data: { simulated } });
  try {
    let usdz: Buffer;
    let taskId = '';
    let credits = 0;
    logEvent(conn, { owner: it.owner, agent: 'meshy', kind: 'tool_call', message: simulated ? `[SIMULATED] Meshy image-to-3D (fixture USDZ, no API call)` : `Meshy image-to-3D (${MESHY_MODEL}, USDZ), about $${cost.toFixed(2)}`, refTable: 'item', refId: it.id, data: { model: MESHY_MODEL, simulated, costUsd: cost, spentUsd, capUsd } });
    if (simulated) {
      usdz = fixtureUsdz();
    } else {
      const photo = await loadImage(it.photoUrls[it.photoUrls.length - 1]);
      const r = await generateModel({ imageUrl: `data:${photo.mediaType};base64,${photo.data}` }, { maxBytes: config.meshy.maxBytes });
      ({ usdz, taskId, credits } = r);
    }
    const name = `${randomUUID()}.usdz`;
    await writeFile(path.join(config.uploadDir, name), usdz, { flag: 'wx' });
    const url = `${config.publicUploadBaseUrl}/files/${name}`;
    conn.reducers.setItemModel({ itemId: it.id, url, source: 'meshy' });
    logEvent(conn, { owner: it.owner, agent: 'meshy', kind: 'result', message: `${simulated ? '[SIMULATED] ' : ''}3D model of "${label}" ready (${(usdz.length / 1024).toFixed(0)} KB)`, refTable: 'item', refId: it.id, data: { url, taskId, credits, bytes: usdz.length, simulated } });
  } catch (err) {
    conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'model' });
    logEvent(conn, { owner: it.owner, agent: 'meshy', kind: 'error', message: `3D model failed: ${String(err)}`, refTable: 'item', refId: it.id, data: { simulated } });
  } finally {
    inFlight.delete(it.id);
  }
}

// Builds a USDZ model of each photographed item with Meshy image-to-3D (#65), as an alternative
// to SAM 3D. Off by default: it runs only with MOOVE_MESHY_ENABLED=1 and MESHY_API_KEY (or
// MESHY_SIMULATED=1). While it runs it claims every model and the SAM 3D agent stands down.
// Object Capture models from the phone still win (enforced in set_item_model).
export const meshyAgent: Agent = {
  name: 'meshy',
  start(conn) {
    if (!config.meshy.enabled) {
      console.log('[meshy] off (set MOOVE_MESHY_ENABLED=1 and MESHY_API_KEY, or MESHY_SIMULATED=1)');
      return;
    }
    if (config.meshy.simulated) console.log('[meshy] SIMULATED: fixture USDZ models, no Meshy API calls');
    const queue: Item[] = [];
    let running = 0;
    const pump = () => {
      while (running < config.meshy.concurrency && queue.length > 0) {
        const it = queue.shift()!;
        if (!needsMeshyModel(it)) continue;
        running++;
        void buildMeshyModel(conn, it).finally(() => {
          running--;
          pump();
        });
      }
    };
    const maybe = (it: Item) => {
      if (needsMeshyModel(it) && !queue.some(q => q.id === it.id)) {
        queue.push(it);
        pump();
      }
    };
    for (const it of conn.db.item.iter()) maybe(it);
    conn.db.item.onInsert((_ctx, it) => maybe(it));
    conn.db.item.onUpdate((_ctx, _old, it) => maybe(it));
  },
};
