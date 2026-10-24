// x402 payment rail (#7). Agents pay for data with testnet USDC from a CDP wallet on Base Sepolia.
//
// Every paid call goes through `paidFetch`, which:
//   1. makes the request; if the server answers 402, reads its payment requirements
//   2. checks our own per-agent budget + per-call max (refusals become `agent_event` rows)
//   3. signs the payment with the CDP wallet and retries
//   4. reads the settlement (tx hash) from the PAYMENT-RESPONSE header and records a `payment` row
//
// We drive the 402 flow by hand instead of using `wrapFetchWithPayment` so each call carries its own
// agent/purpose context and the budget check happens before anything is signed. The SDK's own
// spendControls are still set on the CDP client as a backstop.
//
// With no CDP keys (or X402_SIMULATE=1) the rail is simulated: nothing is signed and every payment
// row says `simulated: true`. Never present those as real payments.

import { x402HTTPClient } from "@x402/core/client";
import type { PaymentPayload, PaymentRequired, PaymentRequirements } from "@x402/core/types";

export const BASE_SEPOLIA = "eip155:84532";
export const USDC_BASE_SEPOLIA = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
export const EXPLORER_TX_URL = "https://sepolia.basescan.org/tx/";

// Opaque here; the SpacetimeDB `Identity` once the worker scaffold lands.
export type Owner = unknown;

/** Mirrors the `record_payment` reducer args (amounts in USD micros; 1 USDC atomic unit = 1 micro). */
export interface PaymentRecord {
  owner: Owner;
  agent: string;
  rail: "x402";
  purpose: string;
  payee: string;
  amountUsdMicros: bigint;
  txHash: string;
  status: "settled" | "failed";
  simulated: boolean;
  refTable: string;
  refId: bigint;
}

/** Mirrors the `log_agent_event` reducer args. */
export interface AgentEventRecord {
  owner: Owner;
  agent: string;
  kind: "tool_call" | "payment" | "error";
  message: string;
  refTable: string;
  refId: bigint;
  dataJson: string;
}

/** What one x402 step amounted to: about to pay, paid, failed after trying, or refused by our budget. */
export type X402Outcome = "paying" | "settled" | "failed" | "refused";

/** Keys present in `data_json` of every agent_event the x402 rail writes (amounts are USD-micro strings). */
export interface X402EventData {
  rail: "x402";
  outcome: X402Outcome;
  simulated: boolean;
  remainingUsdMicros: string;
  capUsdMicros: string;
}

/** Where payment and event rows go. Wired to the SpacetimeDB reducers by the worker. */
export interface PaymentSink {
  recordPayment(p: PaymentRecord): Promise<void>;
  logAgentEvent(e: AgentEventRecord): Promise<void>;
}

/** Anything that can sign an x402 payment (CdpX402Client, or a fake in tests). */
export interface PaymentSigner {
  createPaymentPayload(paymentRequired: PaymentRequired): Promise<PaymentPayload>;
}

export interface PaidCallContext {
  owner: Owner;
  agent: string;
  /** Shown in the spending log, e.g. "comps for 'IKEA Poang chair'". */
  purpose: string;
  refTable?: string;
  refId?: bigint;
  /** Simulated mode only: what this call would have cost, in USD micros. */
  quotedUsdMicros?: bigint;
}

export interface PaidFetchResult {
  response: Response;
  /** Present when a payment was made (or simulated) for this call. */
  payment?: PaymentRecord;
}

export class SpendRefusedError extends Error {
  constructor(
    message: string,
    readonly agent: string,
    readonly amountUsdMicros: bigint,
  ) {
    super(message);
    this.name = "SpendRefusedError";
  }
}

export const usdToMicros = (usd: number): bigint => BigInt(Math.round(usd * 1_000_000));
export const formatUsd = (micros: bigint): string => `$${(Number(micros) / 1_000_000).toFixed(micros < 10_000n ? 4 : 2)}`;

/**
 * Per-agent budgets. Amounts are reserved before signing and released if the payment fails, so
 * concurrent calls from one agent can't overspend.
 */
export class SpendLedger {
  private spent = new Map<string, bigint>();

  constructor(
    readonly capPerAgentMicros: bigint,
    readonly maxPerCallMicros: bigint,
  ) {}

  spentBy(agent: string): bigint {
    return this.spent.get(agent) ?? 0n;
  }

  remaining(agent: string): bigint {
    const left = this.capPerAgentMicros - this.spentBy(agent);
    return left > 0n ? left : 0n;
  }

  /** Throws SpendRefusedError if the payment isn't allowed; otherwise reserves it. */
  reserve(agent: string, amount: bigint): void {
    if (amount > this.maxPerCallMicros) {
      throw new SpendRefusedError(
        `${formatUsd(amount)} is over the per-call max of ${formatUsd(this.maxPerCallMicros)}`,
        agent,
        amount,
      );
    }
    if (this.spentBy(agent) + amount > this.capPerAgentMicros) {
      throw new SpendRefusedError(
        `${formatUsd(amount)} would exceed the ${agent} budget (${formatUsd(this.remaining(agent))} of ${formatUsd(this.capPerAgentMicros)} left)`,
        agent,
        amount,
      );
    }
    this.spent.set(agent, this.spentBy(agent) + amount);
  }

  /**
   * Counts spend that already happened (e.g. `payment` rows from before a worker restart), so a
   * restart can't reset an agent's budget. Never throws: an over-cap agent just gets refused.
   */
  seed(agent: string, amount: bigint): void {
    if (amount > 0n) this.spent.set(agent, this.spentBy(agent) + amount);
  }

  release(agent: string, amount: bigint): void {
    const next = this.spentBy(agent) - amount;
    this.spent.set(agent, next > 0n ? next : 0n);
  }
}

export interface X402RailOptions {
  sink: PaymentSink;
  ledger: SpendLedger;
  /** Omit for a simulated rail. */
  signer?: PaymentSigner;
  fetch?: typeof globalThis.fetch;
  /** If non-empty, only these payTo addresses are paid (case-insensitive). */
  allowedPayees?: string[];
}

export class X402Rail {
  readonly simulated: boolean;
  private readonly sink: PaymentSink;
  private readonly ledger: SpendLedger;
  private readonly signer?: PaymentSigner;
  private readonly http?: x402HTTPClient;
  private readonly fetchImpl: typeof globalThis.fetch;
  private readonly allowedPayees: Set<string>;

  constructor(opts: X402RailOptions) {
    this.allowedPayees = new Set((opts.allowedPayees ?? []).map((a) => a.toLowerCase()));
    this.sink = opts.sink;
    this.ledger = opts.ledger;
    this.signer = opts.signer;
    this.simulated = !opts.signer;
    this.fetchImpl = opts.fetch ?? globalThis.fetch;
    // x402HTTPClient only needs createPaymentPayload from the client it wraps.
    if (opts.signer) this.http = new x402HTTPClient(opts.signer as ConstructorParameters<typeof x402HTTPClient>[0]);
  }

  remaining(agent: string): bigint {
    return this.ledger.remaining(agent);
  }

  /** Counts earlier spend (from `payment` rows) against an agent's budget. */
  seedSpent(agent: string, micros: bigint): void {
    this.ledger.seed(agent, micros);
  }

  async paidFetch(ctx: PaidCallContext, input: string | URL, init?: RequestInit): Promise<PaidFetchResult> {
    return this.simulated ? this.simulatedFetch(ctx, input, init) : this.realFetch(ctx, input, init);
  }

  private async realFetch(ctx: PaidCallContext, input: string | URL, init?: RequestInit): Promise<PaidFetchResult> {
    const http = this.http!;
    const request = new Request(input, init);
    const first = await this.fetchImpl(request.clone());
    if (first.status !== 402) return { response: first };

    let body: unknown;
    try {
      const text = await first.text();
      body = text ? JSON.parse(text) : undefined;
    } catch {
      body = undefined;
    }
    const paymentRequired = http.getPaymentRequiredResponse((name) => first.headers.get(name), body);
    const requirements = pickRequirements(paymentRequired);
    if (!requirements) {
      await this.event(ctx, "error", `No USDC payment option on Base Sepolia for ${request.url}`, {
        ...this.railData(ctx, "failed"),
        url: request.url,
        accepts: paymentRequired.accepts.map((a) => ({ network: a.network, asset: a.asset, amount: a.amount })),
      });
      throw new SpendRefusedError("server does not accept Base Sepolia USDC", ctx.agent, 0n);
    }
    const amount = BigInt(requirements.amount);
    if (!/^0x[0-9a-fA-F]{40}$/.test(requirements.payTo) || (this.allowedPayees.size > 0 && !this.allowedPayees.has(requirements.payTo.toLowerCase()))) {
      await this.event(ctx, "error", `Refused x402 payment for ${ctx.purpose}: payee ${requirements.payTo} is not on the allowlist`, {
        ...this.railData(ctx, "refused"),
        url: request.url,
        payee: requirements.payTo,
        amountUsdMicros: amount.toString(),
        refused: true,
      });
      throw new SpendRefusedError(`payee ${requirements.payTo} is not allowed`, ctx.agent, amount);
    }
    await this.reserveOrRefuse(ctx, amount, requirements.payTo, request.url);

    let settled: PaymentRecord;
    let response: Response;
    let released = false;
    try {
      // Sign only the option we budgeted for.
      const payload = await this.signer!.createPaymentPayload({ ...paymentRequired, accepts: [requirements] });
      const paid = request.clone();
      for (const [k, v] of Object.entries(http.encodePaymentSignatureHeader(payload))) paid.headers.set(k, v);
      response = await this.fetchImpl(paid);

      const settle = response.headers.get("PAYMENT-RESPONSE") || response.headers.get("X-PAYMENT-RESPONSE")
        ? http.getPaymentSettleResponse((name) => response.headers.get(name))
        : undefined;
      const ok = response.ok && !!settle?.success;
      settled = this.record(ctx, {
        payee: requirements.payTo,
        amount: settle?.amount ? BigInt(settle.amount) : amount,
        txHash: settle?.transaction ?? "",
        status: ok ? "settled" : "failed",
        simulated: false,
      });
      if (!ok) {
        this.ledger.release(ctx.agent, amount);
        released = true;
      }
      await this.sink.recordPayment(settled);
      await this.event(
        ctx,
        ok ? "payment" : "error",
        ok
          ? `Paid ${formatUsd(settled.amountUsdMicros)} USDC for ${ctx.purpose}`
          : `x402 payment for ${ctx.purpose} failed (HTTP ${response.status}${settle?.errorReason ? `, ${settle.errorReason}` : ""})`,
        {
          ...this.railData(ctx, ok ? "settled" : "failed"),
          url: request.url,
          payee: settled.payee,
          amountUsdMicros: settled.amountUsdMicros.toString(),
          txHash: settled.txHash,
          network: requirements.network,
          explorer: settled.txHash ? EXPLORER_TX_URL + settled.txHash : undefined,
        },
      );
    } catch (err) {
      if (!released) this.ledger.release(ctx.agent, amount);
      await this.event(ctx, "error", `x402 payment for ${ctx.purpose} failed: ${(err as Error).message}`, {
        ...this.railData(ctx, "failed"),
        url: request.url,
        payee: requirements.payTo,
        amountUsdMicros: amount.toString(),
      });
      throw err;
    }
    return { response, payment: settled };
  }

  private async simulatedFetch(ctx: PaidCallContext, input: string | URL, init?: RequestInit): Promise<PaidFetchResult> {
    const amount = ctx.quotedUsdMicros ?? 0n;
    const url = new Request(input, init).url;
    await this.reserveOrRefuse(ctx, amount, "simulated", url);
    let response: Response;
    try {
      response = await this.fetchImpl(input, init);
    } catch (err) {
      this.ledger.release(ctx.agent, amount);
      await this.event(ctx, "error", `[SIMULATED] x402 payment for ${ctx.purpose} failed: ${(err as Error).message}`, {
        ...this.railData(ctx, "failed"),
        url,
        payee: "simulated",
        amountUsdMicros: amount.toString(),
      });
      throw err;
    }
    // Like realFetch: a non-2xx endpoint means the payment didn't go through, so refund and record it as failed.
    const ok = response.ok;
    if (!ok) this.ledger.release(ctx.agent, amount);
    const payment = this.record(ctx, { payee: "simulated", amount, txHash: "", status: ok ? "settled" : "failed", simulated: true });
    await this.sink.recordPayment(payment);
    await this.event(
      ctx,
      ok ? "payment" : "error",
      ok
        ? `[SIMULATED] Paid ${formatUsd(amount)} USDC for ${ctx.purpose}`
        : `[SIMULATED] x402 payment for ${ctx.purpose} failed (HTTP ${response.status})`,
      {
        ...this.railData(ctx, ok ? "settled" : "failed"),
        url,
        payee: payment.payee,
        amountUsdMicros: amount.toString(),
      },
    );
    return { response, payment };
  }

  private async reserveOrRefuse(ctx: PaidCallContext, amount: bigint, payee: string, url: string): Promise<void> {
    try {
      this.ledger.reserve(ctx.agent, amount);
    } catch (err) {
      if (err instanceof SpendRefusedError) {
        await this.event(ctx, "error", `Refused x402 payment for ${ctx.purpose}: ${err.message}`, {
          ...this.railData(ctx, "refused"),
          url,
          payee,
          amountUsdMicros: amount.toString(),
          refused: true,
        });
      }
      throw err;
    }
    await this.event(ctx, "tool_call", `Paying ${formatUsd(amount)} for ${ctx.purpose}`, {
      ...this.railData(ctx, "paying"),
      url,
      payee,
      amountUsdMicros: amount.toString(),
    });
  }

  /**
   * Fields on every x402 `agent_event.data_json`, so the app can show the live budget and tell
   * x402 payment failures apart from other errors. Budget is read after this step's reserve/release.
   */
  private railData(ctx: PaidCallContext, outcome: X402Outcome): X402EventData {
    return {
      rail: "x402",
      outcome,
      simulated: this.simulated,
      remainingUsdMicros: this.ledger.remaining(ctx.agent).toString(),
      capUsdMicros: this.ledger.capPerAgentMicros.toString(),
    };
  }

  private record(
    ctx: PaidCallContext,
    p: { payee: string; amount: bigint; txHash: string; status: PaymentRecord["status"]; simulated: boolean },
  ): PaymentRecord {
    return {
      owner: ctx.owner,
      agent: ctx.agent,
      rail: "x402",
      purpose: ctx.purpose,
      payee: p.payee,
      amountUsdMicros: p.amount,
      txHash: p.txHash,
      status: p.status,
      simulated: p.simulated,
      refTable: ctx.refTable ?? "",
      refId: ctx.refId ?? 0n,
    };
  }

  private event(ctx: PaidCallContext, kind: AgentEventRecord["kind"], message: string, data: Record<string, unknown>) {
    return this.sink.logAgentEvent({
      owner: ctx.owner,
      agent: ctx.agent,
      kind,
      message,
      refTable: ctx.refTable ?? "",
      refId: ctx.refId ?? 0n,
      dataJson: JSON.stringify(data),
    });
  }
}

/** Only pay in USDC on Base Sepolia, and take the cheapest such option. */
function pickRequirements(pr: PaymentRequired): PaymentRequirements | undefined {
  return pr.accepts
    .filter((a) => a.network === BASE_SEPOLIA && a.asset.toLowerCase() === USDC_BASE_SEPOLIA.toLowerCase())
    .sort((a, b) => (BigInt(a.amount) < BigInt(b.amount) ? -1 : 1))[0];
}

export interface RailEnv {
  CDP_API_KEY_ID?: string;
  CDP_API_KEY_SECRET?: string;
  CDP_WALLET_SECRET?: string;
  X402_SIMULATE?: string;
  AGENT_SPEND_CAP_USDC?: string;
  X402_MAX_PER_CALL_USDC?: string;
  /** Comma-separated payTo addresses the rail may pay. Empty = any valid address (still capped). */
  X402_ALLOWED_PAYEES?: string;
}

export const hasCdpKeys = (env: RailEnv): boolean =>
  !!(env.CDP_API_KEY_ID && env.CDP_API_KEY_SECRET && env.CDP_WALLET_SECRET);

/**
 * Build the rail from env. Real (CDP wallet on Base Sepolia) when CDP keys are set and
 * X402_SIMULATE isn't "1"; otherwise simulated.
 */
export async function createX402Rail(sink: PaymentSink, env: RailEnv = process.env): Promise<X402Rail> {
  const cap = usdToMicros(Number(env.AGENT_SPEND_CAP_USDC ?? "5"));
  const perCall = usdToMicros(Number(env.X402_MAX_PER_CALL_USDC ?? "0.10"));
  const ledger = new SpendLedger(cap, perCall);
  const allowedPayees = (env.X402_ALLOWED_PAYEES ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (env.X402_SIMULATE === "1" || !hasCdpKeys(env)) return new X402Rail({ sink, ledger, allowedPayees });

  const { CdpX402Client } = await import("@coinbase/cdp-sdk/x402");
  const signer = new CdpX402Client({
    environment: "development",
    walletConfig: { type: "eoa", accountName: "moove-agents" },
    // Backstop under our ledger: never sign anything but Base Sepolia USDC within the same caps.
    spendControls: {
      maxAmountPerPayment: { atomic: perCall, asset: USDC_BASE_SEPOLIA },
      maxCumulativeSpend: { atomic: cap * 4n, asset: USDC_BASE_SEPOLIA },
      maxCumulativeSpendWindow: "24h",
      allowedNetworks: [BASE_SEPOLIA],
      allowedAssets: [USDC_BASE_SEPOLIA],
    },
  });
  return new X402Rail({ sink, ledger, signer, allowedPayees });
}
