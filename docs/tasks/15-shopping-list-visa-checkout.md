---
title: Still-need-to-buy list + checkout (Visa)
lane: commerce
depends: 13, 8
tracks: Visa, Coinbase x402, Apify, Anthropic
stretch: false
---

## Goal
Moove works out what the user still needs for the new home, a buy agent finds good deals, and the user checks out through Visa.

## Context
Needs the floor plan (#13) and the keep items (#8). The buy agent lives in the worker (`agents/`), and the list and checkout UI is in iOS. Checkout uses the Visa tooling from the Visa Starter Pack (posted on the Cal Hacks live site). Until that's available, it's stubbed behind `agents/src/integrations/visa.ts`. See `docs/architecture.md`.

## Scope
- Generate the shopping list with Claude from the new-home rooms minus kept items (e.g. no bed for bedroom 2), plus an "ask the user" chat or edit step. Write `shoppingList` rows.
- `agents/src/agents/buy.ts`: for each list item, search deals via Apify (shared with #6), rank them by price, condition and distance, and write `deals` rows (fraudScore is filled in by #18).
- `agents/src/integrations/visa.ts`: a checkout interface (`createCheckout`, `confirm`) with a Visa sandbox implementation once the starter pack is known.
- iOS `ios/Moove/Features/Shopping/`: list, deals per item, approve purchase (large ones go through the #12 approval), then checkout.
- Record a `payments` row (rail=visa, simulated flag).

## Tables / reducers touched
`shoppingList`, `deals`, `payments`, `approvals`, `agentEvents`.

## Acceptance criteria
- [ ] Shopping list generated for the demo house.
- [ ] At least 3 real deals per item from live listings.
- [ ] One end-to-end checkout through the Visa sandbox (or a clearly labeled simulation).
- [ ] Purchased items appear in the #14 layout.

## Demo fallback
Cached deals plus a simulated checkout, labeled "simulated".

## Notes & gotchas
- Visa track criteria include Trust & Responsibility (15%). Show the agent's reasoning, the approvals and the fraud flags.
- Paying a FB or Craigslist seller isn't possible via an API. Frame external deals as "agent found it and drafted the message to the seller", and use Visa checkout where the merchant supports it.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
