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
const SWEEP_STATUS = ['none', 'pending', 'running', 'done', 'failed'] as const;
const MODEL_SOURCE = ['capture', 'sam3d'] as const; // Object Capture on the phone, or SAM 3D from a photo (#65)
const LISTING_STATUS = ['draft', 'awaiting_approval', 'rejected', 'posted', 'sold', 'failed'] as const;
const APPROVAL_KIND = ['listing', 'purchase'] as const;
const APPROVAL_STATUS = ['pending', 'approved', 'denied', 'expired'] as const;
const APPROVAL_DECISION = ['approved', 'denied'] as const; // what decide_approval / record_ciba_decision accept
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
    // Room photo sweep (#73 follow-up). Appended with a default so existing rows migrate.
    sweepStatus: t.string().default('none'), // SWEEP_STATUS
  }
);

// Wide room photos taken after a scan; the sweep agent names RoomPlan's boxes and finds what it missed.
const scanPhoto = table(
  { name: 'scan_photo', public: true },
  {
    id: t.u64().primaryKey().autoInc(),
    owner: t.identity().index('btree'),
    scanId: t.u64().index('btree'),
    url: t.string(),
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
    // 3D model (#65). Appended with defaults so existing rows migrate.
    modelUrl: t.string().default(''), // USDZ (capture) or GLB (sam3d), '' if none
    modelSource: t.string().default(''), // MODEL_SOURCE or ''
    modelStatus: t.string().default('pending'), // STAGE: the SAM 3D agent picks up pending items with a photo
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
    // #42, appended last with defaults so existing rows migrate
    decidedVia: t.string().default(''), // '' while pending | 'app' (owner in the app) | 'ciba' (worker relayed Auth0)
    cibaSubject: t.string().default(''), // Auth0 `sub` the worker reported from the CIBA id_token
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
  scanPhoto,
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

// ---------- identity constants (security pass #41, #44) ----------
// Not secrets: the issuer and client id are in every Auth0 ID token the app holds.
const AUTH0_ISSUER = 'https://dev-78lq8spq27b2bipk.us.auth0.com/'; // exactly as in the token's `iss`
const AUTH0_IOS_CLIENT_ID = 'B674uRd1BKSPe11boeGRMXd2UlJIuDur'; // ID token `aud` (iOS native app)
// Connection gate (#41 part A). Off for now: Auth0 login (#1) has merged, but the app still falls back
// to an anonymous SpacetimeDB token ("Guest"). Setting it back to false is the demo escape hatch if
// login breaks on stage.
const REQUIRE_AUTH0 = false;
// On maincloud only the pinned worker identity may hold the worker role (#44). Every other database
// (local dev) keeps first-caller-wins so teammates can run their own worker.
const MAINCLOUD_DATABASE_IDENTITY = 'c200b33aa2dc4fda37db755875072992ffdf560c733f43b9faec5c1b116793aa';
const MAINCLOUD_WORKER_IDENTITIES: readonly string[] = [
  'c2002442bb9baf2130801c9162964a627e601a60fde9d30f0da5d4a9b8fa09f7', // printed by agents on connect
];

function hex(id: Identity): string {
  return id.toHexString().replace(/^0x/i, '').toLowerCase();
}

// The pinned worker list for this database, or null when any first caller may become the worker.
function pinnedWorkers(ctx: Ctx): readonly string[] | null {
  return hex(ctx.databaseIdentity) === MAINCLOUD_DATABASE_IDENTITY ? MAINCLOUD_WORKER_IDENTITIES : null;
}

// The caller's Auth0 token claims (SpacetimeDB has verified the signature), or null for
// anonymous SpacetimeDB tokens and other issuers.
function auth0Claims(ctx: Ctx) {
  const jwt = ctx.senderAuth.jwt;
  return jwt && jwt.issuer === AUTH0_ISSUER ? jwt : null;
}

// ---------- auth helpers ----------
// On maincloud a worker row only counts for a pinned identity, so a stale row can't keep the role.
function isWorker(ctx: Ctx): boolean {
  if (ctx.db.worker.identity.find(ctx.sender) == null) return false;
  const pinned = pinnedWorkers(ctx);
  return pinned == null || pinned.includes(hex(ctx.sender));
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

// ---------- connection gate (#41 part A) ----------
export const onConnect = spacetimedb.clientConnected(ctx => {
  if (!REQUIRE_AUTH0 || ctx.senderAuth.isInternal) return;
  // The worker connects with a SpacetimeDB-minted token, not Auth0.
  const pinned = pinnedWorkers(ctx);
  if (pinned?.includes(hex(ctx.sender)) || isWorker(ctx)) return;
  // A fresh local DB has no worker yet: let the first one in so it can call register_worker.
  if (pinned == null && ctx.db.worker.count() === 0n) return;
  const jwt = auth0Claims(ctx);
  if (!jwt || !jwt.audience.includes(AUTH0_IOS_CLIENT_ID)) {
    throw new SenderError('sign in with Auth0 to use Moove');
  }
});

// ---------- users & workers ----------
// auth0Sub and email come from the caller's verified Auth0 token (#44), never from the args: CIBA
// pushes go to user.auth0Sub, so a client must not be able to point its row at someone else's account.
// Anonymous/demo tokens get auth0Sub ''. The auth0Sub arg is ignored (kept for binding compatibility);
// email falls back to the arg only when the token has no email claim.
export const registerUser = spacetimedb.reducer(
  { auth0Sub: t.string(), name: t.string(), email: t.string() },
  (ctx, args) => {
    const jwt = auth0Claims(ctx);
    const auth0Sub = jwt ? jwt.subject : '';
    const claimedEmail = jwt ? jwt.fullPayload['email'] : undefined;
    const email = typeof claimedEmail === 'string' ? claimedEmail : args.email;
    const name = args.name;
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

const MAX_APPROVAL_THRESHOLD_CENTS = 10_000_000n; // $100,000

// -1 = always ask (#44 bounds it).
export const setApprovalThreshold = spacetimedb.reducer(
  { cents: t.i64() },
  (ctx, { cents }) => {
    const u = ctx.db.user.identity.find(ctx.sender);
    if (!u) throw new SenderError('register first');
    if (cents < -1n || cents > MAX_APPROVAL_THRESHOLD_CENTS) {
      throw new SenderError(`cents must be -1 (always ask) or 0..${MAX_APPROVAL_THRESHOLD_CENTS}`);
    }
    ctx.db.user.identity.update({ ...u, approvalThresholdCents: cents });
  }
);

// On maincloud only the pinned identity can register (#44). Elsewhere the first caller becomes the
// worker and after that only existing workers can add more; to reset, republish with --delete-data.
export const registerWorker = spacetimedb.reducer({ label: t.string() }, (ctx, { label }) => {
  const pinned = pinnedWorkers(ctx);
  if (pinned) {
    if (!pinned.includes(hex(ctx.sender))) throw new SenderError('not an allowed worker identity');
  } else if (ctx.db.worker.count() > 0n && !isWorker(ctx)) {
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

function requireRoomOwner(ctx: Ctx, roomId: bigint) {
  const r = ctx.db.room.id.find(roomId);
  if (!r) throw new SenderError(`no room ${roomId}`);
  if (!ctx.sender.isEqual(r.owner)) throw new SenderError('only the room owner can do that');
  return r;
}

// Contain a leaked join code (#41): the old code stops working; existing members stay.
export const rotateJoinCode = spacetimedb.reducer({ roomId: t.u64() }, (ctx, { roomId }) => {
  const r = requireRoomOwner(ctx, roomId);
  ctx.db.room.id.update({ ...r, joinCode: newJoinCode(ctx) });
});

export const removeMember = spacetimedb.reducer(
  { roomId: t.u64(), member: t.identity() },
  (ctx, { roomId, member }) => {
    requireRoomOwner(ctx, roomId);
    const rows = Array.from(ctx.db.roomMember.roomId.filter(roomId)).filter(m => m.member.isEqual(member));
    if (rows.length === 0) throw new SenderError('not a member of that room');
    for (const m of rows) ctx.db.roomMember.id.delete(m.id);
  }
);

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
      sweepStatus: 'none',
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
      sweepStatus: 'none',
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

// The worker fetches photo URLs, so keep junk like file: and data: out of the table (#44). The
// worker has its own allowlist (agents/src/integrations/anthropic.ts); this is only a first filter.
function isHttpUrl(url: string): boolean {
  return /^https?:\/\/\S+$/i.test(url);
}

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
    photoUrls: isHttpUrl(o.photoUrl) ? [o.photoUrl] : [], // a bad URL drops the photo, not the import
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
    modelUrl: '',
    modelSource: '',
    modelStatus: 'pending',
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
    if (!isHttpUrl(url)) throw new SenderError('photo URL must be http(s)');
    ctx.db.item.id.update({
      ...it,
      photoUrls: [...it.photoUrls, url],
      detailsStatus: 'pending',
      modelStatus: it.modelSource === 'capture' ? it.modelStatus : 'pending',
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
    else if (field === 'model') ctx.db.item.id.update({ ...it, modelStatus: stage, updatedAt: ctx.timestamp });
    else throw new SenderError("field must be 'details', 'pricing' or 'model'");
  }
);

// ---------- 3D models (#65) ----------
function isHttpOrEmpty(url: string): boolean {
  return url === '' || /^https?:\/\//i.test(url);
}

// Sets (or clears, with url '') an item's 3D model. The app calls it after Object Capture
// ('capture'); the SAM 3D agent calls it with a model built from a photo ('sam3d'). A captured
// model is a real walk-around scan, so a later 'sam3d' result never replaces it.
export const setItemModel = spacetimedb.reducer(
  { itemId: t.u64(), url: t.string(), source: t.string() },
  (ctx, { itemId, url, source }) => {
    const it = getItem(ctx, itemId);
    if (!isWorker(ctx)) requireRoomAccess(ctx, it.roomId);
    oneOf('source', source, MODEL_SOURCE);
    if (!isHttpOrEmpty(url)) throw new SenderError('model URL must be http(s)');
    if (source === 'sam3d' && it.modelSource === 'capture' && it.modelUrl !== '') {
      ctx.db.item.id.update({ ...it, modelStatus: 'done', updatedAt: ctx.timestamp });
      return;
    }
    ctx.db.item.id.update({
      ...it,
      modelUrl: url,
      modelSource: url === '' ? '' : source,
      modelStatus: url === '' ? 'pending' : 'done',
      updatedAt: ctx.timestamp,
    });
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

// ---------- room photo sweep ----------
const MAX_SCAN_PHOTOS = 12;

// The app attaches a wide room photo to a scan (after uploading it to the worker). Each photo
// re-queues the sweep; the agent waits for photos to stop arriving before it runs.
export const addScanPhoto = spacetimedb.reducer(
  { scanId: t.u64(), url: t.string() },
  (ctx, { scanId, url }) => {
    const sc = ctx.db.scan.id.find(scanId);
    if (!sc) throw new SenderError(`no scan ${scanId}`);
    requireRoomAccess(ctx, sc.roomId);
    if (!isHttpUrl(url)) throw new SenderError('photo URL must be http(s)');
    if ([...ctx.db.scanPhoto.scanId.filter(scanId)].length >= MAX_SCAN_PHOTOS) {
      throw new SenderError(`at most ${MAX_SCAN_PHOTOS} photos per scan`);
    }
    ctx.db.scanPhoto.insert({ id: 0n, owner: sc.owner, scanId, url, createdAt: ctx.timestamp });
    ctx.db.scan.id.update({ ...sc, sweepStatus: 'pending' });
  }
);

export const setSweepStatus = spacetimedb.reducer(
  { scanId: t.u64(), status: t.string() },
  (ctx, { scanId, status }) => {
    requireWorker(ctx);
    const sc = ctx.db.scan.id.find(scanId);
    if (!sc) throw new SenderError(`no scan ${scanId}`);
    ctx.db.scan.id.update({ ...sc, sweepStatus: oneOf('status', status, SWEEP_STATUS) });
  }
);

// The sweep recognized a scanned item in a room photo. Unlike set_item_details, a better name
// replaces RoomPlan's category name, and a changed name or brand re-queues pricing so the
// estimate follows the real item. A user's own disposition is untouched (sort respects it).
export const applySweepMatch = spacetimedb.reducer(
  {
    itemId: t.u64(),
    name: t.string(),
    category: t.string(),
    material: t.string(),
    brand: t.string(),
    condition: t.string(),
    fragile: t.bool(),
    maybeSentimental: t.bool(),
    photoUrl: t.string(),
  },
  (ctx, a) => {
    requireWorker(ctx);
    const it = getItem(ctx, a.itemId);
    const name = a.name || it.name;
    const brand = a.brand || it.brand;
    const renamed = name.toLowerCase() !== it.name.toLowerCase() || brand.toLowerCase() !== it.brand.toLowerCase();
    const addPhoto = isHttpUrl(a.photoUrl) && !it.photoUrls.includes(a.photoUrl);
    ctx.db.item.id.update({
      ...it,
      name,
      category: a.category || it.category,
      material: a.material || it.material,
      brand,
      condition: a.condition || it.condition,
      fragile: it.fragile || a.fragile,
      maybeSentimental: it.maybeSentimental || a.maybeSentimental,
      photoUrls: addPhoto ? [...it.photoUrls, a.photoUrl] : it.photoUrls,
      detailsStatus: 'done',
      ...(renamed && it.pricingStatus !== 'running'
        ? { pricingStatus: 'pending', estValueCents: -1n, estLowCents: -1n, estHighCents: -1n }
        : {}),
      updatedAt: ctx.timestamp,
    });
  }
);

// Something the scan missed but a room photo shows. scan_object_id is "photo:<scan>" so the app
// knows it has no RoomPlan box (size is the model's estimate, there is no position).
export const addSweepItem = spacetimedb.reducer(
  {
    scanId: t.u64(),
    name: t.string(),
    category: t.string(),
    widthM: t.f64(),
    heightM: t.f64(),
    depthM: t.f64(),
    material: t.string(),
    brand: t.string(),
    condition: t.string(),
    fragile: t.bool(),
    maybeSentimental: t.bool(),
    photoUrl: t.string(),
  },
  (ctx, a) => {
    requireWorker(ctx);
    const sc = ctx.db.scan.id.find(a.scanId);
    if (!sc) throw new SenderError(`no scan ${a.scanId}`);
    if (!a.name) throw new SenderError('name required');
    const it = insertItem(ctx, sc.owner, sc.roomId, sc.id, {
      scanObjectId: `photo:${sc.id}`,
      name: a.name,
      category: a.category,
      widthM: a.widthM,
      heightM: a.heightM,
      depthM: a.depthM,
      photoUrl: a.photoUrl,
    });
    ctx.db.item.id.update({
      ...it,
      material: a.material,
      brand: a.brand,
      condition: a.condition,
      fragile: a.fragile,
      maybeSentimental: a.maybeSentimental,
      detailsStatus: 'done', // the sweep already looked at it; don't pay for vision again
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

// Worker-only (#44): listing state (posted/sold, eBay id and url, price) only comes from the worker.
export const updateListing = spacetimedb.reducer(
  {
    listingId: t.u64(),
    status: t.string(),
    externalId: t.string(),
    url: t.string(),
    priceCents: t.i64(),
  },
  (ctx, { listingId, status, externalId, url, priceCents }) => {
    requireWorker(ctx);
    const l = ctx.db.listing.id.find(listingId);
    if (!l) throw new SenderError(`no listing ${listingId}`);
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

// ---------- approvals (#12, #42) ----------
// Only the worker asks, and only about the owner's own listing/deal at its real price.
export const requestApproval = spacetimedb.reducer(
  { owner: t.identity(), kind: t.string(), refId: t.u64(), amountCents: t.i64(), summary: t.string() },
  (ctx, { owner, kind, refId, amountCents, summary }) => {
    requireWorker(ctx);
    oneOf('kind', kind, APPROVAL_KIND);
    const ref = kind === 'listing' ? ctx.db.listing.id.find(refId) : ctx.db.deal.id.find(refId);
    if (!ref || !ref.owner.isEqual(owner)) throw new SenderError(`${kind} ${refId} does not belong to that owner`);
    // If purchases (#15) add tax/shipping on top of the deal price, relax this for kind === 'purchase'.
    if (ref.priceCents !== amountCents) throw new SenderError(`amount must equal the ${kind} price`);
    ctx.db.approval.insert({
      id: 0n,
      owner,
      kind,
      refId,
      amountCents,
      summary,
      status: 'pending',
      requestedAt: ctx.timestamp,
      updatedAt: ctx.timestamp,
      decidedVia: '',
      cibaSubject: '',
    });
  }
);

// In-app approve/deny. Owner only: the worker asks for approvals, so it must not grant them (#42).
export const decideApproval = spacetimedb.reducer(
  { approvalId: t.u64(), status: t.string() },
  (ctx, { approvalId, status }) => {
    const a = ctx.db.approval.id.find(approvalId);
    if (!a) throw new SenderError(`no approval ${approvalId}`);
    if (!ctx.sender.isEqual(a.owner)) throw new SenderError('not your approval');
    if (a.status !== 'pending') throw new SenderError(`approval already ${a.status}`);
    ctx.db.approval.id.update({
      ...a,
      status: oneOf('status', status, APPROVAL_DECISION),
      decidedVia: 'app',
      updatedAt: ctx.timestamp,
    });
  }
);

// The worker relays an Auth0 CIBA result (#12, #42). Reducers can't do network I/O, so the module does
// NOT verify the CIBA id_token: it trusts the worker to have checked it. It does pin the reported subject
// to the owner's Auth0 account (taken from their verified token by register_user) and records the path.
export const recordCibaDecision = spacetimedb.reducer(
  { approvalId: t.u64(), status: t.string(), cibaSubject: t.string() },
  (ctx, { approvalId, status, cibaSubject }) => {
    requireWorker(ctx);
    const a = ctx.db.approval.id.find(approvalId);
    if (!a) throw new SenderError(`no approval ${approvalId}`);
    if (a.status !== 'pending') throw new SenderError(`approval already ${a.status}`);
    const u = ctx.db.user.identity.find(a.owner);
    if (!u || !u.auth0Sub || u.auth0Sub !== cibaSubject) {
      throw new SenderError("CIBA subject doesn't match the approval owner's Auth0 account");
    }
    ctx.db.approval.id.update({
      ...a,
      status: oneOf('status', status, APPROVAL_DECISION),
      decidedVia: 'ciba',
      cibaSubject,
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
