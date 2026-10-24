# Sync

Screens only talk to `MooveStore`. It drives one `SyncBackend` (from MooveKit):

- `SpacetimeBackend`: the live backend, built on the community SDK
  [`ekscrypto/spacetimedb-swift-sdk`](https://github.com/ekscrypto/spacetimedb-swift-sdk),
  pinned in `project.yml`. Contract-specific glue lives in `SpacetimeBackend+Contract.swift`.
- `FixtureBackend` (MooveKit): in-memory, the same reducer rules, for previews, tests and the
  **Offline demo** toggle in Settings.

## Regenerating the bindings (`ios/MooveBindings`)
The bindings are generated from the published module's schema with the SDK's `spacetime-swift` tool:

```sh
git clone https://github.com/ekscrypto/spacetimedb-swift-sdk /tmp/stdb-swift
cd /tmp/stdb-swift && git checkout <revision from project.yml> && swift build -c release --product spacetime-swift
# --out must be an absolute path that does NOT start with /private (the tool
# rejects symlink-resolved paths, so use /tmp/..., not /private/tmp/...)
/tmp/stdb-swift/.build/release/spacetime-swift generate \
  --uri https://maincloud.spacetimedb.com --db moove --out "$PWD/ios/MooveBindings/Sources/MooveBindings"
```

Run it from the repo root. Never hand-edit the generated files. They live in their own package so names like `ListingRow` can't clash with app views; refer to them as `MooveBindings.ListingRow`. `Handwritten/` holds initializers the codegen doesn't emit; keep it when regenerating. After regenerating, update `SpacetimeBackend+Contract.swift` and run `xcodegen`.

## Notes from the hour-0 spike (SDK 2026-09-27 `c966b6b`, SpacetimeDB 2.13)
- Connect, subscribe, reducer calls, ownership rejection and reconnect all work.
  A->B live update latency on localhost was ~1.5 ms.
- TS modules expose snake_case names: reducer `setDisposition` is called as `set_disposition`,
  and column `widthM` is `width_m`. The codegen handles this.
- Initial subscription rows arrive as `.inserted` row events, so register `rowEvents` **before** `subscribe`.
- The SDK auto-reconnects but does **not** replay subscriptions; `SpacetimeBackend` resubscribes on reconnect.
- The SDK needs **Swift 6.2+ / Xcode 26+** (it uses `SendableMetatype`), despite its README saying 6.1.
- Generated reducer initializers lowercase multi-word args (`itemid:`), and a reducer argument named
  `name` becomes `nameArg:`.
