---
title: Photo -> item details (vision)
lane: backend
depends: 2
tracks: Anthropic
stretch: false
---

## Goal
Each item gets its real type, material, brand and condition from its photo, because LiDAR can't tell a leather chair from a cheap one. Pricing depends on this.

## Context
Runs in the agent worker (`agents/`), which subscribes to `items` that have photos but no vision details. It calls Claude vision and writes results back through a reducer. See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `agents/src/agents/vision.ts`: subscribe to items needing details, call Claude with the photo plus the RoomPlan category and dims, and get structured output (name, category, material, brand, condition 1-5, fragile, maybeSentimental, confidence).
- `agents/src/integrations/anthropic.ts`: a shared client wrapper with model names from env.
- Call the `updateItemDetails` reducer, and write an `agentEvents` row per call.

## Tables / reducers touched
`items` (details fields), `agentEvents`.

## Acceptance criteria
- [ ] New items with photos get details within ~10s.
- [ ] Output is schema-validated (zod), and failures are retried once, then marked as needing review.
- [ ] `maybeSentimental` is set for things like photos, keepsakes and handmade or old personal items.
- [ ] Runs over the #3 fixture photos with sensible results.

## Demo fallback
Cached vision results for the fixture items in `agents/fixtures/demo-room/vision.json`, used when the API fails (labeled as cached).

## Notes & gotchas
- Models: `claude-sonnet-5-5` for vision (env `MOOVE_VISION_MODEL`). Use tool use or structured output for JSON. Verify against current Anthropic docs.
- Send images as base64 or by URL. The worker can read local upload files directly.
- Keep the prompt honest about uncertainty (brand "unknown" beats a hallucinated brand), since the Anthropic track judges care about where Claude can go wrong.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
