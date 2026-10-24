---
title: Automatic sorting
lane: backend
depends: 6
tracks: Anthropic, Planet-First
stretch: false
---

## Goal
Every item is auto-sorted into keep, sell, donate or trash, with a one-line reason. Possibly sentimental items are left for the user to decide.

## Context
An agent in the worker (`agents/`). It subscribes to priced items and writes `items.disposition` with `dispositionSource=auto`. The review screen (#9) lets the user override. See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `agents/src/agents/sort.ts`: rules first (e.g. value < cost to move -> sell or donate; condition 1 -> trash), then a Claude call for ambiguous cases. Inputs: value, condition, size or volume, an estimated per-item moving cost, and fragility.
- Write disposition plus a reason. Never overwrite `dispositionSource=user`.
- Items with `maybeSentimental=true` -> `disposition=undecided` plus a flag, so they are never auto-decided.
- Write an `agentEvents` row per decision batch.

## Tables / reducers touched
`items` (disposition, dispositionSource, dispositionReason), `agentEvents`.

## Acceptance criteria
- [ ] All fixture items get a disposition and reason.
- [ ] Sentimental items stay undecided.
- [ ] User overrides are never clobbered by a re-run.
- [ ] Donate is preferred over trash for usable items (the Planet-First angle).

## Demo fallback
Rules-only mode (no LLM) behind an env flag.

## Notes & gotchas
- `claude-haiku-5-5` for classification (env-overridable).
- The moving-cost estimate can reuse the volume logic from #19 or a simple per-cubic-meter constant.
- Expose the reasoning in the UI. This is the "Claude does something that matters" story for the Anthropic track.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
