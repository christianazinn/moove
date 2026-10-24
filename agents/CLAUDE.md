# agents/ - Agent worker (Node/TS)

Lanes: backend (vision, pricing, sort, fraud) and commerce (x402 spending, eBay listing, approvals, Visa).

- A long-running Node process, connected to SpacetimeDB as a client via generated bindings in `src/module_bindings/` (never hand-edit them).
- Pattern: subscribe to rows that need work, do the work, write results via reducers. Writes never bypass reducers.
- **Every agent step writes an `agentEvents` row** (plan / tool_call / result / payment / approval / error).
- One file per external service in `src/integrations/` (anthropic, apify, x402, ebay, visa, auth0), each behind an interface with a **labeled simulated implementation** for demo fallback. `visa.ts` stays a stub until the Visa Starter Pack is out.
- Agents live in `src/agents/` (vision, pricing, sort, listing, buy, fraud).
- Spending: enforce `AGENT_SPEND_CAP_USDC`. Purchases or listings above the user's `approvalThresholdCents` require an `approvals` row and an Auth0 async authorization (CIBA) before they proceed.
- Models come from env (`MODEL_VISION`, `MODEL_FAST`, `MODEL_AGENT`).
- Cache real Apify responses into `fixtures/` so the demo can replay them if live calls fail. Label any replay.
- Config comes from `.env.local` (see root `.env.example`).
- x402/CDP, Apify, eBay, Auth0 for AI Agents and Visa APIs change often, so check current docs first.
