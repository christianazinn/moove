// Phone approval for expensive listings/purchases (#12): Auth0 CIBA (Client-Initiated
// Backchannel Authentication) with Auth0 Guardian push. The worker starts a backchannel
// request for the owner's Auth0 user, Guardian shows the binding message on their phone,
// and the worker polls the token endpoint until they approve or deny.
// Docs: https://auth0.com/docs/get-started/authentication-and-authorization-flow/client-initiated-backchannel-authentication-flow/mobile-push-notifications-with-ciba
//
// Env (worker .env.local; config.ts has already loaded it):
//   AUTH0_DOMAIN               tenant domain, e.g. moove.us.auth0.com (https:// and trailing / are ok)
//   AUTH0_CIBA_CLIENT_ID       the confidential "moove-worker" Regular Web App with the CIBA grant
//   AUTH0_CIBA_CLIENT_SECRET   its secret (never logged)
//   AUTH0_AUDIENCE             optional API audience
// Note: AUTH0_CLIENT_ID / AUTH0_CLIENT_SECRET belong to the iOS native app and can't run CIBA.

export type ApprovalStart = {
  authReqId: string;
  expiresAt: number; // epoch ms, from expires_in on our clock
  intervalSec: number; // how long to wait before the first / next poll
};

// 'denied' from Auth0 can also mean the request expired (access_denied covers both), so the
// caller tells them apart with its own clock against expiresAt. 'expired' is only returned if
// the server says so explicitly (expired_token, per the OpenID CIBA spec).
export type ApprovalPoll =
  | { status: 'pending' }
  | { status: 'slow_down'; intervalSec: number }
  | { status: 'approved' }
  | { status: 'denied' }
  | { status: 'expired' };

export interface ApprovalGateway {
  readonly simulated: boolean;
  readonly name: string; // shown in agent events, e.g. "Auth0 Guardian"
  start(req: { auth0Sub: string; bindingMessage: string }): Promise<ApprovalStart>;
  poll(authReqId: string): Promise<ApprovalPoll>;
}

export type Auth0Config = { domain: string; clientId: string; clientSecret: string; audience: string };

// Returns the CIBA config, or null unless domain, client id and secret are all set.
export function auth0Config(env: NodeJS.ProcessEnv = process.env): Auth0Config | null {
  const domain = (env.AUTH0_DOMAIN ?? '')
    .trim()
    .replace(/^https?:\/\//i, '')
    .replace(/\/+$/, '');
  const clientId = (env.AUTH0_CIBA_CLIENT_ID ?? '').trim();
  const clientSecret = (env.AUTH0_CIBA_CLIENT_SECRET ?? '').trim();
  if (!domain || !clientId || !clientSecret) return null;
  return { domain, clientId, clientSecret, audience: (env.AUTH0_AUDIENCE ?? '').trim() };
}

// ---------- binding message ----------

const BINDING_MAX = 64;

function formatAmount(cents: bigint): string {
  const neg = cents < 0n;
  const abs = neg ? -cents : cents;
  return `${neg ? '-' : ''}${abs / 100n}.${(abs % 100n).toString().padStart(2, '0')}`;
}

// Auth0 rules: required, <= 64 chars, only letters, digits, spaces and + - _ . , : #.
// Produces e.g. "Moove: sell 420.00 USD: Herman Miller chair". The amount comes first and is
// never cut, so a scraped title (e.g. "chair for 1.00 USD") can't read as the price. The title
// is sanitized and truncated to fit.
export function toBindingMessage(action: 'sell' | 'buy', title: string, amountCents: bigint): string {
  const head = `Moove: ${action} ${formatAmount(amountCents)} USD`;
  const clean = title
    .normalize('NFKD')
    .replace(/[^A-Za-z0-9+\-_.,:# ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const budget = BINDING_MAX - head.length - 2; // ": "
  let t = clean.length > budget ? clean.slice(0, Math.max(0, budget)) : clean;
  t = t.replace(/[\s+\-_.,:#]+$/, ''); // don't end a truncated title on a space or punctuation
  return t ? `${head}: ${t}` : head;
}

// ---------- real Auth0 CIBA ----------

type OAuthError = { error?: string; error_description?: string; interval?: number };

async function readJson(r: Response): Promise<Record<string, unknown>> {
  try {
    return (await r.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

// Decodes a JWT payload without verifying it. Acceptable here: the token comes straight back
// from the tenant's token endpoint over TLS in response to our authenticated client request.
function jwtPayload(jwt: string): Record<string, unknown> | null {
  const part = jwt.split('.')[1];
  if (!part) return null;
  try {
    return JSON.parse(Buffer.from(part, 'base64url').toString('utf8')) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function describe(where: string, status: number, j: OAuthError): string {
  // Only the error code and description from Auth0, never request bodies (they hold the secret).
  return `${where} failed (HTTP ${status}): ${j.error ?? 'unknown_error'}${j.error_description ? ` - ${j.error_description}` : ''}`;
}

export function auth0CibaGateway(cfg: Auth0Config): ApprovalGateway {
  const base = `https://${cfg.domain}`;
  const subByReq = new Map<string, string>(); // auth_req_id -> requested sub, to check the id_token
  return {
    simulated: false,
    name: 'Auth0 Guardian',
    async start({ auth0Sub, bindingMessage }) {
      const body = new URLSearchParams({
        client_id: cfg.clientId,
        client_secret: cfg.clientSecret,
        scope: 'openid',
        binding_message: bindingMessage,
        login_hint: JSON.stringify({ format: 'iss_sub', iss: `${base}/`, sub: auth0Sub }),
        requested_expiry: '300', // <= 300 selects Guardian push (higher would switch to email)
      });
      if (cfg.audience) body.set('audience', cfg.audience);
      const r = await fetch(`${base}/bc-authorize`, { method: 'POST', body });
      const j = await readJson(r);
      if (!r.ok) throw new Error(describe('Auth0 bc-authorize', r.status, j as OAuthError));
      const authReqId = typeof j.auth_req_id === 'string' ? j.auth_req_id : '';
      if (!authReqId) throw new Error('Auth0 bc-authorize returned no auth_req_id');
      const expiresIn = Number(j.expires_in ?? 300);
      const interval = Number(j.interval ?? 5);
      subByReq.set(authReqId, auth0Sub);
      return {
        authReqId,
        expiresAt: Date.now() + (Number.isFinite(expiresIn) && expiresIn > 0 ? expiresIn : 300) * 1000,
        intervalSec: Number.isFinite(interval) && interval > 0 ? interval : 5,
      };
    },
    async poll(authReqId) {
      const body = new URLSearchParams({
        grant_type: 'urn:openid:params:grant-type:ciba',
        auth_req_id: authReqId,
        client_id: cfg.clientId,
        client_secret: cfg.clientSecret,
      });
      const r = await fetch(`${base}/oauth/token`, { method: 'POST', body });
      const j = await readJson(r);
      if (r.ok) {
        // Tokens are never stored or logged; we only check who approved. We ask for scope
        // openid, so a real approval always carries an id_token: fail closed without one.
        const expected = subByReq.get(authReqId);
        subByReq.delete(authReqId);
        const sub = typeof j.id_token === 'string' ? jwtPayload(j.id_token)?.sub : undefined;
        if (!expected || sub !== expected) {
          throw new Error(
            sub === undefined
              ? 'Auth0 approval came back without a readable id_token, ignoring it'
              : 'Auth0 approval came back for a different user than requested, ignoring it'
          );
        }
        return { status: 'approved' };
      }
      const e = j as OAuthError;
      switch (e.error) {
        case 'authorization_pending':
          return { status: 'pending' };
        case 'slow_down': {
          const iv = Number(e.interval);
          return { status: 'slow_down', intervalSec: Number.isFinite(iv) && iv > 0 ? iv : 0 };
        }
        case 'access_denied':
          subByReq.delete(authReqId);
          return { status: 'denied' };
        case 'expired_token':
          subByReq.delete(authReqId);
          return { status: 'expired' };
        default:
          throw new Error(describe('Auth0 CIBA token poll', r.status, e));
      }
    },
  };
}

// ---------- selection ----------

export type GatewayChoice = { gateway: ApprovalGateway | null; mode: string };

// Real CIBA when AUTH0_DOMAIN + AUTH0_CIBA_CLIENT_ID + AUTH0_CIBA_CLIENT_SECRET are set; else none
// (approvals wait for the in-app inbox, which calls decide_approval itself). `mode` is for a startup
// log line. There is no simulated approver any more: since #42 the worker can only record a decision
// with record_ciba_decision, which needs the owner's real Auth0 subject.
export function selectApprovalGateway(env: NodeJS.ProcessEnv = process.env): GatewayChoice {
  const cfg = auth0Config(env);
  if (cfg) {
    return { gateway: auth0CibaGateway(cfg), mode: `Auth0 CIBA via Guardian push (tenant ${cfg.domain})` };
  }
  if (Number(env.APPROVAL_SIM_AUTO_APPROVE_SEC ?? '0') > 0) {
    console.warn('[approval] APPROVAL_SIM_AUTO_APPROVE_SEC is ignored: the worker can no longer approve its own requests (#42)');
  }
  return { gateway: null, mode: 'Auth0 not configured: approvals wait for the in-app inbox' };
}
