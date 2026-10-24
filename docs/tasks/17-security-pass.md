---
title: Security pass
lane: commerce
depends: none
tracks: Armadin Security, Visa, Coinbase x402
stretch: false
---

## Goal
User data is protected, and no API keys or passwords are ever in the repo. Judges can see we took security seriously.

## Context
Cross-cutting. It touches the worker (`agents/`), the SpacetimeDB module (`spacetime/`) and the iOS app. Start early (secrets hygiene) and finish late (review). See `docs/architecture.md`.

## Scope
- Secrets: `.env.example` is complete, gitleaks passes in CI, secrets live only in env vars, and the iOS app has no embedded server secrets.
- SpacetimeDB: every reducer checks `ctx.sender` ownership or room membership, and the worker identity is scoped.
- Uploads: auth on the upload endpoint, unguessable file names, and no directory listing.
- Agent guardrails: spend caps (#7), approval thresholds (#12), and prompt-injection hygiene when listing text from scraped pages reaches an LLM (treat scraped content as data).
- Encrypt sensitive fields at rest if anything sensitive is stored (e.g. addresses).
- Write the section in the README and `docs/tracks.md` on security and responsible-AI choices.

## Tables / reducers touched
Reviews all reducers. No new tables expected.

## Acceptance criteria
- [ ] `gitleaks detect` is clean on the full history.
- [ ] Calling another user's reducer is rejected (a manual test is documented).
- [ ] An injection string planted in a scraped listing doesn't change agent behavior (spot check).
- [ ] The security notes are written up for judges.

## Demo fallback
Not applicable.

## Notes & gotchas
- Cartesia and other tracks explicitly say there must be no keys in the repo. Rotate any key that is ever committed.
- Armadin's Best Security Hack criteria are "coming soon". Check the live site.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
