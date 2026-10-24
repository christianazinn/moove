# 0146: Module-side input hardening (#17 follow-up)

**Status:** accepted (lazy consensus on #146, Sat Oct 24 3:23 AM PDT; backend lane accepted all five). Implemented in #159, republished to maincloud `moove` and `moove-demo` (logic only, no schema change).

## Context
The #17 follow-up security pass (#150) found four gaps that only the module can close, because any client calls these reducers directly:
- the worker role was pinned only on `moove`, so on any other maincloud database (`moove-demo`) the first `register_worker` caller became the worker and could redirect every phone's uploads through `upload_base_url`;
- the module's `upload_base_url` rule accepted `user@host` and plain http to public hosts;
- item sizes accepted NaN, ±Infinity, negatives and `1e300`, which crash the app's truck estimate for every room member;
- scan imports had no object-count or string-length caps;
- (low) `set_item_model` URLs were only prefix-checked.

## Decision
- `PINNED_WORKERS` is a per-database map that covers maincloud `moove` and `moove-demo`. Local and e2e databases keep first-caller-wins.
- `upload_base_url` must be a bare `https://host[:port]` origin, or `http://` only for localhost and private LAN ranges (the same rule as MooveKit `ServiceConfig`).
- Item sizes must be finite and 0–30 m. Imports take at most 200 objects. Invalid objects on import paths are skipped and reported in one `agent_event`, while `add_item` rejects them.
- Length caps: name/category 120, `scan_object_id` 64, room name 80, URLs 2048.
- `set_item_model` URLs must be http(s) and at most 2048 characters.

The exact limits are in [`docs/data-model.md`](../data-model.md) under "Input limits (#146)".

## Consequences
- A hostile room member can no longer crash the room or flood the worker with items.
- A stranger can't become the worker on `moove-demo`.
- Older app builds keep working: no table shapes changed, so no binding regen.
- Scans with a bad object lose only that object, and say so in the agent log.
