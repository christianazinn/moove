---
title: Real eBay sandbox posting
lane: commerce
depends: 11
tracks: Anthropic, Apify
stretch: false
---

## Goal
Listings post to the real eBay **sandbox** instead of the simulation whenever the team has eBay keys, without changing the listing agent's flow.

## Scope
- `agents/src/integrations/ebay.ts`: `sandboxEbay` behind the existing `EbayPoster` interface (inventory item -> offer -> publish), chosen by `chooseEbay()` when every `EBAY_*` key is set. The simulation stays the default.
- `agents/scripts/ebay-setup.ts`: consent URL, code -> refresh token, business-policy opt-in, 3 policies + location, and a `check` command.

## Human setup (in order)
1. Join the eBay Developers Program (approval can take ~1 business day). Create a **Sandbox** keyset: App ID -> `EBAY_CLIENT_ID`, Cert ID -> `EBAY_CLIENT_SECRET`.
2. Create a sandbox test seller (Develop -> Tools -> eBay Sandbox -> test users).
3. User Tokens page -> add a sandbox RuName (any https Accept URL) -> `EBAY_RUNAME`.
4. In `agents/`: `npm run ebay:setup -- consent`, sign in as the test seller, then `npm run ebay:setup -- token "<redirect URL>"` within 5 minutes -> `EBAY_REFRESH_TOKEN`.
5. `npm run ebay:setup -- provision` -> policy ids + `EBAY_LOCATION_KEY`. Then `npm run ebay:setup -- check`.
6. Make photos public https: run the worker behind a tunnel (`cloudflared tunnel --url http://localhost:8787`) and set `PUBLIC_UPLOAD_BASE_URL` to it, or set `EBAY_FALLBACK_IMAGE_URL`.

## Acceptance criteria
- [ ] With keys set, a sell item is published in the eBay sandbox and its `listing.url` opens `https://sandbox.ebay.com/itm/<id>`, with `simulated=false`.
- [ ] Without keys, behavior is exactly the #11 simulation.
- [ ] eBay errors mark the listing `failed` with the eBay error ids in an `agentEvents` row (no silent fallback to a fake post).

## Notes & gotchas
- Business-policy opt-in is API-only in sandbox and can lag; rerun `provision` if policy creation fails.
- Used conditions collapse to `USED_EXCELLENT` ("Used"), the value most home/furniture leaves accept; the grade is in the description.
- Sandbox is flaky. Keep the simulation as the demo fallback.
