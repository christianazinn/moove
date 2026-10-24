---
title: Login (Auth0)
lane: ios-capture
depends: none
tracks: Auth0 (MLH), Spacetime
stretch: false
---

## Goal
The user signs in with Auth0 on launch. Every row they create in SpacetimeDB is tied to that identity, so everything else in the app is per-user.

## Context
iOS SwiftUI app (`ios/`) talking to the SpacetimeDB TS module (`spacetime/`, the contract). The Auth0 ID token (an OIDC JWT) is passed as the SpacetimeDB connection token, so the module's `ctx.sender` identity maps to the Auth0 user. The agent worker (`agents/`) also reuses this Auth0 tenant for #12 (phone approvals). See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- Create the Auth0 tenant and a Native application, with callback URLs for the iOS bundle id. Add a social login (Google or Apple) plus passwordless if it's quick.
- `ios/Moove/Features/Auth/`: login screen, session storage in the Keychain, logout, and token refresh.
- Connect to SpacetimeDB with the ID token. On first login, call a `registerUser` reducer that creates the `users` row.
- Add the Auth0 domain, client id and audience to `.env.example` and the iOS config (never commit secrets).

## Tables / reducers touched
- `users` (insert on first login), via the `registerUser` reducer. Coordinate with #2.

## Acceptance criteria
- [ ] Fresh install -> Auth0 login -> lands on the home/scan screen.
- [ ] Relaunching skips login (the session persists). Logout returns to the login screen.
- [ ] A `users` row exists for the Auth0 subject, and a second device logged in as the same user resolves to the same identity.
- [ ] No Auth0 secrets in the repo (a native app needs only the domain and client id).

## Demo fallback
A pre-logged-in demo account on the demo phone. If the OIDC-to-SpacetimeDB handoff fails, connect with a SpacetimeDB anonymous identity, store the Auth0 `sub` on the `users` row, and say so in the README.

## Notes & gotchas
- Auth0.swift SDK (Web Auth with a universal login page). Verify setup steps against current docs.
- SpacetimeDB accepts OIDC JWTs from external issuers. Verify how the issuer and audience are configured on maincloud against current docs.
- The Swift SpacetimeDB client is community-built (`ekscrypto/spacetimedb-swift-sdk`) and is the top technical risk. If the hour-0 spike fails, the iOS app talks to the agent worker gateway instead (see #10), and the worker forwards the Auth0 token.
- MLH Auth0 prize: any Auth0 API counts, and #12 adds "Auth0 for AI Agents".

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
