---
title: eBay listing agent
lane: commerce
depends: 6, 8
tracks: Visa, Anthropic, Apify
stretch: false
---

## Goal
For every "sell" item, an agent writes a strong listing (title, description, price, photos) and posts it to eBay (sandbox), with a status the user can track.

## Context
An agent in the worker (`agents/`). It subscribes to items with `disposition=sell` and no listing. It uses comps from #6 for pricing, and expensive listings wait for #12's phone approval before posting. See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `agents/src/agents/listing.ts`: Claude drafts the title, description, condition notes, category and price (from comps) and writes a `listings` row (status=draft).
- If the price is over the approval threshold, set `needsApproval` and create an `approvals` row, which hands off to #12.
- `agents/src/integrations/ebay.ts`: the Sell Inventory API sandbox flow (inventory item -> offer -> publish), saving `ebayId` and the URL.
- iOS `ios/Moove/Features/Listings/`: listing cards with status (draft / awaiting approval / live / sold) and an edit-before-post option.
- Write an `agentEvents` row for every step.

## Tables / reducers touched
`listings`, `approvals`, `items` (read), `comps` (read), `agentEvents`.

## Acceptance criteria
- [ ] Sell fixture items get drafted listings with prices justified by comps.
- [ ] At least one listing is actually published in the eBay sandbox, with a viewable URL.
- [ ] Expensive items wait for approval and are not posted.
- [ ] Listing text can be copied for manual cross-posting to FB Marketplace or Craigslist (no APIs exist for those).

## Demo fallback
Drafted listings with a "simulated post" badge if eBay sandbox auth fails.

## Notes & gotchas
- Sign up for an **eBay developer sandbox keyset NOW**. The OAuth user-token flow for a sandbox seller takes setup. Verify the Sell Inventory API steps against current eBay docs.
- Photos must be public URLs for eBay. The worker upload endpoint needs to be reachable (tunnel or deployed).
- `claude-opus-5-5` for listing planning, or sonnet if latency matters (env-overridable).

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
