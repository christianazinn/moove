# 0129: Five tabs that follow the move

**Status:** accepted (lazy consensus on #129, Sat Oct 24 3:04 AM PDT; commerce agreed)

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
