---
title: Fraud screening
lane: backend
depends: 15, 6
tracks: Visa, CRS Credit, Anthropic
stretch: true
---

## Goal
Every deal the buy agent finds is screened for fraud, and risky ones are flagged with reasons before the user ever pays.

## Context
An agent in the worker (`agents/`) that subscribes to new `deals` rows and writes `fraudScore` plus `fraudReasons`. The iOS shopping UI (#15) shows the flags. See `docs/data-model.md`.

## Scope
- `agents/src/agents/fraud.ts` signals:
  - Price far below the comps (from #6): too good to be true.
  - New or empty seller account (if the scraper exposes it).
  - Text asking to pay off-platform (Zelle, gift cards, wire).
  - Reused photos (perceptual hash against other listings or a reverse-image check if feasible).
- Combine rules with a Claude judgment and a short explanation.
- Optional: the CRS Credit sandbox identity check for sellers (test identities only) for the CRS Identity/Fraud prize.

## Tables / reducers touched
`deals` (fraudScore, fraudReasons), `agentEvents`.

## Acceptance criteria
- [ ] Planted scam listings in fixtures are flagged, with the correct reasons.
- [ ] Legit fixture deals are not flagged (low false-positive rate on the test set).
- [ ] Flags are visible in the shopping UI.

## Demo fallback
The planted-scam fixture set with an answer key, showing the screener catching them.

## Notes & gotchas
- Build a small labeled test set (planted errors with an answer key). Judges love proof that it works.
- CRS sandbox: https://calhacks.crscreditapi.com (use only the provided test identities). Verify the API against their docs.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
