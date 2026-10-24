---
title: Pricing agent (Apify)
lane: backend
depends: 4, 5
tracks: Apify, Coinbase x402, Anthropic
stretch: false
---

## Goal
Each item gets an estimated resale value backed by real comparable listings from Facebook Marketplace, Craigslist and eBay.

## Context
An agent in the worker (`agents/`). It subscribes to items that have details but no estValue, runs Apify scrapers, has Claude pick the relevant comps and estimate a price, and writes `comps` plus `items.estValue`. Its paid data calls go through x402 so #7 can log the spend. See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `agents/src/integrations/apify.ts`: run actors for FB Marketplace, Craigslist and eBay search by query plus location, with a timeout and result cap.
- `agents/src/agents/pricing.ts`: build a search query from the item details, fetch comps, have Claude filter them and estimate a price range, then write `comps` rows and `items.estValue`.
- Route at least one paid data call through x402 (`agents/src/integrations/x402.ts`, shared with #7). Every call writes an `agentEvents` row with its cost.
- Cache raw Apify results to `agents/fixtures/comps/` for demo replay.

## Tables / reducers touched
`comps`, `items` (estValue, priceLow, priceHigh), `payments` (via #7), `agentEvents`.

## Acceptance criteria
- [ ] Fixture items get prices with at least 3 comps each, and each comp links to a real listing URL.
- [ ] Prices look sane (a used IKEA chair isn't priced at $500).
- [ ] Agent steps are visible in `agentEvents`.
- [ ] Runs without blocking other agents (concurrency limit, backoff).

## Demo fallback
Replay cached comps from fixtures, labeled "cached comps" in the UI.

## Notes & gotchas
- Apify actor names, inputs and pricing: verify against the current Apify Store. Some FB Marketplace actors need cookies, so prefer public-search actors.
- Apify track: "use Apify in a meaningful way". Stretch: publish our own "moving comps" actor for the $400 Best Actor prize.
- Bright Data is NOT used (their rules disqualify mocked demo data).
- Use `claude-haiku-5-5` for comp filtering and `claude-sonnet-5-5` for the estimate. Both are env-overridable.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
