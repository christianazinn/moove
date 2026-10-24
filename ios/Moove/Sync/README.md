# Sync

Screens only talk to `MooveStore`. It drives one `SyncBackend` (from MooveKit):

- `SpacetimeBackend`: the live backend, built on the community SDK
  [`ekscrypto/spacetimedb-swift-sdk`](https://github.com/ekscrypto/spacetimedb-swift-sdk),
  pinned in `project.yml`. Contract-specific glue lives in `SpacetimeBackend+Contract.swift`.
- `FixtureBackend` (MooveKit): in-memory, the same reducer rules, for previews, tests and the
  **Offline demo** toggle in Settings.

## Regenerating `Generated/`
The bindings are generated from the published module's schema with the SDK's `spacetime-swift` tool:

```sh
git clone https://github.com/ekscrypto/spacetimedb-swift-sdk /tmp/stdb-swift
cd /tmp/stdb-swift && git checkout <revision from project.yml> && swift build -c release --product spacetime-swift
# --out must be an absolute path that does NOT start with /private (the tool
# rejects symlink-resolved paths, so use /tmp/..., not /private/tmp/...)
/tmp/stdb-swift/.build/release/spacetime-swift generate \
  --uri http://127.0.0.1:3000 --db moove --out "$PWD/ios/Moove/Sync/Generated"
```

Never hand-edit `Generated/`. After regenerating, update `SpacetimeBackend+Contract.swift`.

## Notes from the hour-0 spike (SDK 2026-09-27 `c966b6b`, SpacetimeDB 2.13)
- Connect, subscribe, reducer calls, ownership rejection and reconnect all work.
  A->B live update latency on localhost was ~1.5 ms.
- TS modules expose snake_case names: reducer `setDisposition` is called as `set_disposition`,
  and column `widthM` is `width_m`. The codegen handles this.
- Initial subscription rows arrive as `.inserted` row events, so register `rowEvents` **before** `subscribe`.
- The SDK auto-reconnects but does **not** replay subscriptions; `SpacetimeBackend` resubscribes on reconnect.
- Generated reducer initializers lowercase multi-word args (`itemid:`), and a reducer argument named
  `name` becomes `nameArg:`.
