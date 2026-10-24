# 0254: Room members see x402 comps payments and agent steps for shared items (#254)

**Status:** accepted (lazy consensus on #254, Sat Oct 24 5:40 AM PDT; no objections from backend or iOS Sync). The views are the backend lane's change (Christian's agent implements and republishes, as with #239). App support shipped in #256. It works before and after the republish.

## Context
On the Demo backend, judges join the seeded Bedroom (`4RZ9G8`). The seed user owns the pricing agent's 10 simulated x402 comps payments (`ref_table = 'item'`) and the agent steps on its items. The app read `payment` / `agent_event WHERE owner = me`, so a joined phone's Spending said "No payments yet" and Summary's "Agents kept you safe" had no x402 line. That hid the Coinbase-track evidence from judges. Subscriptions join at most two tables, so `payment → item → room_member` can't be one subscription (same as #195 / 0200).

## Decision
- Per-user views **`my_payment`** (own payments, plus `refTable = 'item'` payments for items in rooms the sender owns or joined) and **`my_agent_event`** (own events, plus `refTable = 'item'` events for those items and `refTable = 'listing'` events for listings in `my_listing`). Read-only: no reducers or table changes. They reuse the base row types.
- **Purchase payments stay owner-only** (Visa and buy payments reference `deal` / `shopping_item`, which belong to the owner's shopping list). So do buy, fraud and approval-decision events. This mirrors 0200: members are trusted co-movers for the room's items, and anything tied to the owner's own budget or shopping list stays with the owner.
- The app subscribes to the views in a **separate, optional subscription** next to the owner-only ones and merges rows by id. If a module doesn't have the views, only that subscription is rejected.
- The user's own totals never include room rows. MooveKit `SpendingSplit { yours, room }`: Spending shows a "Shared room" section with its own totals and tagged rows. The safety card has a separate "Shared room: agents paid … over x402" line. The move summary's spend is the user's own; its timeline includes the room's agent steps.

## Consequences
- After the republish, a judge who joins `4RZ9G8` on Demo sees ten $0.01 SIMULATED x402 comps payments under Spending → Shared room, and the room x402 line on Summary.
- A member can see what the agents paid to price shared items. That's a few cents per item to a public data endpoint, about items they can already see. No card or account data is exposed.
- Budgets stay per owner. The app computes the user's budgets from their own x402 events only.
