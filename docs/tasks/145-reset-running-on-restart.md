---
title: Reset vision, sam3d and sweep rows left running by a worker restart
lane: backend
depends:
tracks: Spacetime
stretch: false
---

## Goal
A worker restart never leaves an item's vision (`details_status`), SAM 3D (`model_status`) or a scan's room sweep (`sweep_status`) stuck at `running`. Same bug #138 fixed for pricing.

## Context
Each of these agents sets the row to `running` before its work (`vision.ts` `setItemStage(..., 'running', 'details')`, `sam3d.ts` `setItemStage(..., 'running', 'model')`, `sweep.ts` `setSweepStatus(..., 'running')`) and to `done`/`failed` after. If the worker dies in between (supervisor restart via `scripts/run-worker.sh`, a maincloud republish disconnect, a redeploy), the row stays `running` forever: every agent only picks up `pending` rows, so nothing re-queues it. The app shows a spinner that never ends, and downstream agents wait (pricing and sort wait for vision done/failed, sam3d waits for vision).

#138 fixed this for pricing: `agents/src/agents/pricing.ts` `start()` puts every `pricing_status = running` item that isn't in flight back to `pending` before subscribing. Only one worker runs against a DB, so anything `running` at start belongs to a dead worker.

## Scope
- `agents/src/agents/vision.ts` `start()`: reset `details_status = running` to `pending` (field `details`).
- `agents/src/agents/sam3d.ts` `start()`: reset `model_status = running` to `pending` (field `model`). A reset item may pay fal again; `SAM3D_MAX_USD` covers that.
- `agents/src/agents/sweep.ts` `start()`: reset `sweep_status = running` to `pending` via `set_sweep_status`, then let the normal settle timer schedule it.
- A short comment in each, like pricing's, and a test per agent against a fake connection (see `agents/test/x402-hardening.test.ts`, "an item left pricing_status=running by a worker restart is priced again").
- If a reducer refuses `running -> pending` for one of these fields, that's a contract change: its own small PR.

## Tables / reducers touched
`item` (`details_status`, `model_status`), `scan` (`sweep_status`); `set_item_stage`, `set_sweep_status`. No new reducers expected.

## Acceptance criteria
- [ ] With a row left `running` (details, model or sweep) and no work in flight, starting the worker re-runs it once and it ends `done`/`failed`.
- [ ] Rows that are `pending`, `done` or `failed` are untouched.
- [ ] One test per agent; `cd agents && npm run typecheck && npm test` pass.
- [ ] `agents/CLAUDE.md` mentions the reset for each agent.

## Demo fallback
None needed: today the workaround is re-adding a photo (vision/sam3d) or rescanning (sweep). A reset re-run of vision or the sweep replays from `fixtures/llm` when `LLM_REPLAY` is on; live it costs one Claude call, and sam3d one fal run (~$0.02), within the existing caps.

## Depends on
Nothing. Related: #138 (pricing fix).
