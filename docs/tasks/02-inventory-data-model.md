---
title: Inventory data model (SpacetimeDB)
lane: backend
depends: none
tracks: Spacetime
stretch: false
---

## Goal
A published SpacetimeDB module whose tables and reducers every feature reads and writes. This is the single contract between all four lanes.

## Context
**Critical path.** The draft schema is in `docs/data-model.md`. Ship it within the first ~3 hours. The SpacetimeDB TypeScript module lives in `spacetime/`. The agent worker (`agents/`) consumes generated TS bindings, and the iOS app mirrors the models in `ios/MooveKit`. Reducers stay pure (no outbound I/O); all external calls happen in the worker. See `docs/architecture.md`.

## Scope
- `spacetime/`: init the TS module, define all tables from `docs/data-model.md`, and write reducers for every write path (insert/update item, set disposition, add comp, create listing, record payment, log agent event, etc.).
- Publish to maincloud (plus a local `spacetime start` for development).
- Run `spacetime generate --lang typescript` into `agents/src/module_bindings/`.
- Mirror the table structs as Swift `Codable` models in `ios/MooveKit/Sources/MooveKit/Models/`.
- Seed reducer or script: load the fixture room and items so other lanes have data before #3 and #4 land.
- Update `docs/data-model.md` to match exactly what shipped.

## Tables / reducers touched
All of them: `users`, `rooms`, `scans`, `items`, `comps`, `listings`, `approvals`, `shoppingList`, `deals`, `payments`, `newHome`, `layouts`, `agentEvents`.

## Acceptance criteria
- [ ] `spacetime publish` succeeds locally and on maincloud.
- [ ] TS bindings are generated and committed, and `agents/` typechecks against them.
- [ ] MooveKit models compile (`swift test` passes on Linux CI).
- [ ] Seed data is visible via `spacetime sql` (fixture room with at least 10 items).
- [ ] Reducers check ownership (`ctx.sender` must own the row) except for the worker identity.

## Demo fallback
None needed. Everything depends on this, so keep it simple and ship it.

## Notes & gotchas
- **Contract changes after the first ship go in their own small PR**: regenerate the bindings, update MooveKit, update `docs/data-model.md`, and announce it to the team.
- Item fields: name, category, dims (w/h/d in meters), photoUrls, material, brand, condition, estValue, disposition (keep/sell/donate/trash/undecided), dispositionSource (auto/user), fragile, maybeSentimental, roomId, scanObjectId.
- `payments` must have a `simulated` flag (a Coinbase rule). `agentEvents` gets a row for every agent step (agent, step, input summary, output summary, cost, timestamp).
- The worker needs a privileged identity for reducers. Decide how it authenticates (a dedicated token) and document it.
- TypeScript module syntax and `spacetime generate` flags: verify against current docs.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
