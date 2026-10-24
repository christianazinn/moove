# spacetime/ - SpacetimeDB module (TypeScript)

Lane: backend (task #2). This is **the contract**. Everyone depends on it.

- Source of truth for the schema is `docs/data-model.md`. Keep it in sync with the code in the same PR.
- Reducers must be deterministic: **no network calls, no randomness, no clocks except `ctx.timestamp`**. Outbound I/O belongs in `agents/`.
- Authorize writes with `ctx.sender`. Worker-only reducers check against the worker identity.
- After any table or reducer change, regenerate the client bindings for `agents/` (`spacetime generate --lang typescript --out-dir ../agents/src/module_bindings`) and update `ios/MooveKit` models.
- Contract changes go in their own small PR. Announce them in the team chat.
- The SpacetimeDB TS module API is evolving, so check https://spacetimedb.com/docs before writing code.
- Fill in the build/publish/generate commands in the root `CLAUDE.md` once they're set up.
