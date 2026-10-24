# 0200: Room members may decide listing approvals for shared items (#195)

**Status:** accepted (lazy consensus on #200, Sat Oct 24 4:10 AM PDT; no objections from backend or iOS Sync). Not implemented yet: the backend lane (Christian's agent) implements and republishes. Interim read-only app support shipped in #208.

## Context
On the Demo backend, judges join the seeded Bedroom (`4RZ9G8`). The seed user owns every item, listing and approval, and `decide_approval` is owner-only. So a joined phone can't approve the over-$100 chair (#194). SpacetimeDB 2.13 subscriptions join at most two tables, so the app can't subscribe to "listings for items in my shared rooms" (listing → item → room_member) in one query.

## Decision
- `decide_approval` allows `ctx.sender == owner`, **or** `kind == 'listing'` when the sender is a `room_member` of the room that holds the listing's item.
- **Purchase approvals stay owner-only**, because they spend the owner's budget and deals aren't room-scoped.
- `approval` gets `decidedBy`, appended last with a default. `decide_approval` sets it to the sender. `record_ciba_decision` sets it to the owner.
- Per-user views `my_listing` (own listings + listings for items in joined rooms) and `my_approval` (own approvals + listing approvals for those listings) replace the app's interim "all listings + other users' listing approvals, filtered client-side" subscriptions from #208.
- Nice to have: a way to read co-members' display names for "Waiting for <name>".

## Consequences
- Room members are trusted co-movers, and they can already re-disposition shared items. A member's approval posts the listing right away, so the owner can't take it back. `decidedBy` keeps an audit trail. On Demo, posting is SIMULATED.
- After republish, the app shows Approve/Deny on shared listing approvals (commerce lane follow-up) and swaps to the views.
- The `decidedBy` append has to be sequenced with any #186 approval-expiry column change.
