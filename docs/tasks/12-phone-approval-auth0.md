---
title: Phone approval for expensive listings (Auth0)
lane: commerce
depends: 1, 11
tracks: Auth0 (MLH), Visa, Coinbase x402
stretch: false
---

## Goal
Before an agent posts a high-value listing (or makes a large purchase), the user gets a push on their phone to approve or deny it, and the agent waits.

## Context
Sits in front of #11's eBay posting (and optionally #15's checkout). Uses Auth0 for AI Agents async authorization (CIBA), so the agent gets a scoped approval rather than blanket access. See `docs/architecture.md`.

## Scope
- `agents/src/integrations/auth0.ts`: start a CIBA / async authorization request for the user with a binding message ("Post 'Herman Miller chair' for $420?"), then poll or wait for the result.
- On approval, set `approvals.status=approved` and let #11 publish. On denial, mark the listing as rejected and log it.
- Threshold config (env and per-user setting).
- iOS: an in-app approvals inbox as a backup to the push (Guardian or Auth0 push), subscribed to `approvals`.

## Tables / reducers touched
`approvals`, `listings` (status), `agentEvents`.

## Acceptance criteria
- [ ] An expensive listing triggers an approval prompt on the phone.
- [ ] Approve -> the listing posts. Deny -> it doesn't, and the reason is logged.
- [ ] The agent never posts above the threshold without approval (tested).

## Demo fallback
An in-app approve/deny button driven by the `approvals` table (still a real gate, just not Auth0 push).

## Notes & gotchas
- Auth0 for AI Agents: async authorization via CIBA with Guardian push. It requires tenant features to be enabled. Verify against current Auth0 docs early, because the tenant setup may take time.
- Segregation of duties (the agent requests, the human approves) is a strong trust point for the Visa and Coinbase judges.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
