# Security pass: connection gate, approval separation of duties, reducer hardening
Status: accepted (#41 part A, #42, #44). #41 part B (private tables + per-user views) is deferred.

Context: the security pass (#17) found that any token could connect, that the worker could approve its
own approval requests, that `register_user` trusted client-supplied Auth0 subjects (which CIBA pushes
target), that the worker role went to whoever called `register_worker` first, that owners could fake
listing outcomes, and that the vision agent fetched any client-supplied photo URL (SSRF). Proposals:
[#41](https://github.com/christianazinn/moove/issues/41), [#42](https://github.com/christianazinn/moove/issues/42),
[#44](https://github.com/christianazinn/moove/issues/44).

Decision (all in `spacetime/src/index.ts` unless noted):
- **Connection gate (#41 A):** `client_connected` accepts only Auth0 ID tokens from our tenant whose `aud`
  includes the iOS native client id, plus the worker. Behind `REQUIRE_AUTH0`, which ships `false` until the
  app no longer falls back to anonymous tokens. Flipping it back to `false` is the stage escape hatch.
- **Join codes (#41, instead of part B for now):** owner-only `rotate_join_code(room_id)` and
  `remove_member(room_id, member)`.
- **Approvals (#42):** `decide_approval` keeps its signature but is owner-only and takes only
  `approved|denied` (`decided_via = 'app'`). The worker records CIBA results with the new worker-only
  `record_ciba_decision(approval_id, status, ciba_subject)`, which requires `ciba_subject` to equal the
  owner's `user.auth0_sub` (`decided_via = 'ciba'`). `request_approval` checks that the listing/deal belongs
  to `owner` and that the amount equals its price. New `approval` columns `decided_via` and `ciba_subject`
  are appended with defaults, so existing rows migrate without `--delete-data`.
- **`register_user` (#44):** `auth0_sub` and `email` come from the verified Auth0 token (`ctx.senderAuth.jwt`
  with our issuer). The `auth0_sub` arg is ignored but kept for binding compatibility.
- **Worker pinning (#44):** when `ctx.databaseIdentity` is the maincloud database, only the pinned worker
  identity can register or pass `requireWorker`. Every other database keeps first-caller-wins so
  teammates can run local workers.
- **`update_listing` (#44):** worker-only. Owners never set listing state.
- **`set_approval_threshold` (#44):** `-1` or `0..10,000,000` cents.
- **SSRF (#44, `agents/src/integrations/photos.ts`):** `loadImage` never fetches arbitrary URLs. Our own
  uploads (`PUBLIC_UPLOAD_BASE_URL/files/<uuid>.<ext>`) are read from `UPLOAD_DIR` on disk with a strict
  name check. Anything else must be https, on a host in `ALLOWED_PHOTO_HOSTS` (default empty), resolve only
  to public addresses, and not redirect. The module also refuses non-http(s) photo URLs.

Consequences:
- The opt-in simulated auto-approver (`APPROVAL_SIM_AUTO_APPROVE_SEC`) is gone: the worker can no longer
  approve on its own. Without Auth0 CIBA, approvals wait for the in-app inbox.
- CIBA results are relayed by the worker and not verified in-module (reducers can't fetch JWKS); the
  subject pin plus `decided_via` make the path auditable.
- Photos from any host other than our upload server need `ALLOWED_PHOTO_HOSTS`. If the phone uploads
  through a different base URL than the worker's `PUBLIC_UPLOAD_BASE_URL`, vision says why it skipped the photo.
- Maincloud needs a republish by Christian (no `--delete-data` needed; verified locally against the old schema).
  Rotating the maincloud worker identity means editing `MAINCLOUD_WORKER_IDENTITIES` and republishing.
- iOS: no signature changes. `register_user`'s `auth0Sub` arg is ignored. The app can show `decided_via`.
