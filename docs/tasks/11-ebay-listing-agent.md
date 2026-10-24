---
title: eBay listing agent
lane: commerce
depends: 6, 8
tracks: Visa, Anthropic, Apify
stretch: false
---

## Goal
For every "sell" item, an agent writes a strong listing (title, description, price, photos) and posts it to eBay, with a status the user can track. **For the demo the eBay post is simulated** (team call, 2026-10-23): the agent walks the real Sell Inventory API sequence with realistic latency and agentEvents, but calls nothing, and every listing has `simulated=true` and a visible label.

## Context
An agent in the worker (`agents/`). It subscribes to items with `disposition=sell` and no listing. It uses comps from #6 for pricing, and expensive listings wait for #12's phone approval before posting. See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `agents/src/agents/listing.ts`: Claude drafts the title, description, condition notes, category and price (from comps) and writes a `listings` row (status=draft).
- If the price is over the approval threshold, set the listing status to `awaiting_approval` and call `request_approval`, which hands off to #12.
- `agents/src/integrations/ebay.ts`: the Sell Inventory API sandbox flow (inventory item -> offer -> publish), saving `external_id` and the URL.
- iOS `ios/Moove/Features/Listings/`: listing cards with status (draft / awaiting approval / live / sold) and an edit-before-post option.
- Write an `agentEvents` row for every step.

## Tables / reducers touched
`listings`, `approvals`, `items` (read), `comps` (read), `agentEvents`.

## Acceptance criteria
- [ ] Sell fixture items get drafted listings with prices justified by comps.
- [ ] Listings "post" (simulated) with an item number and a viewable listing page, labeled simulated in data and UI.
- [ ] Expensive items wait for approval and are not posted.
- [ ] Listing text can be copied for manual cross-posting to FB Marketplace or Craigslist (no APIs exist for those).

## Demo fallback
Drafted listings with a "simulated post" badge if eBay sandbox auth fails.

## Notes & gotchas
- Real eBay is out of scope for the demo. If it comes back: developer account approval takes ~1 business day, business-policy opt-in is API-only in sandbox, category suggestions don't work in sandbox, and photos must be public HTTPS URLs.
- `LISTING_SIM_SOLD_AFTER_SEC` (worker env, default 0 = off) flips posted simulated listings to `sold` after a delay for the demo.
- `claude-opus-5-5` for listing planning, or sonnet if latency matters (env-overridable).

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
