# 0144: Crash-safe listing posts now, payment rows later

**Status:** part A accepted, part B deferred until after the demo (decided on #144 by the backend lane, Sat Oct 24 3:25 AM PDT, past the proposal's decide-by)

## Context
A worker restart between `publish()` and `update_listing('posted')` re-posts a listing. A restart between paying and `record_payment` hides that spend from the restart budget seed. See #144.

## Decision
- **A (accepted):** `listing.status` gains `posting`. `update_listing(..., 'posting', ...)` is worker-only and allowed only from `draft` or `awaiting_approval`. The listing agent sets it before `publish()` and `posted`/`failed` after. On start it doesn't re-post a `posting` listing: real eBay re-checks by SKU, simulated is marked `failed` with an error event. This is a new string value, not a schema change.
- **B (deferred):** `begin_payment` + `payment.idempotency_key` adds a column. That changes the `payment` row layout, so every iOS decoder needs a coordinated regen. Not worth the risk before the demo. Today's caps (x402 per-call max, CDP spend controls, `VISA_SPEND_CAP_USD`, simulated Visa for the demo) bound the worst case.

## Follow-ups
- Commerce: `listing.ts` uses `posting`, and iOS adds `ListingStatus.posting` ("Posting...") in one PR. Today iOS drops listings with an unknown status, so ship the Swift case first or together with the worker change.
