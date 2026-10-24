---
title: Summary screen
lane: ios-newhome
depends: 8, 11, 15
tracks: Planet-First
stretch: false
---

## Goal
One screen that tells the story of the move: what was kept, sold, donated and trashed, money earned and spent, agent activity, and the impact.

## Context
iOS (`ios/Moove/Features/Summary/`), read-only over many tables. This is the closing slide of the demo. See `docs/data-model.md`.

## Scope
- Totals: number of items per disposition, expected or actual sales (listings), spend (payments, split by rail), and net.
- Agent activity: counts and a short timeline from `agentEvents`.
- Impact: items diverted from landfill (sold plus donated), with a rough kg estimate.
- A share or export image (nice to have).

## Tables / reducers touched
`items`, `listings`, `payments`, `agentEvents`, `shoppingList` (all read).

## Acceptance criteria
- [ ] Numbers match the underlying tables for the fixture data.
- [ ] Updates live as agents work.
- [ ] Looks good enough to end the demo on.

## Demo fallback
Fixture-backed numbers.

## Notes & gotchas
- Label simulated payments separately from real testnet ones.
- The landfill-diversion stat supports the Best Planet-First Hack general prize.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
