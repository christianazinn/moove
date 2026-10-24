---
title: Live spending log (x402)
lane: commerce
depends: 6
tracks: Coinbase x402, Spacetime, Visa
stretch: false
---

## Goal
The agents pay for data and services with USDC over x402 from a CDP wallet, and the user watches every payment arrive in a live spending log in the app.

## Context
Payment rail for the agent worker (`agents/`), plus an iOS screen subscribed to `payments` and `agentEvents`. Build it right after pricing (#6), because it logs the pricing agent's payments. See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `agents/src/integrations/x402.ts`: a CDP wallet on Base Sepolia (testnet USDC) and an x402-enabled fetch wrapper. Every paid call records a `payments` row (rail=x402, amount, payee, txHash, simulated flag).
- Spending caps: a per-agent budget and per-call max, with refusal logged as an `agentEvents` row.
- If no third-party x402 service fits, stand up a small x402-paywalled endpoint in the worker (e.g. a premium comps report) so the flow is real end to end.
- `ios/Moove/Features/Spending/`: live log (amount, what was bought, which agent, tx link to the Base Sepolia explorer), plus the budget remaining.

## Tables / reducers touched
`payments`, `agentEvents`.

## Acceptance criteria
- [ ] A pricing run produces at least one real testnet x402 payment with a tx hash.
- [ ] The payment shows up in the app's log in real time.
- [ ] Budget caps work: an over-budget call is refused and the refusal is logged.
- [ ] Anything simulated is visibly labeled "simulated".

## Demo fallback
Simulated payments (rail=x402, simulated=true) with a clear badge. Never present simulated payments as real.

## Notes & gotchas
- Packages: `@coinbase/x402`, `x402-fetch` / `x402-axios`, and the CDP SDK (`@coinbase/cdp-sdk`). Also check the Coinbase for Agents MCP. Verify all of these against https://docs.cdp.coinbase.com/x402/welcome and https://docs.cdp.coinbase.com/ai-agents/overview.
- **Every team member needs a verified Coinbase account** to be prize-eligible.
- The Coinbase submission requires a project summary, a working example, an **architecture diagram** and **builder feedback** (biggest blocker, workaround, the missing capability we most want). the lane owner owns these, and the notes go in `docs/tracks.md`.
- Keep CDP keys in env only.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
