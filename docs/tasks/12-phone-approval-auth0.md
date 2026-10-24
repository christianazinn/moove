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
- On approval, set `approvals.status=approved` and let #11 publish. On denial, set the listing status to `rejected` (`update_listing`) and log it.
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

## Status (as built)
- **Worker:** `agents/src/agents/approval.ts` + `agents/src/integrations/auth0.ts` (real CIBA via plain `fetch`, plus an opt-in, labeled simulated approver). See `agents/CLAUDE.md`. Without Auth0 config the worker leaves approvals pending for the in-app inbox; it never approves on its own.
- **Binding message:** Auth0 allows max 64 chars of letters, digits, spaces and `+-_.,:#`, so the example above is invalid. We send e.g. `Moove: sell 420.00 USD: Herman Miller chair` or `Moove: buy 179.99 USD: 8in memory foam mattress` (amount first, title from the listing or deal row).
- **iOS:** `ios/Moove/Features/Approvals/` (Approvals tab with pending badge, approve/deny with confirm, history) + MooveKit `Approval` model, `SyncSnapshot.approvals`, fixtures, tests. Works in fixture mode; the live `decideApproval` is a stub like every other reducer in `SpacetimeBackend+Contract.swift` until the Swift bindings are generated.
- **Tested** (scratch harness on a fake connection): below threshold posts directly; above threshold without Auth0 never posts; CIBA denied -> listing `rejected`; CIBA approved -> posted; push expiry or in-app decision mid-poll -> the worker does not decide.
- **Not yet tested against a real tenant** (no Auth0 credentials yet). CIBA may be plan-gated (Enterprise or add-on).

## Turning on real phone push (human, in order)
1. Use the same Auth0 tenant as the iOS login (#1), so the app's users exist there.
2. Applications > Create > Regular Web Application `moove-worker`. Advanced Settings > Grant Types: enable **Client Initiated Backchannel Authentication (CIBA)**. If it isn't offered, the plan doesn't include CIBA: ask the Auth0/MLH table, or demo with the in-app inbox.
3. In that app's CIBA settings, enable the **Guardian push** notification channel.
4. Security > Multi-factor Auth: enable **Push Notification using Auth0 Guardian** (push app = Auth0 Guardian). Leave the MFA policy at Never so login isn't affected.
5. Install **Auth0 Guardian** on the demo phone and enroll the demo user (Management API `POST /api/v2/guardian/enrollments/ticket` with the user id, open `ticket_url`, scan the QR).
6. Make sure that user's `user.auth0_sub` in SpacetimeDB is their Auth0 user id (e.g. `auth0|abc...`).
7. Worker `.env.local`: `AUTH0_DOMAIN`, `AUTH0_CIBA_CLIENT_ID`, `AUTH0_CIBA_CLIENT_SECRET` (optionally `AUTH0_AUDIENCE`). Restart the worker; it logs `[approval] <mode>`.
8. Demo: one over-threshold listing at a time (Auth0 allows 5 CIBA requests per user per minute), and approve within 5 minutes.
