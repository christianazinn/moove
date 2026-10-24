// Visa checkout rail (#15). The buy agent pays merchants by card through one interface:
//
//   authorize -> (re-check the approval gate) -> capture        or        authorize -> void
//
// Backends, chosen by VISA_PROVIDER:
//   - `acceptance`: Visa Acceptance (CyberSource) REST **sandbox**. A real API call with a real
//     transaction id, on a public Visa test card, so no money moves. HTTP Signature auth, built to
//     match cybersource-rest-client@0.0.84 (src/authentication/http) and the REST getting-started
//     guide. Only the sandbox host is allowed. Rows say simulated=false; event data says sandbox=true.
//     Our two sandbox merchants answer every authorization with a 502 SYSTEM_ERROR (merchant setup).
//   - `authorizenet`: Authorize.net (also a Visa Acceptance product) **sandbox** JSON API, same test
//     card, same labels as `acceptance` (simulated=false, sandbox=true). Auth is in the request body.
//     Only apitest.authorize.net is allowed.
//   - `simulated`: no network. Every result and row says `simulated: true` and messages start with
//     [SIMULATED]. This is the default whenever the AUTHORIZENET_* and VISA_ACCEPTANCE_* keys are missing.
//   - `vic`: Visa Intelligent Commerce. Credentials are gated (VIC/VTS onboarding), so this is only a
//     seam: see `createVicBackend` below.
//
// Every step writes an agent_event through the injected sink; every authorization writes a
// `payment` row (rail=visa) that moves pending -> settled (captured) or failed (declined/voided).
// Guardrails: a per-agent spend ledger + per-purchase max, and an approval gate that is checked
// before authorizing and again right before capture.

import crypto from 'node:crypto';
import { usdCapFromEnv } from './caps.js';
import { simulatedLabel } from './simulated.js';

export type VisaProvider = 'acceptance' | 'authorizenet' | 'simulated' | 'vic';

// Opaque here; the SpacetimeDB `Identity` in the worker (see payments wiring in buy.ts).
export type Owner = unknown;

/** Mirrors the `record_payment` reducer args. */
export interface VisaPaymentRecord {
  owner: Owner;
  agent: string;
  rail: 'visa';
  purpose: string;
  payee: string;
  amountUsdMicros: bigint;
  txHash: string;
  status: 'pending' | 'settled' | 'failed';
  simulated: boolean;
  refTable: string;
  refId: bigint;
}

/** Mirrors the `log_agent_event` reducer args (data is JSON-encoded by the sink). */
export interface VisaEventRecord {
  owner: Owner;
  agent: string;
  kind: 'tool_call' | 'payment' | 'approval' | 'error';
  message: string;
  refTable: string;
  refId: bigint;
  data: Record<string, unknown>;
}

/** Where payment and event rows go. The worker wires this to the SpacetimeDB reducers. */
export interface VisaSink {
  /** Inserts a payment row and resolves to its id. */
  recordPayment(p: VisaPaymentRecord): Promise<bigint>;
  updatePayment(paymentId: bigint, status: VisaPaymentRecord['status'], txHash: string): Promise<void>;
  logAgentEvent(e: VisaEventRecord): Promise<void>;
}

// ---------- backends ----------

export interface AuthorizeRequest {
  /** Our reference, sent as clientReferenceInformation.code (e.g. "moove-deal-12"). */
  reference: string;
  amountCents: bigint;
  currency: 'USD';
  description: string;
}

export interface BackendResult {
  /** Processor transaction id (CyberSource `id`, Authorize.net `transId`, or `sim_*`). */
  id: string;
  status: 'authorized' | 'captured' | 'voided' | 'declined';
  /** Processor status string, e.g. AUTHORIZED, PENDING, REVERSED, DECLINED. */
  processorStatus: string;
  reason?: string;
  /** HTTP status of the processor call (sandbox backends only), kept as evidence in event data. */
  httpStatus?: number;
}

export interface CheckoutBackend {
  provider: VisaProvider;
  /** True only for the no-network backend. */
  simulated: boolean;
  /** True for a real call to a sandbox (no real money). */
  sandbox: boolean;
  /** Who the payment row names as payee. */
  payee: string;
  authorize(req: AuthorizeRequest): Promise<BackendResult>;
  capture(authId: string, amountCents: bigint, reference: string): Promise<BackendResult>;
  void(authId: string, amountCents: bigint, reference: string, reason: string): Promise<BackendResult>;
}

/** The provider was explicitly requested but can't run (missing keys, bad host). Never falls back. */
export class VisaConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VisaConfigError';
  }
}

/** 401/403: the keys or account are wrong. Surfaced as a failed checkout, never as a simulated one. */
export const isAuthError = (err: unknown): boolean => err instanceof VisaApiError && (err.httpStatus === 401 || err.httpStatus === 403);

/** Worth trying again later: a transport error or a 5xx/timeout, not a decline, auth or config problem. */
export const isTransient = (err: unknown): boolean =>
  (err instanceof VisaApiError && !isAuthError(err) && (err.httpStatus === 0 || err.httpStatus === 408 || err.httpStatus === 429 || err.httpStatus >= 500)) ||
  (err instanceof TypeError && /fetch failed|network|socket|ECONN|ETIMEDOUT/i.test(err.message));

/** Thrown for transport/auth failures (not declines), so the caller can fall back. */
export class VisaApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number,
    readonly body: unknown,
  ) {
    super(message);
    this.name = 'VisaApiError';
  }
}

const centsToAmount = (c: bigint): string => `${c / 100n}.${(c % 100n).toString().padStart(2, '0')}`;

export const CYBERSOURCE_SANDBOX_HOST = 'apitest.cybersource.com';
// Public Visa test card from the CyberSource test-data guide. Sandbox only; never a real PAN.
// Same shape as CyberSource's own REST samples (cybersource-rest-samples-node), which send no CVV.
const VISA_TEST_CARD = { number: '4111111111111111', expirationMonth: '12', expirationYear: '2031' };

export interface AcceptanceConfig {
  merchantId: string;
  keyId: string;
  /** Base64 shared secret from Business Center > Key Management (REST - Shared Secret). */
  secret: string;
  host?: string;
  fetch?: typeof globalThis.fetch;
  now?: () => Date;
}

/**
 * HTTP Signature headers for one CyberSource REST call. Same signing string as the official SDK:
 * `host`, `date`, `request-target`, `digest` (POST/PUT/PATCH only), `v-c-merchant-id`, one per line,
 * HMAC-SHA256 with the base64-decoded secret.
 */
export function cybersourceSignedHeaders(
  cfg: { merchantId: string; keyId: string; secret: string; host: string },
  method: 'GET' | 'POST',
  path: string,
  body: string,
  date: Date,
): Record<string, string> {
  const httpDate = date.toUTCString(); // RFC 7231 / RFC 1123
  const m = method.toLowerCase();
  const lines = [`host: ${cfg.host}`, `date: ${httpDate}`, `request-target: ${m} ${path}`];
  const headers: Record<string, string> = {
    'v-c-merchant-id': cfg.merchantId,
    date: httpDate,
    'content-type': 'application/json;charset=utf-8',
    accept: 'application/hal+json;charset=utf-8',
  };
  let signed = 'host date request-target v-c-merchant-id';
  if (method === 'POST') {
    const digest = 'SHA-256=' + crypto.createHash('sha256').update(Buffer.from(body, 'utf8')).digest('base64');
    lines.push(`digest: ${digest}`);
    headers.digest = digest;
    signed = 'host date request-target digest v-c-merchant-id';
  }
  lines.push(`v-c-merchant-id: ${cfg.merchantId}`);
  const signature = crypto
    .createHmac('sha256', Buffer.from(cfg.secret, 'base64'))
    .update(Buffer.from(lines.join('\n'), 'utf8'))
    .digest('base64');
  headers.signature = `keyid="${cfg.keyId}", algorithm="HmacSHA256", headers="${signed}", signature="${signature}"`;
  return headers;
}

/** Visa Acceptance (CyberSource) REST sandbox: authorization hold, capture, authorization reversal. */
export function createAcceptanceBackend(cfg: AcceptanceConfig): CheckoutBackend {
  const host = cfg.host || CYBERSOURCE_SANDBOX_HOST;
  // Guardrail: this integration only ever talks to the sandbox with a test card.
  if (host !== CYBERSOURCE_SANDBOX_HOST) {
    throw new Error(`VISA_ACCEPTANCE_HOST must be ${CYBERSOURCE_SANDBOX_HOST} (sandbox only), got ${host}`);
  }
  const fetchImpl = cfg.fetch ?? globalThis.fetch;
  const now = cfg.now ?? (() => new Date());

  async function call(path: string, payload: object): Promise<Record<string, any>> {
    const body = JSON.stringify(payload);
    const headers = cybersourceSignedHeaders({ ...cfg, host }, 'POST', path, body, now());
    let res: Response;
    try {
      res = await fetchImpl(`https://${host}${path}`, { method: 'POST', headers, body });
    } catch (err) {
      // DNS, TLS, reset, offline: a transport failure (status 0), retryable.
      throw new VisaApiError(`CyberSource unreachable on ${path}: ${(err as Error).message}`, 0, undefined);
    }
    const text = await res.text();
    let json: Record<string, any> = {};
    try {
      json = text ? JSON.parse(text) : {};
    } catch {
      json = { raw: text.slice(0, 500) };
    }
    // 201 carries both approvals and soft declines (status DECLINED); 400 is INVALID_REQUEST or a
    // hard decline; 401 is a signature problem; 5xx is CyberSource being down.
    if (res.status === 201 || (res.status === 400 && json.status === 'DECLINED')) return { ...json, __http: res.status };
    const reason = json.errorInformation?.message ?? json.message ?? json.response?.rmsg ?? json.reason ?? text.slice(0, 200);
    throw new VisaApiError(`CyberSource ${res.status} on ${path}: ${reason}`, res.status, json);
  }

  const declineReason = (j: Record<string, any>) =>
    [j.errorInformation?.reason, j.errorInformation?.message].filter(Boolean).join(': ') || j.status;

  return {
    provider: 'acceptance',
    simulated: false,
    sandbox: true,
    payee: 'Visa Acceptance sandbox merchant',
    async authorize(req) {
      const j = await call('/pts/v2/payments', {
        clientReferenceInformation: { code: req.reference },
        processingInformation: { capture: false },
        paymentInformation: { card: VISA_TEST_CARD },
        orderInformation: {
          amountDetails: { totalAmount: centsToAmount(req.amountCents), currency: req.currency },
          billTo: {
            // CyberSource's sample test billing address.
            firstName: 'John',
            lastName: 'Doe',
            address1: '1 Market St',
            locality: 'san francisco',
            administrativeArea: 'CA',
            postalCode: '94105',
            country: 'US',
            email: 'test@cybs.com',
            phoneNumber: '4158880000',
          },
        },
      });
      const ok = j.status === 'AUTHORIZED';
      return { id: String(j.id ?? ''), status: ok ? 'authorized' : 'declined', processorStatus: String(j.status ?? ''), reason: ok ? undefined : declineReason(j), httpStatus: j.__http };
    },
    async capture(authId, amountCents, reference) {
      const j = await call(`/pts/v2/payments/${encodeURIComponent(authId)}/captures`, {
        clientReferenceInformation: { code: reference },
        orderInformation: { amountDetails: { totalAmount: centsToAmount(amountCents), currency: 'USD' } },
      });
      // PENDING = queued for settlement in the next batch; TRANSMITTED for online-capture merchants.
      const ok = j.status === 'PENDING' || j.status === 'TRANSMITTED';
      return { id: String(j.id ?? ''), status: ok ? 'captured' : 'declined', processorStatus: String(j.status ?? ''), reason: ok ? undefined : declineReason(j), httpStatus: j.__http };
    },
    async void(authId, amountCents, reference, reason) {
      // Releasing an uncaptured hold is an authorization reversal (/voids is for captures).
      const j = await call(`/pts/v2/payments/${encodeURIComponent(authId)}/reversals`, {
        clientReferenceInformation: { code: reference },
        reversalInformation: { amountDetails: { totalAmount: centsToAmount(amountCents) }, reason: reason.slice(0, 100) },
      });
      const ok = j.status === 'REVERSED';
      return { id: String(j.id ?? ''), status: ok ? 'voided' : 'declined', processorStatus: String(j.status ?? ''), reason: ok ? undefined : declineReason(j), httpStatus: j.__http };
    },
  };
}

export const AUTHORIZENET_SANDBOX_HOST = 'apitest.authorize.net';
// The same public Visa test card, in Authorize.net's shape (expirationDate is YYYY-MM). Sandbox only.
const AUTHORIZENET_TEST_CARD = { cardNumber: '4111111111111111', expirationDate: '2031-12', cardCode: '123' };

export interface AuthorizeNetConfig {
  apiLoginId: string;
  transactionKey: string;
  host?: string;
  fetch?: typeof globalThis.fetch;
}

// transactionResponse.responseCode -> our processorStatus string.
const AUTHORIZENET_RESPONSE: Record<string, string> = { '1': 'APPROVED', '2': 'DECLINED', '3': 'ERROR', '4': 'HELD_FOR_REVIEW' };

/**
 * refId and order.invoiceNumber are capped at 20 characters. Keep the tail, which holds the row id
 * (`moove-deal-12`), so two long references never collapse into the same prefix.
 */
export const authorizeNetRef = (reference: string): string => {
  const clean = reference.replace(/[^A-Za-z0-9_-]/g, '');
  return clean.length <= 20 ? clean : clean.slice(-20);
};

/** Authorize.net sandbox (JSON API): authOnlyTransaction, priorAuthCaptureTransaction, voidTransaction. */
export function createAuthorizeNetBackend(cfg: AuthorizeNetConfig): CheckoutBackend {
  const host = cfg.host || AUTHORIZENET_SANDBOX_HOST;
  // Guardrail: this integration only ever talks to the sandbox with a test card.
  if (host !== AUTHORIZENET_SANDBOX_HOST) {
    throw new Error(`AUTHORIZENET_HOST must be ${AUTHORIZENET_SANDBOX_HOST} (sandbox only), got ${host}`);
  }
  const fetchImpl = cfg.fetch ?? globalThis.fetch;

  async function call(reference: string, transactionRequest: object): Promise<Record<string, any>> {
    // The JSON API is XML-backed, so key order matters: merchantAuthentication, refId, transactionRequest.
    const body = JSON.stringify({
      createTransactionRequest: {
        merchantAuthentication: { name: cfg.apiLoginId, transactionKey: cfg.transactionKey },
        refId: authorizeNetRef(reference),
        transactionRequest,
      },
    });
    let res: Response;
    try {
      res = await fetchImpl(`https://${host}/xml/v1/request.api`, { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json' }, body });
    } catch (err) {
      // DNS, TLS, reset, offline: a transport failure (status 0), retryable.
      throw new VisaApiError(`Authorize.net unreachable: ${(err as Error).message}`, 0, undefined);
    }
    // Authorize.net starts its JSON with a UTF-8 BOM, which JSON.parse rejects.
    const text = (await res.text()).replace(/^﻿/, '');
    let json: Record<string, any> = {};
    try {
      json = text ? JSON.parse(text) : {};
    } catch {
      json = { raw: text.slice(0, 500) };
    }
    const msg = json.messages?.message?.[0] as { code?: string; text?: string } | undefined;
    // Evidence for the fallback/error events, in the fields the CyberSource body has (never credentials).
    const evidence = { id: json.transactionResponse?.transId, status: json.messages?.resultCode, reason: msg ? `${msg.code}: ${msg.text}` : undefined, response: json };
    if (res.status !== 200) throw new VisaApiError(`Authorize.net ${res.status}: ${msg?.text ?? text.slice(0, 200)}`, res.status, evidence);
    // HTTP is 200 either way: approvals and declines both carry transactionResponse.responseCode
    // (with resultCode Ok or Error). Without one, the request itself was refused.
    if (json.transactionResponse?.responseCode) return { ...json.transactionResponse, __http: res.status, __message: msg };
    // E00007/E00008: wrong or inactive API login ID / transaction key, like CyberSource's 401/403.
    // E00001 is "An error occurred during processing. Please try again", so it counts as a 5xx.
    const httpStatus = msg?.code === 'E00007' ? 401 : msg?.code === 'E00008' ? 403 : msg?.code === 'E00001' ? 503 : 400;
    throw new VisaApiError(`Authorize.net ${msg?.code ?? 'error'}: ${msg?.text ?? text.slice(0, 200)}`, httpStatus, evidence);
  }

  const result = (t: Record<string, any>, ok: BackendResult['status']): BackendResult => {
    const code = String(t.responseCode);
    // 1 = approved. 2 = declined, 3 = error, 4 = held for review: none of those is a usable hold.
    const approved = code === '1';
    const err = t.errors?.[0] as { errorCode?: string; errorText?: string } | undefined;
    const reason = approved ? undefined : [err?.errorCode, err?.errorText ?? t.__message?.text].filter(Boolean).join(': ') || AUTHORIZENET_RESPONSE[code] || code;
    return { id: String(t.transId ?? ''), status: approved ? ok : 'declined', processorStatus: AUTHORIZENET_RESPONSE[code] ?? code, reason, httpStatus: t.__http };
  };

  return {
    provider: 'authorizenet',
    simulated: false,
    sandbox: true,
    payee: 'Authorize.net sandbox merchant',
    async authorize(req) {
      // Field order follows the schema: transactionType, amount, payment, order, billTo.
      const t = await call(req.reference, {
        transactionType: 'authOnlyTransaction',
        amount: centsToAmount(req.amountCents),
        payment: { creditCard: AUTHORIZENET_TEST_CARD },
        order: { invoiceNumber: authorizeNetRef(req.reference), description: req.description.slice(0, 255) },
        billTo: {
          // Same sample test billing address as the CyberSource backend.
          firstName: 'John',
          lastName: 'Doe',
          address: '1 Market St',
          city: 'San Francisco',
          state: 'CA',
          zip: '94105',
          country: 'US',
        },
      });
      return result(t, 'authorized');
    },
    async capture(authId, amountCents, reference) {
      const t = await call(reference, { transactionType: 'priorAuthCaptureTransaction', amount: centsToAmount(amountCents), refTransId: authId });
      return result(t, 'captured');
    },
    async void(authId, _amountCents, reference) {
      // Releasing an uncaptured hold is a void of the authorization (no amount or reason field).
      const t = await call(reference, { transactionType: 'voidTransaction', refTransId: authId });
      return result(t, 'voided');
    },
  };
}

/** No network. Every id starts with `sim_` and every row says simulated: true. */
export function createSimulatedBackend(opts: { delayMs?: number; declineOverCents?: bigint } = {}): CheckoutBackend {
  // Globally unique (not a per-process counter): the worker finds the inserted payment row by txHash.
  const newId = () => `sim_auth_${crypto.randomUUID()}`;
  const wait = () => (opts.delayMs ? new Promise(r => setTimeout(r, opts.delayMs)) : Promise.resolve());
  return {
    provider: 'simulated',
    simulated: true,
    sandbox: false,
    payee: 'simulated merchant',
    async authorize(req) {
      await wait();
      if (opts.declineOverCents !== undefined && req.amountCents > opts.declineOverCents) {
        return { id: newId(), status: 'declined', processorStatus: 'DECLINED', reason: 'simulated decline' };
      }
      return { id: newId(), status: 'authorized', processorStatus: 'AUTHORIZED' };
    },
    async capture(authId) {
      await wait();
      return { id: `sim_cap_${authId}`, status: 'captured', processorStatus: 'PENDING' };
    },
    async void(authId) {
      await wait();
      return { id: `sim_rev_${authId}`, status: 'voided', processorStatus: 'REVERSED' };
    },
  };
}

/**
 * Visa Intelligent Commerce seam. VIC credentials (API key + shared secret, MLE keys, VTS token
 * requestor, consumer/enrollment ids) come only through Visa onboarding. With them, implement:
 *   authorize -> POST /vacp/v1/instructions (mandate: declineThreshold = amount, merchant, expiry,
 *                consumerPrompt) then POST /vacp/v1/instructions/{id}/credentials
 *   capture   -> hand the token + cryptogram to the merchant, then POST .../{id}/confirmations
 *   void      -> PUT /vacp/v1/instructions/{id}/cancel
 * (X-Pay token + JWE message-level encryption; see github.com/visa/ai packages/api-client.)
 */
export function createVicBackend(): CheckoutBackend {
  throw new Error('VISA_PROVIDER=vic is not implemented: VIC sandbox credentials are gated behind Visa onboarding');
}

// ---------- guardrails ----------

/** The capture call failed in transit, so whether money moved is unknown. */
export class CaptureUnknown extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CaptureUnknown';
  }
}

export class VisaSpendRefused extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VisaSpendRefused';
  }
}

export const dollars = (cents: bigint): string => `$${centsToAmount(cents)}`;

/** Per-agent card budget, in cents. Reserved at authorization, released on void/decline. */
export class CardSpendLedger {
  private spent = new Map<string, bigint>();
  constructor(
    readonly capPerAgentCents: bigint,
    readonly maxPerPurchaseCents: bigint,
  ) {}
  spentBy(agent: string): bigint {
    return this.spent.get(agent) ?? 0n;
  }
  remaining(agent: string): bigint {
    const left = this.capPerAgentCents - this.spentBy(agent);
    return left > 0n ? left : 0n;
  }
  /** Why `reserve` would refuse this amount right now, without reserving anything. */
  check(agent: string, cents: bigint): string | undefined {
    if (cents <= 0n) return `amount must be positive, got ${cents}`;
    if (cents > this.maxPerPurchaseCents) return `${dollars(cents)} is over the per-purchase max of ${dollars(this.maxPerPurchaseCents)}`;
    if (this.spentBy(agent) + cents > this.capPerAgentCents) {
      return `${dollars(cents)} would exceed the ${agent} card budget (${dollars(this.remaining(agent))} of ${dollars(this.capPerAgentCents)} left)`;
    }
    return undefined;
  }
  reserve(agent: string, cents: bigint): void {
    if (cents <= 0n) throw new VisaSpendRefused(`amount must be positive, got ${cents}`);
    if (cents > this.maxPerPurchaseCents) {
      throw new VisaSpendRefused(`${dollars(cents)} is over the per-purchase max of ${dollars(this.maxPerPurchaseCents)}`);
    }
    if (this.spentBy(agent) + cents > this.capPerAgentCents) {
      throw new VisaSpendRefused(`${dollars(cents)} would exceed the ${agent} card budget (${dollars(this.remaining(agent))} of ${dollars(this.capPerAgentCents)} left)`);
    }
    this.spent.set(agent, this.spentBy(agent) + cents);
  }
  /** Counts spend from before this process started (pending/settled payment rows). */
  seed(agent: string, cents: bigint): void {
    if (cents > 0n) this.spent.set(agent, this.spentBy(agent) + cents);
  }
  release(agent: string, cents: bigint): void {
    const next = this.spentBy(agent) - cents;
    this.spent.set(agent, next > 0n ? next : 0n);
  }
}

export interface ApprovalView {
  id: bigint;
  status: string;
  amountCents: bigint;
}

export type GateResult = { ok: true; approvalId?: bigint } | { ok: false; needsApproval: boolean; reason: string };

/**
 * The approval rule. At or under the owner's threshold the agent may buy on its own; above it
 * (or with threshold -1, "always ask") it needs an `approved` approval for exactly this amount.
 */
export function approvalGate(amountCents: bigint, thresholdCents: bigint, approval: ApprovalView | undefined): GateResult {
  // A user's "no" sticks even if the threshold is raised later.
  if (approval && (approval.status === 'denied' || approval.status === 'expired')) {
    return { ok: false, needsApproval: false, reason: `approval ${approval.status}` };
  }
  const needs = thresholdCents < 0n || amountCents > thresholdCents;
  if (!needs) return { ok: true };
  if (!approval) return { ok: false, needsApproval: true, reason: `${dollars(amountCents)} is over the ${thresholdCents < 0n ? 'always-ask' : dollars(thresholdCents)} threshold` };
  if (approval.status === 'pending') return { ok: false, needsApproval: false, reason: 'waiting for approval' };
  if (approval.status !== 'approved') return { ok: false, needsApproval: false, reason: `approval ${approval.status}` };
  if (approval.amountCents !== amountCents) {
    return { ok: false, needsApproval: false, reason: `approved ${dollars(approval.amountCents)} but the amount is now ${dollars(amountCents)}` };
  }
  return { ok: true, approvalId: approval.id };
}

// ---------- checkout ----------

export interface PurchaseContext {
  owner: Owner;
  agent: string;
  /** Shown in the spending log, e.g. `Twin bed frame from IKEA`. */
  purpose: string;
  /** Merchant the deal is from (the sandbox merchant stands in for it). */
  merchant: string;
  refTable: string;
  refId: bigint;
  amountCents: bigint;
  /** The owner's approval threshold (-1 = always ask). Pass a getter so re-checks see changes. */
  thresholdCents: bigint | (() => bigint);
  /** Latest approval for this purchase, read fresh each time (so a late denial is seen). */
  currentApproval: () => ApprovalView | undefined;
  /** Extra re-check right before capture (e.g. the user still has this deal chosen). Return a reason to abort. */
  stillValid?: () => string | undefined;
  /** VIC-style mandate text: what the user asked the agent to buy. */
  consumerPrompt: string;
}

/** The parts of a purchase that every event names. */
export type EventContext = Pick<PurchaseContext, 'owner' | 'agent' | 'purpose' | 'merchant' | 'refTable' | 'refId' | 'amountCents'>;

const thresholdOf = (ctx: PurchaseContext): bigint => (typeof ctx.thresholdCents === 'function' ? ctx.thresholdCents() : ctx.thresholdCents);

export interface Hold {
  authId: string;
  paymentId: bigint;
  amountCents: bigint;
  provider: VisaProvider;
  simulated: boolean;
}

export interface PurchaseResult {
  /** `unknown`: the capture call failed in transit; the payment row stays pending until reconciled. */
  status: 'captured' | 'declined' | 'voided' | 'refused' | 'needs_approval' | 'waiting' | 'unknown';
  reason?: string;
  /** A transient failure before any hold was placed: nothing to undo, safe to try again later. */
  retryable?: boolean;
  hold?: Hold;
  captureId?: string;
  provider: VisaProvider;
  simulated: boolean;
}

export interface VisaCheckoutOptions {
  sink: VisaSink;
  backend: CheckoutBackend;
  ledger: CardSpendLedger;
  /** When the real backend fails on transport/auth (not a decline), retry that one authorization here. */
  fallback?: CheckoutBackend;
}

export class VisaCheckout {
  private readonly sink: VisaSink;
  private readonly backend: CheckoutBackend;
  private readonly ledger: CardSpendLedger;
  private readonly fallback?: CheckoutBackend;
  /**
   * Every hold this checkout placed, with the backend that placed it. Capture and void always go to
   * that backend (never "whatever is current"), and a hold can be closed (captured or voided) once,
   * so budget is never released twice or released after a capture.
   */
  private readonly holds = new Map<string, { backend: CheckoutBackend; open: boolean }>();

  constructor(opts: VisaCheckoutOptions) {
    this.sink = opts.sink;
    this.backend = opts.backend;
    this.ledger = opts.ledger;
    this.fallback = opts.fallback;
  }

  /** The configured backend. A fallback is per authorization and shows up on the Hold/result instead. */
  get provider(): VisaProvider {
    return this.backend.provider;
  }
  get simulated(): boolean {
    return this.backend.simulated;
  }
  /** service_config `visa_checkout` (#191). */
  get mode(): VisaCheckoutMode {
    return checkoutMode(this.backend, this.fallback);
  }
  remaining(agent: string): bigint {
    return this.ledger.remaining(agent);
  }
  /** Why a purchase of this amount would be refused by the card caps (checked before asking the user). */
  spendBlocker(agent: string, cents: bigint): string | undefined {
    return this.ledger.check(agent, cents);
  }
  /** Counts spend recorded before this process started, so a restart doesn't reset the cap. */
  seedSpent(agent: string, cents: bigint): void {
    this.ledger.seed(agent, cents);
  }

  /** The whole flow: gate, reserve, authorize, re-check, capture (or void). Never throws for declines. */
  async purchase(ctx: PurchaseContext): Promise<PurchaseResult> {
    const label = { provider: this.backend.provider, simulated: this.backend.simulated };
    const gate = approvalGate(ctx.amountCents, thresholdOf(ctx), ctx.currentApproval());
    if (!gate.ok) {
      await this.event(ctx, this.backend, 'approval', `Not charging yet: ${gate.reason}`, { gate: gate.reason });
      return { status: gate.needsApproval ? 'needs_approval' : gate.reason === 'waiting for approval' ? 'waiting' : 'refused', reason: gate.reason, ...label };
    }

    let hold: Hold;
    try {
      hold = await this.authorize(ctx);
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      return { status: err instanceof VisaSpendRefused ? 'refused' : 'declined', reason, retryable: isTransient(err), ...label };
    }
    const holdLabel = { provider: hold.provider, simulated: hold.simulated };

    // Re-check right before capture: the approval could have been revoked/changed, or the user
    // could have picked another deal, while the authorization was in flight.
    const again = approvalGate(ctx.amountCents, thresholdOf(ctx), ctx.currentApproval());
    const invalid = !again.ok ? again.reason : ctx.stillValid?.();
    if (invalid) {
      await this.void(ctx, hold, invalid);
      return { status: 'voided', reason: invalid, hold, ...holdLabel };
    }
    try {
      const captureId = await this.capture(ctx, hold);
      return { status: 'captured', hold, captureId, ...holdLabel };
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      const status = err instanceof VisaSpendRefused ? 'voided' : err instanceof CaptureUnknown ? 'unknown' : 'declined';
      return { status, reason, hold, ...holdLabel };
    }
  }

  /** Reserves budget and places an authorization hold; records a pending payment row. */
  async authorize(ctx: PurchaseContext): Promise<Hold> {
    try {
      this.ledger.reserve(ctx.agent, ctx.amountCents);
    } catch (err) {
      await this.event(ctx, this.backend, 'error', `Refused card payment for ${ctx.purpose}: ${(err as Error).message}`, {
        refused: true,
        remainingCents: this.ledger.remaining(ctx.agent).toString(),
      });
      throw err;
    }
    const mandate = {
      // VIC-shaped purchase instruction, kept in event data (maps onto POST /vacp/v1/instructions).
      maxAmountCents: ctx.amountCents.toString(),
      merchant: ctx.merchant,
      consumerPrompt: ctx.consumerPrompt,
      effectiveUntil: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
    };
    const req: AuthorizeRequest = { reference: `moove-${ctx.refTable}-${ctx.refId}`, amountCents: ctx.amountCents, currency: 'USD', description: ctx.purpose };

    // The fallback applies to this authorization only: later purchases try the real backend again,
    // and this hold remembers which backend placed it.
    let backend = this.backend;
    let r: BackendResult;
    try {
      await this.event(ctx, backend, 'tool_call', `${tag(backend)} Authorizing ${dollars(ctx.amountCents)} hold for ${ctx.purpose}`, { mandate, step: 'authorize' });
      try {
        r = await backend.authorize(req);
      } catch (err) {
        const fb = this.fallback;
        // Never hide broken keys or config behind a simulated label: 401/403 always surface.
        if (!(err instanceof VisaApiError) || isAuthError(err) || !fb || fb === backend) throw err;
        await this.event(ctx, backend, 'error', `${tag(backend)} ${err.message}; falling back to the ${fb.simulated ? 'simulated' : fb.provider} checkout`, {
          httpStatus: err.httpStatus,
          // Processor request id + reason, for support tickets (never credentials).
          requestId: (err.body as Record<string, unknown> | undefined)?.id,
          processorStatus: (err.body as Record<string, unknown> | undefined)?.status,
          processorReason: (err.body as Record<string, unknown> | undefined)?.reason,
          fallback: fb.provider,
        });
        backend = fb;
        await this.event(ctx, backend, 'tool_call', `${tag(backend)} Authorizing ${dollars(ctx.amountCents)} hold for ${ctx.purpose}`, { mandate, step: 'authorize' });
        r = await backend.authorize(req);
      }
    } catch (err) {
      this.ledger.release(ctx.agent, ctx.amountCents);
      await this.event(ctx, backend, 'error', `${tag(backend)} Authorization for ${ctx.purpose} failed: ${(err as Error).message}`, { step: 'authorize' });
      throw err;
    }

    const authorized = r.status === 'authorized';
    // The sink finds the inserted row by txHash, so it must be unique even when a decline has no id.
    const txHash = r.id || `${backend.provider}_${authorized ? 'auth' : 'declined'}_${crypto.randomUUID()}`;
    let paymentId: bigint;
    try {
      paymentId = await this.sink.recordPayment({
        owner: ctx.owner,
        agent: ctx.agent,
        rail: 'visa',
        // Sandbox charges say so in the spending log itself, not only in event data.
        purpose: backend.sandbox ? `[Visa sandbox] ${ctx.purpose}` : ctx.purpose,
        payee: backend.sandbox ? `${backend.payee} (for ${ctx.merchant})` : `${ctx.merchant} (${backend.payee})`,
        amountUsdMicros: ctx.amountCents * 10_000n,
        txHash,
        status: authorized ? 'pending' : 'failed',
        simulated: backend.simulated,
        refTable: ctx.refTable,
        refId: ctx.refId,
      });
    } catch (err) {
      // No row to track the hold by: release it rather than leave an untracked authorization.
      this.ledger.release(ctx.agent, ctx.amountCents);
      if (authorized) await backend.void(r.id, ctx.amountCents, req.reference, 'could not record payment').catch(() => undefined);
      await this.event(ctx, backend, 'error', `${tag(backend)} Could not record the payment for ${ctx.purpose}: ${(err as Error).message}`, { authId: r.id, step: 'authorize' });
      throw err;
    }
    if (!authorized) {
      this.ledger.release(ctx.agent, ctx.amountCents);
      await this.event(ctx, backend, 'error', `${tag(backend)} Card declined for ${ctx.purpose}: ${r.reason ?? r.processorStatus}`, { authId: r.id, processorStatus: r.processorStatus, paymentId: paymentId.toString() });
      throw new Error(`declined: ${r.reason ?? r.processorStatus}`);
    }
    const hold: Hold = { authId: r.id, paymentId, amountCents: ctx.amountCents, provider: backend.provider, simulated: backend.simulated };
    this.holds.set(holdKey(hold), { backend, open: true });
    await this.event(ctx, backend, 'payment', `${tag(backend)} Hold of ${dollars(ctx.amountCents)} placed for ${ctx.purpose}`, { authId: r.id, processorStatus: r.processorStatus, httpStatus: r.httpStatus, paymentId: paymentId.toString(), mandate });
    return hold;
  }

  /**
   * Captures a hold for its full amount and settles the payment row. Re-applies the approval gate to
   * the hold's amount itself, so calling this directly can't skip approval; a failing gate voids the
   * hold and throws VisaSpendRefused.
   */
  async capture(ctx: PurchaseContext, hold: Hold): Promise<string> {
    const entry = this.openHold(hold, 'capture');
    const backend = entry.backend;
    const gate = approvalGate(hold.amountCents, thresholdOf(ctx), ctx.currentApproval());
    if (!gate.ok) {
      await this.void(ctx, hold, gate.reason);
      throw new VisaSpendRefused(`not captured: ${gate.reason}`);
    }
    await this.event(ctx, backend, 'tool_call', `${tag(backend)} Capturing ${dollars(hold.amountCents)} for ${ctx.purpose}`, { authId: hold.authId, step: 'capture' });
    let r: BackendResult;
    try {
      r = await backend.capture(hold.authId, hold.amountCents, `moove-${ctx.refTable}-${ctx.refId}`);
    } catch (err) {
      // The capture may have gone through before the connection failed. Don't void, don't release
      // budget, leave the payment row pending: that blocks a repeat purchase until someone reconciles.
      entry.open = false;
      await this.event(ctx, backend, 'error', `${tag(backend)} Capture for ${ctx.purpose} failed in transit: ${(err as Error).message}. Left pending for reconciliation`, { authId: hold.authId, reconcile: true });
      throw new CaptureUnknown((err as Error).message);
    }
    if (r.status !== 'captured') {
      await this.event(ctx, backend, 'error', `${tag(backend)} Capture declined for ${ctx.purpose}: ${r.reason ?? r.processorStatus}`, { authId: hold.authId, processorStatus: r.processorStatus });
      await this.void(ctx, hold, 'capture declined').catch(() => undefined);
      throw new Error(`capture declined: ${r.reason ?? r.processorStatus}`);
    }
    // Captured: the budget stays spent and the hold can't be voided or captured again. A sink failure
    // past this point must not turn a real capture into a "declined" result.
    entry.open = false;
    try {
      await this.sink.updatePayment(hold.paymentId, 'settled', '');
      await this.event(ctx, backend, 'payment', `${tag(backend)} Paid ${dollars(hold.amountCents)} for ${ctx.purpose}`, { authId: hold.authId, captureId: r.id, processorStatus: r.processorStatus, httpStatus: r.httpStatus, paymentId: hold.paymentId.toString() });
    } catch (err) {
      console.warn(`[visa] captured ${hold.authId} but could not record it: ${(err as Error).message}`);
    }
    return r.id;
  }

  /** Releases a hold (authorization reversal) and marks the payment failed. */
  async void(ctx: PurchaseContext, hold: Hold, reason: string): Promise<void> {
    const entry = this.openHold(hold, 'void');
    const backend = entry.backend;
    entry.open = false;
    let r: BackendResult | undefined;
    let failure: string | undefined;
    try {
      r = await backend.void(hold.authId, hold.amountCents, `moove-${ctx.refTable}-${ctx.refId}`, reason);
      if (r.status !== 'voided') failure = r.reason ?? r.processorStatus;
    } catch (err) {
      failure = (err as Error).message;
    }
    await this.sink.updatePayment(hold.paymentId, 'failed', '').catch(err => console.warn(`[visa] could not mark payment ${hold.paymentId} failed: ${(err as Error).message}`));
    if (failure === undefined) {
      // Only a confirmed reversal gives the budget back; a stuck hold keeps counting until it expires.
      this.ledger.release(ctx.agent, hold.amountCents);
      await this.event(ctx, backend, 'payment', `${tag(backend)} Released the ${dollars(hold.amountCents)} hold for ${ctx.purpose}: ${reason}`, { authId: hold.authId, reversalId: r!.id, processorStatus: r!.processorStatus, voided: true });
    } else {
      await this.event(ctx, backend, 'error', `${tag(backend)} Could not release the hold for ${ctx.purpose}: ${failure} (it expires on its own)`, { authId: hold.authId, voided: false, reason });
    }
  }

  /** True if this process placed a hold with this processor id (in flight, closed, or capture unknown). */
  knowsHold(authId: string): boolean {
    for (const k of this.holds.keys()) if (k.endsWith(`:${authId}`)) return true;
    return false;
  }

  /**
   * Reverses a hold an earlier run of the worker placed and never closed (it restarted between
   * authorize and capture). Only a confirmed reversal marks the row failed; anything else (wrong
   * backend now, or the processor refuses because the capture did go through) leaves it pending with
   * an error event for reconciliation. Budget stays counted (it was seeded from the row). True if released.
   */
  async releaseStale(ctx: EventContext, p: { paymentId: bigint; authId: string; simulated: boolean }): Promise<boolean> {
    if (this.knowsHold(p.authId)) return false;
    const backend = p.simulated ? (this.backend.simulated ? this.backend : (this.fallback ?? createSimulatedBackend())) : this.backend.simulated ? undefined : this.backend;
    let failure: string | undefined;
    let r: BackendResult | undefined;
    if (!backend || !p.authId) {
      failure = `no ${p.simulated ? 'simulated' : 'real'} checkout configured to release it`;
    } else {
      try {
        r = await backend.void(p.authId, ctx.amountCents, `moove-${ctx.refTable}-${ctx.refId}`, 'left open by an earlier run');
        if (r.status !== 'voided') failure = r.reason ?? r.processorStatus;
      } catch (err) {
        failure = (err as Error).message;
      }
    }
    // No backend means a real hold while this run is simulated: label it as the real (sandbox) hold
    // it is, never as [SIMULATED]. Both real backends are sandboxes; the row doesn't say which one.
    const b = backend ?? { ...this.backend, provider: 'acceptance' as const, simulated: false, sandbox: true };
    if (failure !== undefined) {
      await this.event(ctx, b, 'error', `${tag(b)} A ${dollars(ctx.amountCents)} hold for ${ctx.purpose} from an earlier run is still pending and could not be released: ${failure}. Left pending for reconciliation`, { authId: p.authId, paymentId: p.paymentId.toString(), reconcile: true });
      return false;
    }
    await this.sink.updatePayment(p.paymentId, 'failed', '');
    await this.event(ctx, b, 'payment', `${tag(b)} Released the ${dollars(ctx.amountCents)} hold for ${ctx.purpose} left open by an earlier run`, { authId: p.authId, reversalId: r!.id, processorStatus: r!.processorStatus, paymentId: p.paymentId.toString(), voided: true });
    return true;
  }

  private openHold(hold: Hold, op: 'capture' | 'void') {
    const entry = this.holds.get(holdKey(hold));
    if (!entry) throw new Error(`cannot ${op} unknown hold ${hold.authId}`);
    if (!entry.open) throw new Error(`cannot ${op} hold ${hold.authId}: already captured or voided`);
    return entry;
  }

  private event(ctx: EventContext, b: CheckoutBackend, kind: VisaEventRecord['kind'], message: string, data: Record<string, unknown>) {
    return this.sink.logAgentEvent({
      owner: ctx.owner,
      agent: ctx.agent,
      kind,
      // Simulated checkout steps are always labeled, including "Not charging yet" and refusals.
      message: b.simulated ? simulatedLabel(message) : message,
      refTable: ctx.refTable,
      refId: ctx.refId,
      data: {
        ...data,
        rail: 'visa',
        provider: b.provider,
        simulated: b.simulated,
        sandbox: b.sandbox,
        ...(b.sandbox ? { note: `${b.provider === 'authorizenet' ? 'Authorize.net' : 'Visa Acceptance'} sandbox, test card, no real money` } : {}),
        amountCents: ctx.amountCents.toString(),
        merchant: ctx.merchant,
      },
    });
  }
}

const holdKey = (h: Hold) => `${h.provider}:${h.simulated}:${h.authId}`;
const tag = (b: CheckoutBackend): string => (b.simulated ? '[SIMULATED]' : b.sandbox ? '[VISA SANDBOX]' : '[VISA]');

// ---------- wiring from env ----------

export interface VisaEnv {
  VISA_PROVIDER?: string;
  VISA_ACCEPTANCE_MERCHANT_ID?: string;
  VISA_ACCEPTANCE_KEY_ID?: string;
  VISA_ACCEPTANCE_SECRET?: string;
  VISA_ACCEPTANCE_HOST?: string;
  VISA_SPEND_CAP_USD?: string;
  VISA_MAX_PER_PURCHASE_USD?: string;
  VISA_SIM_DELAY_MS?: string;
  VISA_FALLBACK_SIMULATED?: string;
  AUTHORIZENET_API_LOGIN_ID?: string;
  AUTHORIZENET_TRANSACTION_KEY?: string;
  AUTHORIZENET_HOST?: string;
}

export const hasAcceptanceKeys = (env: VisaEnv): boolean =>
  !!(env.VISA_ACCEPTANCE_MERCHANT_ID && env.VISA_ACCEPTANCE_KEY_ID && env.VISA_ACCEPTANCE_SECRET);

export const hasAuthorizeNetKeys = (env: VisaEnv): boolean => !!(env.AUTHORIZENET_API_LOGIN_ID && env.AUTHORIZENET_TRANSACTION_KEY);

// An explicit "0" means "no card spending". Non-numeric or negative -> a loud warning and the default (caps.ts).
const capCents = (env: VisaEnv, key: 'VISA_SPEND_CAP_USD' | 'VISA_MAX_PER_PURCHASE_USD'): bigint =>
  BigInt(Math.round(usdCapFromEnv(env, key) * 100));

/** Picks the backend. Falls back to simulated (with a reason) whenever the real one can't run. */
/** Stands in for an explicitly requested provider that can't run: every call fails loudly. */
export function createMisconfiguredBackend(provider: VisaProvider, why: string): CheckoutBackend {
  const fail = async (): Promise<BackendResult> => {
    throw new VisaConfigError(`VISA_PROVIDER=${provider} is set but ${why}; not falling back to simulated`);
  };
  return { provider, simulated: false, sandbox: provider === 'acceptance' || provider === 'authorizenet', payee: `${provider} (misconfigured)`, authorize: fail, capture: fail, void: fail };
}

export function selectBackend(env: VisaEnv, fetchImpl?: typeof globalThis.fetch): { backend: CheckoutBackend; note?: string } {
  const sim = createSimulatedBackend({ delayMs: Number(env.VISA_SIM_DELAY_MS ?? '400') });
  // No VISA_PROVIDER: Authorize.net if its keys are set (its sandbox works), else CyberSource, else simulated.
  const wanted = (env.VISA_PROVIDER || (hasAuthorizeNetKeys(env) ? 'authorizenet' : hasAcceptanceKeys(env) ? 'acceptance' : 'simulated')) as VisaProvider;
  if (wanted === 'simulated') return { backend: sim };
  if (wanted === 'vic') {
    try {
      return { backend: createVicBackend() };
    } catch (err) {
      return { backend: sim, note: (err as Error).message };
    }
  }
  if (wanted === 'authorizenet') {
    const explicitAnet = env.VISA_PROVIDER === 'authorizenet';
    if (!hasAuthorizeNetKeys(env)) {
      return explicitAnet
        ? { backend: createMisconfiguredBackend('authorizenet', 'AUTHORIZENET_* keys are missing'), note: 'AUTHORIZENET_* keys are missing' }
        : { backend: sim, note: 'AUTHORIZENET_* keys are missing' };
    }
    try {
      return {
        backend: createAuthorizeNetBackend({
          apiLoginId: env.AUTHORIZENET_API_LOGIN_ID!,
          transactionKey: env.AUTHORIZENET_TRANSACTION_KEY!,
          host: env.AUTHORIZENET_HOST,
          fetch: fetchImpl,
        }),
      };
    } catch (err) {
      const why = (err as Error).message;
      return explicitAnet ? { backend: createMisconfiguredBackend('authorizenet', why), note: why } : { backend: sim, note: why };
    }
  }
  if (wanted !== 'acceptance') return { backend: sim, note: `unknown VISA_PROVIDER '${wanted}'` };
  const explicit = env.VISA_PROVIDER === 'acceptance';
  if (!hasAcceptanceKeys(env)) {
    return explicit
      ? { backend: createMisconfiguredBackend('acceptance', 'VISA_ACCEPTANCE_* keys are missing'), note: 'VISA_ACCEPTANCE_* keys are missing' }
      : { backend: sim, note: 'VISA_ACCEPTANCE_* keys are missing' };
  }
  try {
    return {
      backend: createAcceptanceBackend({
        merchantId: env.VISA_ACCEPTANCE_MERCHANT_ID!,
        keyId: env.VISA_ACCEPTANCE_KEY_ID!,
        secret: env.VISA_ACCEPTANCE_SECRET!,
        host: env.VISA_ACCEPTANCE_HOST,
        fetch: fetchImpl,
      }),
    };
  } catch (err) {
    const why = (err as Error).message;
    return explicit ? { backend: createMisconfiguredBackend('acceptance', why), note: why } : { backend: sim, note: why };
  }
}

// Falling back to simulated on a 5xx/network error is opt-in once a provider is explicitly chosen
// (VISA_FALLBACK_SIMULATED=1), and on by default only when the provider was picked from the keys.
const fallbackAllowed = (env: VisaEnv): boolean =>
  env.VISA_FALLBACK_SIMULATED === '1' || (!env.VISA_PROVIDER && env.VISA_FALLBACK_SIMULATED !== '0');

/** What the worker announces as service_config `visa_checkout` (#191), so the app can label purchase approvals. */
export type VisaCheckoutMode = 'simulated' | 'sandbox' | 'sandbox+fallback';

/**
 * The checkout mode for a backend and its fallback. A real (sandbox) backend with no fallback is
 * `sandbox`, even when misconfigured: those checkouts fail loudly and are never simulated.
 */
export const checkoutMode = (backend: Pick<CheckoutBackend, 'simulated'>, fallback?: Pick<CheckoutBackend, 'simulated'>): VisaCheckoutMode =>
  backend.simulated ? 'simulated' : fallback?.simulated ? 'sandbox+fallback' : 'sandbox';

/** The mode `createVisaCheckout(sink, env)` would run in. No network: selecting a backend only builds it. */
export function visaCheckoutMode(env: VisaEnv = process.env): VisaCheckoutMode {
  const { backend } = selectBackend(env);
  return checkoutMode(backend, !backend.simulated && fallbackAllowed(env) ? { simulated: true } : undefined);
}

export function createVisaCheckout(sink: VisaSink, env: VisaEnv = process.env, fetchImpl?: typeof globalThis.fetch): VisaCheckout {
  const { backend, note } = selectBackend(env, fetchImpl);
  if (note) console.warn(backend.simulated ? `[visa] using the SIMULATED checkout: ${note}` : `[visa] CHECKOUT WILL FAIL: ${note}`);
  const ledger = new CardSpendLedger(capCents(env, 'VISA_SPEND_CAP_USD'), capCents(env, 'VISA_MAX_PER_PURCHASE_USD'));
  const fallback = backend.simulated || !fallbackAllowed(env) ? undefined : createSimulatedBackend({ delayMs: Number(env.VISA_SIM_DELAY_MS ?? '400') });
  return new VisaCheckout({ sink, backend, ledger, fallback });
}
