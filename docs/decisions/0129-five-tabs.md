# 0129: Five tabs that follow the move

**Status:** accepted (lazy consensus on #129, Sat Oct 24 3:04 AM PDT; commerce agreed). Now four tabs: Summary was removed (addendum below).

## Context
The app had 10 tabs. iOS shows 4 plus "More", so half the demo script hid behind More. Lisa flagged it as too many tabs.

## Decision
| Tab | Screens (segmented picker, first is the default) |
|---|---|
| Scan | Scan home |
| Items | Inventory · Review |
| Sell & Buy | Listings · Shopping · Approvals · Spending |
| Move | New Home · Pack |
| Summary | Summary |

- `Moove/App/TabGroups.swift` holds the groups. Feature screens are unchanged.
- `@AppStorage("moove.tab")` stores the screen key, so `tab = "approvals"` (or "inventory" etc.) from anywhere opens the right tab and segment.
- The Sell & Buy tab badge and the Approvals pill show the pending approvals count (commerce's condition).
- Default Sell & Buy segment: Listings (the demo reaches it before Shopping).

## Addendum: Sell & Buy has three segments (Oct 24)
Lisa: "the main issue we want to fix is simplifying the app because it seems like there are a lot of tabs and subtabs. can you merge approvals and spending together into sell & buy because they both have to do with agents behavior?"

- Sell & Buy is now **Listings · Shopping · Agents**. **Agents** (`Features/Agents/AgentsView.swift`) is one screen: a small Waiting / Decided / Payments strip, then **Needs your OK** (the pending approval cards with Approve / Deny, or one "Nothing waiting" line), **Shared rooms** when there are any, **Decided** (the last 3 decisions, "Show all N" for the rest), then the spending **Receipts** with the totals tape (#316). Follow-up (Lisa: "for the spending logs in the receipt could it not be just scrolling through it, maybe you can scroll through multiple receipts"): the receipts are a sideways paged carousel, one receipt per page.
- The Sell & Buy tab badge and the **"Agents · N"** pill count pending approvals (own + shared room), as the Approvals pill did.
- The screen keys "approvals" and "spending" still work: `TabGroup.segment(for:)` maps both to "agents", so `tab = "approvals"` lands on Agents at the top and `tab = "spending"` scrolls to the receipts. The key then becomes "agents".
- All element identifiers are unchanged (`approval.pending.<id>`, `approval.approve.<id>`, `approval.decided.<id>`, `payment.<id>`, `payment.basescan.<id>`, `receipt.<id>`); new ones: `spending.totals`, `approvals.nothingWaiting`, `approvals.decided.showAll`.

## Addendum: Summary removed, four tabs (Oct 24)
Lisa: "can we remove the summary page entirely but keep the however many kg saved (sustainability thing) in the inventory/review tab or wherever you see fit".

- The app has **four tabs**: **Scan · Items · Sell & Buy · Move**. `TabGroup.summary` and `Features/Summary/` are gone; the MooveKit math (`MoveSummary`, `SafetySummary`) stays and is still tested.
- **Kg kept from landfill** moved to a banner at the top of **Items > Review** (`review.impact`): "~49 kg kept out of landfill" and "4 items sold or donated" on the Offline demo, from `MoveSummary` over the visible items, so it updates as you decide. Tap it for how it's estimated and the Sell / Donate breakdown.
- **"Agents kept you safe"** (#225, #229) moved to **Sell & Buy > Agents** (`agents.safety`), between "Needs your OK" and "Decided". Same lines, same Simulated / Sim tags.
- Money (sold, spent, net) already lives on the Agents receipts tape, so it isn't repeated. The agent timeline is gone.
- The old screen key "summary" maps to "review" (`TabGroup.segment(for:)`), so a stored `moove.tab = "summary"` or `tab = "summary"` lands on Review.
- Devpost shots: `08-summary` is replaced by `08-agents-safety` and `08b-review-impact`.
