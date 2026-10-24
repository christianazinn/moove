// Moove SpacetimeDB module: the shared contract between the iOS app and the agent worker.
// See docs/data-model.md. Conventions:
// - "enum" columns are plain strings validated here (not sum types) so the community
//   Swift SDK only has to decode primitives, strings, arrays and products.
// - "unknown" sentinels instead of options: '' for strings, -1 for numbers, 0n for ids.
// - Money is integer cents (i64); payments use USD micros so x402 USDC (6 decimals) and
//   card amounts share one column.
// - Reducers are deterministic: no network I/O. All outbound calls live in agents/.
import { schema, table, t, SenderError, type ReducerCtx } from 'spacetimedb/server';
import type { Identity } from 'spacetimedb';

// ---------- allowed values for string "enums" ----------
const HOME = ['old', 'new'] as const;
const DISPOSITION = ['undecided', 'keep', 'sell', 'donate', 'trash'] as const;
const DISPOSITION_SOURCE = ['auto', 'user'] as const;
const STAGE = ['pending', 'running', 'done', 'failed'] as const;
const LISTING_STATUS = ['draft', 'awaiting_approval', 'rejected', 'posted', 'sold', 'failed'] as const;
const APPROVAL_KIND = ['listing', 'purchase'] as const;
const APPROVAL_STATUS = ['pending', 'approved', 'denied', 'expired'] as const;
const SHOPPING_STATUS = ['open', 'searching', 'found', 'bought'] as const;
const RAIL = ['x402', 'visa'] as const;
const PAYMENT_STATUS = ['pending', 'settled', 'failed'] as const;
const NEW_HOME_SOURCE = ['demo', 'zillow', 'manual'] as const;
const EVENT_KIND = ['plan', 'tool_call', 'result', 'payment', 'approval', 'error'] as const;

function oneOf(field: string, value: string, allowed: readonly string[]): string {
  if (!allowed.includes(value)) {
    throw new SenderError(`${field} must be one of ${allowed.join('|')}, got '${value}'`);
  }
  return value;
}

// ---------- tables ----------
const user = table(
  { name: 'user', public: true },
  {
    identity: t.identity().primaryKey(),
    auth0Sub: t.string(),
    name: t.string(),
    email: t.string(),
    // Purchases/listings above this need phone approval (#12). -1 = always ask.
    approvalThresholdCents: t.i64(),
    createdAt: t.timestamp(),
  }
);

// Identities allowed to call worker-only reducers (the agent worker process).
const worker = table(
  { name: 'worker', public: true },
  {
    identity: t.identity().primaryKey(),
    label: t.string(),
    registeredAt: t.timestamp(),
  }
);

const room = table(
  { name: 'room', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    name: t.string(),
    home: t.string(), // HOME
    joinCode: t.string().unique(), // share with a second phone/person (#10)
    createdAt: t.timestamp(),
  }
);

// People other than the owner who can see and edit a room's items (#10).
const roomMember = table(
  { name: 'room_member', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    roomId: t.u64().index('btree'),
    member: t.identity().index('btree'),
    joinedAt: t.timestamp(),
  }
);

const scan = table(
  { name: 'scan', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    roomId: t.u64().index('btree'),
    usdzUrl: t.string(),
    capturedRoomJsonUrl: t.string(),
    createdAt: t.timestamp(),
  }
);

const item = table(
  { name: 'item', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    roomId: t.u64().index('btree'),
    scanId: t.u64(), // 0 = added manually
    scanObjectId: t.string(), // RoomPlan object UUID, '' if none
    name: t.string(),
    category: t.string(), // RoomPlan category or vision-assigned
    widthM: t.f64(),
    heightM: t.f64(),
    depthM: t.f64(),
    photoUrls: t.array(t.string()),
    // vision (#5)
    material: t.string(),
    brand: t.string(),
    condition: t.string(),
    detailsStatus: t.string(), // STAGE
    // pricing (#6)
    estValueCents: t.i64(), // -1 = unknown
    estLowCents: t.i64(), // -1 = unknown
    estHighCents: t.i64(), // -1 = unknown
    pricingStatus: t.string(), // STAGE
    // sorting (#8, #9)
    disposition: t.string(), // DISPOSITION
    dispositionSource: t.string(), // DISPOSITION_SOURCE
    dispositionReason: t.string(),
    fragile: t.bool(),
    maybeSentimental: t.bool(),
    createdAt: t.timestamp(),
    updatedAt: t.timestamp(),
  }
);

const comp = table(
  { name: 'comp', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    itemId: t.u64().index('btree'),
    source: t.string(), // 'fb' | 'craigslist' | 'ebay' | ...
    title: t.string(),
    priceCents: t.i64(),
    url: t.string(),
    fetchedAt: t.timestamp(),
  }
);

const listing = table(
  { name: 'listing', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    itemId: t.u64().index('btree'),
    platform: t.string(), // 'ebay'
    title: t.string(),
    description: t.string(),
    priceCents: t.i64(),
    status: t.string(), // LISTING_STATUS
    externalId: t.string(),
    url: t.string(),
    simulated: t.bool(),
    createdAt: t.timestamp(),
    updatedAt: t.timestamp(),
  }
);

const approval = table(
  { name: 'approval', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    kind: t.string(), // APPROVAL_KIND
    refId: t.u64(), // listing.id or deal.id
    amountCents: t.i64(),
    summary: t.string(),
    status: t.string(), // APPROVAL_STATUS
    requestedAt: t.timestamp(),
    updatedAt: t.timestamp(),
  }
);

const shoppingItem = table(
  { name: 'shopping_item', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    name: t.string(),
    category: t.string(),
    reason: t.string(),
    status: t.string(), // SHOPPING_STATUS
    chosenDealId: t.u64(), // 0 = none
    createdAt: t.timestamp(),
  }
);

const deal = table(
  { name: 'deal', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    shoppingItemId: t.u64().index('btree'),
    source: t.string(),
    title: t.string(),
    priceCents: t.i64(),
    url: t.string(),
    sellerInfo: t.string(),
    // fraud screening (#18); -1 = not scored yet
    fraudScore: t.f64(), // 0 (clean) .. 1 (likely fraud)
    aiTextScore: t.f64(), // AI-generated-text likelihood of the listing copy
    fraudReasons: t.array(t.string()),
    createdAt: t.timestamp(),
  }
);

const payment = table(
  { name: 'payment', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    agent: t.string(),
    rail: t.string(), // RAIL
    purpose: t.string(),
    payee: t.string(),
    amountUsdMicros: t.i64(), // USD * 1e6
    txHash: t.string(),
    status: t.string(), // PAYMENT_STATUS
    simulated: t.bool(),
    refTable: t.string(),
    refId: t.u64(),
    createdAt: t.timestamp(),
    updatedAt: t.timestamp(),
  }
);

const newHome = table(
  { name: 'new_home', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    name: t.string(),
    source: t.string(), // NEW_HOME_SOURCE
    floorPlanJson: t.string(), // { rooms: [{ name, polygon: [[x,y]...], widthM, depthM }] }
    createdAt: t.timestamp(),
  }
);

const layout = table(
  { name: 'layout', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    newHomeId: t.u64().index('btree'),
    name: t.string(),
    placementsJson: t.string(), // [{ itemId, room, x, y, rotationDeg }]
    createdAt: t.timestamp(),
  }
);

const agentEvent = table(
  { name: 'agent_event', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    agent: t.string(), // 'vision' | 'pricing' | 'sort' | 'listing' | 'buy' | 'fraud' | ...
    kind: t.string(), // EVENT_KIND
    message: t.string(),
    refTable: t.string(),
    refId: t.u64(),
    dataJson: t.string(),
    createdAt: t.timestamp(),
  }
);

const spacetimedb = schema({
  user,
  worker,
  room,
  roomMember,
  scan,
  item,
  comp,
  listing,
  approval,
  shoppingItem,
  deal,
  payment,
  newHome,
  layout,
  agentEvent,
});
export default spacetimedb;

type Ctx = ReducerCtx<typeof spacetimedb.schemaType>;

// ---------- auth helpers ----------
function isWorker(ctx: Ctx): boolean {
  return ctx.db.worker.identity.find(ctx.sender) != null;
}

function requireWorker(ctx: Ctx): void {
  if (!isWorker(ctx)) throw new SenderError('worker-only reducer');
}

function requireOwnerOrWorker(ctx: Ctx, owner: Identity): void {
  if (!ctx.sender.isEqual(owner) && !isWorker(ctx)) throw new SenderError('not your row');
}

function canAccessRoom(ctx: Ctx, roomId: bigint): boolean {
  const r = ctx.db.room.id.find(roomId);
  if (!r) throw new SenderError(`no room ${roomId}`);
  if (ctx.sender.isEqual(r.owner) || isWorker(ctx)) return true;
  for (const m of ctx.db.roomMember.roomId.filter(roomId)) {
    if (m.member.isEqual(ctx.sender)) return true;
  }
  return false;
}

function requireRoomAccess(ctx: Ctx, roomId: bigint) {
  if (!canAccessRoom(ctx, roomId)) throw new SenderError('not your room');
  return ctx.db.room.id.find(roomId)!;
}

function getItem(ctx: Ctx, id: bigint) {
  const row = ctx.db.item.id.find(id);
  if (!row) throw new SenderError(`no item ${id}`);
  return row;
}

// ---------- users & workers ----------
export const registerUser = spacetimedb.reducer(
  { auth0Sub: t.string(), name: t.string(), email: t.string() },
  (ctx, { auth0Sub, name, email }) => {
    const existing = ctx.db.user.identity.find(ctx.sender);
    if (existing) {
      ctx.db.user.identity.update({ ...existing, auth0Sub, name, email });
    } else {
      ctx.db.user.insert({
        identity: ctx.sender,
        auth0Sub,
        name,
        email,
        approvalThresholdCents: 10_000n, // $100 default
        createdAt: ctx.timestamp,
      });
    }
  }
);

export const setApprovalThreshold = spacetimedb.reducer(
  { cents: t.i64() },
  (ctx, { cents }) => {
    const u = ctx.db.user.identity.find(ctx.sender);
    if (!u) throw new SenderError('register first');
    ctx.db.user.identity.update({ ...u, approvalThresholdCents: cents });
  }
);

// First caller becomes the worker; after that only existing workers can add more.
// To reset, republish with --delete-data (dev) or clear the table.
export const registerWorker = spacetimedb.reducer({ label: t.string() }, (ctx, { label }) => {
  if (ctx.db.worker.count() > 0n && !isWorker(ctx)) {
    throw new SenderError('a worker is already registered');
  }
  if (!ctx.db.worker.identity.find(ctx.sender)) {
    ctx.db.worker.insert({ identity: ctx.sender, label, registeredAt: ctx.timestamp });
  }
});

// ---------- capture (#3, #4) ----------
export const createRoom = spacetimedb.reducer(
  { name: t.string(), home: t.string() },
  (ctx, { name, home }) => {
    ctx.db.room.insert({
      id: 0n,
      owner: ctx.sender,
      name,
      home: oneOf('home', home, HOME),
      joinCode: newJoinCode(ctx),
      createdAt: ctx.timestamp,
    });
  }
);

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function newJoinCode(ctx: Ctx): string {
  for (;;) {
    let code = '';
    for (let i = 0; i < 6; i++) code += CODE_ALPHABET[Math.floor(ctx.random() * CODE_ALPHABET.length)];
    if (!ctx.db.room.joinCode.find(code)) return code;
  }
}

export const joinRoom = spacetimedb.reducer({ code: t.string() }, (ctx, { code }) => {
  const r = ctx.db.room.joinCode.find(code.trim().toUpperCase());
  if (!r) throw new SenderError('no room with that code');
  if (canAccessRoom(ctx, r.id)) return;
  ctx.db.roomMember.insert({ id: 0n, roomId: r.id, member: ctx.sender, joinedAt: ctx.timestamp });
});

const ScanObjectInput = t.object('ScanObjectInput', {
  scanObjectId: t.string(),
  name: t.string(),
  category: t.string(),
  widthM: t.f64(),
  heightM: t.f64(),
  depthM: t.f64(),
  photoUrl: t.string(), // '' if none
});

// One-shot import for the app: creates room + scan + items atomically, since reducers
// can't return new ids to the caller.
export const importScan = spacetimedb.reducer(
  {
    roomName: t.string(),
    home: t.string(),
    usdzUrl: t.string(),
    capturedRoomJsonUrl: t.string(),
    objects: t.array(ScanObjectInput),
  },
  (ctx, { roomName, home, usdzUrl, capturedRoomJsonUrl, objects }) => {
    const r = ctx.db.room.insert({
      id: 0n,
      owner: ctx.sender,
      name: roomName,
      home: oneOf('home', home, HOME),
      joinCode: newJoinCode(ctx),
      createdAt: ctx.timestamp,
    });
    const s = ctx.db.scan.insert({
      id: 0n,
      owner: ctx.sender,
      roomId: r.id,
      usdzUrl,
      capturedRoomJsonUrl,
      createdAt: ctx.timestamp,
    });
    for (const o of objects) insertItem(ctx, ctx.sender, r.id, s.id, o);
  }
);

// Re-scan an existing room: creates the scan row and one item per RoomPlan object (re-running with the same
// scanObjectIds updates dimensions instead of duplicating).
export const createScan = spacetimedb.reducer(
  {
    roomId: t.u64(),
    usdzUrl: t.string(),
    capturedRoomJsonUrl: t.string(),
    objects: t.array(ScanObjectInput),
  },
  (ctx, { roomId, usdzUrl, capturedRoomJsonUrl, objects }) => {
    const r = requireRoomAccess(ctx, roomId);
    const s = ctx.db.scan.insert({
      id: 0n,
      owner: r.owner,
      roomId,
      usdzUrl,
      capturedRoomJsonUrl,
      createdAt: ctx.timestamp,
    });
    const existing = new Map<string, ReturnType<typeof getItem>>();
    for (const it of ctx.db.item.roomId.filter(roomId)) {
      if (it.scanObjectId) existing.set(it.scanObjectId, it);
    }
    for (const o of objects) {
      const prev = o.scanObjectId ? existing.get(o.scanObjectId) : undefined;
      if (prev) {
        ctx.db.item.id.update({
          ...prev,
          scanId: s.id,
          widthM: o.widthM,
          heightM: o.heightM,
          depthM: o.depthM,
          updatedAt: ctx.timestamp,
        });
      } else {
        insertItem(ctx, r.owner, roomId, s.id, o);
      }
    }
  }
);

function insertItem(
  ctx: Ctx,
  owner: Identity,
  roomId: bigint,
  scanId: bigint,
  o: {
    scanObjectId: string;
    name: string;
    category: string;
    widthM: number;
    heightM: number;
    depthM: number;
    photoUrl: string;
  }
) {
  return ctx.db.item.insert({
    id: 0n,
    owner,
    roomId,
    scanId,
    scanObjectId: o.scanObjectId,
    name: o.name || o.category,
    category: o.category,
    widthM: o.widthM,
    heightM: o.heightM,
    depthM: o.depthM,
    photoUrls: o.photoUrl ? [o.photoUrl] : [],
    material: '',
    brand: '',
    condition: '',
    detailsStatus: 'pending',
    estValueCents: -1n,
    estLowCents: -1n,
    estHighCents: -1n,
    pricingStatus: 'pending',
    disposition: 'undecided',
    dispositionSource: 'auto',
    dispositionReason: '',
    fragile: false,
    maybeSentimental: false,
    createdAt: ctx.timestamp,
    updatedAt: ctx.timestamp,
  });
}

export const addItem = spacetimedb.reducer(
  { roomId: t.u64(), object: ScanObjectInput },
  (ctx, { roomId, object }) => {
    const r = requireRoomAccess(ctx, roomId);
    insertItem(ctx, r.owner, roomId, 0n, object);
  }
);

// Adding a photo re-queues vision (#5) for the item.
export const addItemPhoto = spacetimedb.reducer(
  { itemId: t.u64(), url: t.string() },
  (ctx, { itemId, url }) => {
    const it = getItem(ctx, itemId);
    requireRoomAccess(ctx, it.roomId);
    ctx.db.item.id.update({
      ...it,
      photoUrls: [...it.photoUrls, url],
      detailsStatus: 'pending',
      updatedAt: ctx.timestamp,
    });
  }
);

export const deleteItem = spacetimedb.reducer({ itemId: t.u64() }, (ctx, { itemId }) => {
  const it = getItem(ctx, itemId);
  requireRoomAccess(ctx, it.roomId);
  ctx.db.item.id.delete(itemId);
});

// ---------- user-side item edits (#9) ----------
export const setDisposition = spacetimedb.reducer(
  { itemId: t.u64(), disposition: t.string() },
  (ctx, { itemId, disposition }) => {
    const it = getItem(ctx, itemId);
    requireRoomAccess(ctx, it.roomId);
    ctx.db.item.id.update({
      ...it,
      disposition: oneOf('disposition', disposition, DISPOSITION),
      dispositionSource: 'user',
      dispositionReason: 'set by user',
      updatedAt: ctx.timestamp,
    });
  }
);

// Absolute setters (not toggles) so two phones editing at once converge.
export const setSentimental = spacetimedb.reducer(
  { itemId: t.u64(), value: t.bool() },
  (ctx, { itemId, value }) => {
    const it = getItem(ctx, itemId);
    requireRoomAccess(ctx, it.roomId);
    ctx.db.item.id.update({ ...it, maybeSentimental: value, updatedAt: ctx.timestamp });
  }
);

export const setFragile = spacetimedb.reducer(
  { itemId: t.u64(), value: t.bool() },
  (ctx, { itemId, value }) => {
    const it = getItem(ctx, itemId);
    requireRoomAccess(ctx, it.roomId);
    ctx.db.item.id.update({ ...it, fragile: value, updatedAt: ctx.timestamp });
  }
);

export const renameItem = spacetimedb.reducer(
  { itemId: t.u64(), name: t.string() },
  (ctx, { itemId, name }) => {
    const it = getItem(ctx, itemId);
    requireRoomAccess(ctx, it.roomId);
    ctx.db.item.id.update({ ...it, name, updatedAt: ctx.timestamp });
  }
);

// ---------- worker-side item enrichment (#5, #6, #8) ----------
export const setItemStage = spacetimedb.reducer(
  { itemId: t.u64(), stage: t.string(), field: t.string() },
  (ctx, { itemId, stage, field }) => {
    requireWorker(ctx);
    const it = getItem(ctx, itemId);
    oneOf('stage', stage, STAGE);
    if (field === 'details') ctx.db.item.id.update({ ...it, detailsStatus: stage, updatedAt: ctx.timestamp });
    else if (field === 'pricing') ctx.db.item.id.update({ ...it, pricingStatus: stage, updatedAt: ctx.timestamp });
    else throw new SenderError("field must be 'details' or 'pricing'");
  }
);

export const setItemDetails = spacetimedb.reducer(
  {
    itemId: t.u64(),
    name: t.string(),
    category: t.string(),
    material: t.string(),
    brand: t.string(),
    condition: t.string(),
    fragile: t.bool(),
    maybeSentimental: t.bool(),
  },
  (ctx, args) => {
    requireWorker(ctx);
    const it = getItem(ctx, args.itemId);
    ctx.db.item.id.update({
      ...it,
      // keep a user-chosen name if they renamed it
      name: args.name || it.name,
      category: args.category || it.category,
      material: args.material,
      brand: args.brand,
      condition: args.condition,
      fragile: it.fragile || args.fragile,
      maybeSentimental: it.maybeSentimental || args.maybeSentimental,
      detailsStatus: 'done',
      updatedAt: ctx.timestamp,
    });
  }
);

const CompInput = t.object('CompInput', {
  source: t.string(),
  title: t.string(),
  priceCents: t.i64(),
  url: t.string(),
});

export const addComps = spacetimedb.reducer(
  { itemId: t.u64(), comps: t.array(CompInput) },
  (ctx, { itemId, comps }) => {
    requireWorker(ctx);
    getItem(ctx, itemId);
    for (const c of comps) ctx.db.comp.insert({ id: 0n, itemId, ...c, fetchedAt: ctx.timestamp });
  }
);

export const setEstValue = spacetimedb.reducer(
  { itemId: t.u64(), estValueCents: t.i64(), estLowCents: t.i64(), estHighCents: t.i64() },
  (ctx, { itemId, estValueCents, estLowCents, estHighCents }) => {
    requireWorker(ctx);
    const it = getItem(ctx, itemId);
    ctx.db.item.id.update({
      ...it,
      estValueCents,
      estLowCents,
      estHighCents,
      pricingStatus: 'done',
      updatedAt: ctx.timestamp,
    });
  }
);

// Never overrides a user's choice, and never auto-decides possibly sentimental items.
export const setAutoDisposition = spacetimedb.reducer(
  { itemId: t.u64(), disposition: t.string(), reason: t.string() },
  (ctx, { itemId, disposition, reason }) => {
    requireWorker(ctx);
    const it = getItem(ctx, itemId);
    if (it.dispositionSource === 'user') return;
    if (it.maybeSentimental) {
      ctx.db.item.id.update({
        ...it,
        disposition: 'undecided',
        dispositionReason: 'possibly sentimental - your call',
        updatedAt: ctx.timestamp,
      });
      return;
    }
    ctx.db.item.id.update({
      ...it,
      disposition: oneOf('disposition', disposition, DISPOSITION),
      dispositionSource: 'auto',
      dispositionReason: reason,
      updatedAt: ctx.timestamp,
    });
  }
);

// ---------- listings (#11) ----------
export const createListingDraft = spacetimedb.reducer(
  { itemId: t.u64(), title: t.string(), description: t.string(), priceCents: t.i64(), simulated: t.bool() },
  (ctx, { itemId, title, description, priceCents, simulated }) => {
    requireWorker(ctx);
    const it = getItem(ctx, itemId);
    ctx.db.listing.insert({
      id: 0n,
      owner: it.owner,
      itemId,
      platform: 'ebay',
      title,
      description,
      priceCents,
      status: 'draft',
      externalId: '',
      url: '',
      simulated,
      createdAt: ctx.timestamp,
      updatedAt: ctx.timestamp,
    });
  }
);

export const updateListing = spacetimedb.reducer(
  {
    listingId: t.u64(),
    status: t.string(),
    externalId: t.string(),
    url: t.string(),
    priceCents: t.i64(),
  },
  (ctx, { listingId, status, externalId, url, priceCents }) => {
    const l = ctx.db.listing.id.find(listingId);
    if (!l) throw new SenderError(`no listing ${listingId}`);
    requireOwnerOrWorker(ctx, l.owner);
    ctx.db.listing.id.update({
      ...l,
      status: oneOf('status', status, LISTING_STATUS),
      externalId: externalId || l.externalId,
      url: url || l.url,
      priceCents: priceCents >= 0n ? priceCents : l.priceCents,
      updatedAt: ctx.timestamp,
    });
  }
);

// ---------- approvals (#12) ----------
export const requestApproval = spacetimedb.reducer(
  { owner: t.identity(), kind: t.string(), refId: t.u64(), amountCents: t.i64(), summary: t.string() },
  (ctx, { owner, kind, refId, amountCents, summary }) => {
    requireWorker(ctx);
    ctx.db.approval.insert({
      id: 0n,
      owner,
      kind: oneOf('kind', kind, APPROVAL_KIND),
      refId,
      amountCents,
      summary,
      status: 'pending',
      requestedAt: ctx.timestamp,
      updatedAt: ctx.timestamp,
    });
  }
);

// Called by the app (in-app approve/deny) or by the worker after an Auth0 CIBA response.
export const decideApproval = spacetimedb.reducer(
  { approvalId: t.u64(), status: t.string() },
  (ctx, { approvalId, status }) => {
    const a = ctx.db.approval.id.find(approvalId);
    if (!a) throw new SenderError(`no approval ${approvalId}`);
    requireOwnerOrWorker(ctx, a.owner);
    if (a.status !== 'pending') throw new SenderError(`approval already ${a.status}`);
    ctx.db.approval.id.update({
      ...a,
      status: oneOf('status', status, APPROVAL_STATUS),
      updatedAt: ctx.timestamp,
    });
  }
);

// ---------- shopping & deals (#15, #18) ----------
export const addShoppingItem = spacetimedb.reducer(
  { owner: t.identity(), name: t.string(), category: t.string(), reason: t.string() },
  (ctx, { owner, name, category, reason }) => {
    // Users add for themselves; the worker may add generated starter-list items for a user.
    requireOwnerOrWorker(ctx, owner);
    ctx.db.shoppingItem.insert({
      id: 0n,
      owner,
      name,
      category,
      reason,
      status: 'open',
      chosenDealId: 0n,
      createdAt: ctx.timestamp,
    });
  }
);

export const setShoppingStatus = spacetimedb.reducer(
  { shoppingItemId: t.u64(), status: t.string() },
  (ctx, { shoppingItemId, status }) => {
    const s = ctx.db.shoppingItem.id.find(shoppingItemId);
    if (!s) throw new SenderError(`no shopping item ${shoppingItemId}`);
    requireOwnerOrWorker(ctx, s.owner);
    ctx.db.shoppingItem.id.update({ ...s, status: oneOf('status', status, SHOPPING_STATUS) });
  }
);

export const removeShoppingItem = spacetimedb.reducer(
  { shoppingItemId: t.u64() },
  (ctx, { shoppingItemId }) => {
    const s = ctx.db.shoppingItem.id.find(shoppingItemId);
    if (!s) return;
    requireOwnerOrWorker(ctx, s.owner);
    ctx.db.shoppingItem.id.delete(shoppingItemId);
  }
);

export const addDeal = spacetimedb.reducer(
  {
    shoppingItemId: t.u64(),
    source: t.string(),
    title: t.string(),
    priceCents: t.i64(),
    url: t.string(),
    sellerInfo: t.string(),
  },
  (ctx, args) => {
    requireWorker(ctx);
    const s = ctx.db.shoppingItem.id.find(args.shoppingItemId);
    if (!s) throw new SenderError(`no shopping item ${args.shoppingItemId}`);
    ctx.db.deal.insert({
      id: 0n,
      owner: s.owner,
      ...args,
      fraudScore: -1,
      aiTextScore: -1,
      fraudReasons: [],
      createdAt: ctx.timestamp,
    });
    if (s.status === 'open' || s.status === 'searching') {
      ctx.db.shoppingItem.id.update({ ...s, status: 'found' });
    }
  }
);

export const setDealFraud = spacetimedb.reducer(
  { dealId: t.u64(), fraudScore: t.f64(), aiTextScore: t.f64(), reasons: t.array(t.string()) },
  (ctx, { dealId, fraudScore, aiTextScore, reasons }) => {
    requireWorker(ctx);
    const d = ctx.db.deal.id.find(dealId);
    if (!d) throw new SenderError(`no deal ${dealId}`);
    ctx.db.deal.id.update({ ...d, fraudScore, aiTextScore, fraudReasons: reasons });
  }
);

export const chooseDeal = spacetimedb.reducer(
  { shoppingItemId: t.u64(), dealId: t.u64() },
  (ctx, { shoppingItemId, dealId }) => {
    const s = ctx.db.shoppingItem.id.find(shoppingItemId);
    if (!s) throw new SenderError(`no shopping item ${shoppingItemId}`);
    requireOwnerOrWorker(ctx, s.owner);
    const d = ctx.db.deal.id.find(dealId);
    if (!d || d.shoppingItemId !== shoppingItemId) throw new SenderError('deal does not match item');
    ctx.db.shoppingItem.id.update({ ...s, chosenDealId: dealId });
  }
);

// ---------- payments (#7, #15) ----------
export const recordPayment = spacetimedb.reducer(
  {
    owner: t.identity(),
    agent: t.string(),
    rail: t.string(),
    purpose: t.string(),
    payee: t.string(),
    amountUsdMicros: t.i64(),
    txHash: t.string(),
    status: t.string(),
    simulated: t.bool(),
    refTable: t.string(),
    refId: t.u64(),
  },
  (ctx, args) => {
    requireWorker(ctx);
    ctx.db.payment.insert({
      id: 0n,
      ...args,
      rail: oneOf('rail', args.rail, RAIL),
      status: oneOf('status', args.status, PAYMENT_STATUS),
      createdAt: ctx.timestamp,
      updatedAt: ctx.timestamp,
    });
  }
);

export const updatePayment = spacetimedb.reducer(
  { paymentId: t.u64(), status: t.string(), txHash: t.string() },
  (ctx, { paymentId, status, txHash }) => {
    requireWorker(ctx);
    const p = ctx.db.payment.id.find(paymentId);
    if (!p) throw new SenderError(`no payment ${paymentId}`);
    ctx.db.payment.id.update({
      ...p,
      status: oneOf('status', status, PAYMENT_STATUS),
      txHash: txHash || p.txHash,
      updatedAt: ctx.timestamp,
    });
  }
);

// ---------- new home (#13, #14) ----------
export const createNewHome = spacetimedb.reducer(
  { name: t.string(), source: t.string(), floorPlanJson: t.string() },
  (ctx, { name, source, floorPlanJson }) => {
    ctx.db.newHome.insert({
      id: 0n,
      owner: ctx.sender,
      name,
      source: oneOf('source', source, NEW_HOME_SOURCE),
      floorPlanJson,
      createdAt: ctx.timestamp,
    });
  }
);

export const saveLayout = spacetimedb.reducer(
  { newHomeId: t.u64(), name: t.string(), placementsJson: t.string() },
  (ctx, { newHomeId, name, placementsJson }) => {
    const h = ctx.db.newHome.id.find(newHomeId);
    if (!h) throw new SenderError(`no new home ${newHomeId}`);
    requireOwnerOrWorker(ctx, h.owner);
    ctx.db.layout.insert({
      id: 0n,
      owner: h.owner,
      newHomeId,
      name,
      placementsJson,
      createdAt: ctx.timestamp,
    });
  }
);

// ---------- agent activity log ----------
export const logAgentEvent = spacetimedb.reducer(
  {
    owner: t.identity(),
    agent: t.string(),
    kind: t.string(),
    message: t.string(),
    refTable: t.string(),
    refId: t.u64(),
    dataJson: t.string(),
  },
  (ctx, args) => {
    requireWorker(ctx);
    ctx.db.agentEvent.insert({
      id: 0n,
      ...args,
      kind: oneOf('kind', args.kind, EVENT_KIND),
      createdAt: ctx.timestamp,
    });
  }
);
