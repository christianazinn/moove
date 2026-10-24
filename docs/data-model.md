# Data model (the contract)

**Source of truth: `spacetime/src/index.ts`.** This file summarizes it. Change both in the same PR, run `npm run generate` in `spacetime/` to refresh `agents/src/module_bindings/`, update the `ios/MooveKit` models, and announce the change (label: `contract-change`).

## Conventions
- **Names:** TS code uses camelCase (`ctx.db.shoppingItem`, `photoUrls`). On the wire, in SQL and in generated clients, names are **snake_case**: tables `shopping_item`, `agent_event`, `new_home`; columns `photo_urls`; reducers `create_scan`, `set_auto_disposition`.
- **"Enums" are plain strings**, validated in reducers. We avoid sum types and options so the community Swift SDK only has to decode primitives, strings, arrays and products. Allowed values are listed below.
- **Unknown values use sentinels:** `''` for strings, `-1` for numbers (`est_value_cents`, `fraud_score`, `ai_text_score`), `0` for ids (`scan_id`, `chosen_deal_id`).
- **Money:** prices are `i64` cents. Payments use `amount_usd_micros` (`i64`, USD × 1e6), so x402 USDC (6 decimals) and card amounts share one column.
- **Types:** ids are `u64` auto-inc (pass `0` on insert). Dimensions are `f64` meters. Times are `Timestamp`. Ownership is `owner: Identity`.
- **Room access:** room items are readable and editable by the owner, by `room_member`s (who join with `join_room(code)`), and by the worker. Other tables are owner-only. The owner can `rotate_join_code` (the old code stops working) and `remove_member` if a code leaks (#41).
- **All tables are public** for now, so clients subscribe with `WHERE owner = ...`. Private tables + per-user views (#41 part B) are deferred until the demo path works end to end.
- **Worker auth:** the agent worker calls `register_worker` on connect. **On maincloud** (the module checks `ctx.databaseIdentity`) only the pinned worker identity in `spacetime/src/index.ts` (`MAINCLOUD_WORKER_IDENTITIES`) can register or act as the worker, even if another row is in `worker` (#44). **On any other database** (local dev) the first caller wins, and after that only registered workers can add more. Worker-only reducers reject everyone else. Rotating the maincloud worker means editing that constant and republishing.
- **Connection gate (#41 part A):** `client_connected` rejects connections that aren't an Auth0 ID token from our tenant (`iss` = `https://dev-78lq8spq27b2bipk.us.auth0.com/`, `aud` contains the iOS native client id) or the worker (on a local DB with no worker yet, any caller gets in so the first worker can register). It is **off** (`REQUIRE_AUTH0 = false`) until the app no longer falls back to anonymous tokens; flipping it is a one-line change plus a republish. Tested locally: with it on, HTTP reducer calls and `spacetime sql` are rejected too.
- **Identity claims:** `register_user` takes `auth0_sub` (and `email`, when the token has one) from the caller's verified Auth0 token, never from its args (#44). Anonymous tokens get `auth0_sub = ''`. The `auth0_sub` arg is ignored but kept so bindings don't change. The SQL column name is `auth_0_sub` (that's how SpacetimeDB snake-cases `auth0Sub`).
- **Photo URLs:** `add_item_photo` rejects anything but `http(s)://`; `import_scan`/`create_scan`/`add_item` drop a non-http(s) `photo_url` and keep the item (#44). The worker only reads photos from its own upload dir, or https hosts in `ALLOWED_PHOTO_HOSTS` (see `agents/CLAUDE.md`).

## Tables
| Table | Columns (beyond `id`, `owner`, timestamps) |
|---|---|
| `user` (pk `identity`) | auth0_sub, name, email, approval_threshold_cents (default 10000 = $100) |
| `worker` (pk `identity`) | label |
| `room` | name, home: `old`\|`new`, join_code (6 chars, unique) |
| `room_member` | room_id, member (Identity), for shared access (#10) |
| `scan` | room_id, usdz_url, captured_room_json_url |
| `item` | room_id, scan_id, scan_object_id, name, category, width_m, height_m, depth_m, photo_urls[], material, brand, condition, **details_status**, est_value_cents, est_low_cents, est_high_cents, **pricing_status**, **disposition**, **disposition_source**: `auto`\|`user`, disposition_reason, fragile, maybe_sentimental |
| `comp` | item_id, source (`fb`\|`craigslist`\|`ebay`\|…), title, price_cents, url |
| `listing` | item_id, platform (`ebay`), title, description, price_cents, status, external_id, url, simulated |
| `approval` | kind: `listing`\|`purchase`, ref_id, amount_cents, summary, status, **decided_via**: `''` (pending)\|`app`\|`ciba`, ciba_subject (the Auth0 `sub` the worker reported) |
| `shopping_item` | name, category, reason, status, chosen_deal_id |
| `deal` | shopping_item_id, source, title, price_cents, url, seller_info, fraud_score (0-1), ai_text_score (0-1), fraud_reasons[] |
| `payment` | agent, rail: `x402`\|`visa`, purpose, payee, amount_usd_micros, tx_hash, status, simulated, ref_table, ref_id |
| `new_home` | name, source: `demo`\|`zillow`\|`manual`, floor_plan_json |
| `layout` | new_home_id, name, placements_json |
| `agent_event` | agent, kind: `plan`\|`tool_call`\|`result`\|`payment`\|`approval`\|`error`, message, ref_table, ref_id, data_json |

Status values:
- `details_status` / `pricing_status`: `pending`\|`running`\|`done`\|`failed`. The worker picks up `pending` rows.
- `disposition`: `undecided`\|`keep`\|`sell`\|`donate`\|`trash`
- `listing.status`: `draft`\|`awaiting_approval`\|`rejected`\|`posted`\|`sold`\|`failed`
- `approval.status`: `pending`\|`approved`\|`denied`\|`expired`. Since #42 nothing sets `expired`; decisions are only `approved`\|`denied`.
- `shopping_item.status`: `open`\|`searching`\|`found`\|`bought`
- `payment.status`: `pending`\|`settled`\|`failed`

## Reducers
**App (owner), and the worker can call these too:**
- **Users:** `register_user(auth0_sub, name, email)` (`auth0_sub`/`email` come from the token, see above), `set_approval_threshold(cents)` (`-1` = always ask, else `0..10000000` = $100,000)
- **Capture:** **`import_scan(room_name, home, usdz_url, captured_room_json_url, objects[])`**: the app's one-shot import that creates room, scan and items atomically. `objects[]` = {scan_object_id, name ('' means use category), category, width_m, height_m, depth_m, photo_url ('' if none)}. Also `create_room(name, home)`, `join_room(code)`, `rotate_join_code(room_id)` and `remove_member(room_id, member)` (room owner only), and `create_scan(room_id, ...)` to re-scan (it updates items by `scan_object_id`), `add_item(room_id, object)`, `add_item_photo(item_id, url)` (re-queues vision), `delete_item`
- **Review:** `set_disposition(item_id, disposition)` (marks it `user`; auto-sort never overrides it), `set_sentimental(item_id, value)`, `set_fragile(item_id, value)` (absolute setters, not toggles), `rename_item`
- **Approvals:** `decide_approval(approval_id, status)`: **owner only** (not the worker), `status` must be `approved`\|`denied`, records `decided_via = 'app'` (#42)
- **Shopping:** `add_shopping_item(owner, name, category, reason)`, `set_shopping_status`, `remove_shopping_item`, `choose_deal(shopping_item_id, deal_id)`
- **New home:** `create_new_home(name, source, floor_plan_json)`, `save_layout(new_home_id, name, placements_json)`

**Worker only:**
- `register_worker(label)`
- **Item enrichment:** `set_item_stage(item_id, stage, field: details|pricing)`, `set_item_details(...)`, `add_comps(item_id, comps[])`, `set_est_value(item_id, est_value_cents, est_low_cents, est_high_cents)`
- **Sorting:** `set_auto_disposition(item_id, disposition, reason)`. It no-ops on user-set items and forces `undecided` on `maybe_sentimental` ones.
- **Listings, approvals, deals:** `create_listing_draft(...)`, `update_listing(listing_id, status, external_id, url, price_cents)` (`''`/`-1` keep the current value; worker-only since #44), `request_approval(owner, kind, ref_id, amount_cents, summary)` (the listing, or deal for `purchase`, must belong to `owner` and `amount_cents` must equal its `price_cents`), `record_ciba_decision(approval_id, status, ciba_subject)` (`approved`\|`denied`; `ciba_subject` must equal the owner's `user.auth0_sub`; records `decided_via = 'ciba'`), `add_deal(...)`, `set_deal_fraud(deal_id, fraud_score, ai_text_score, reasons[])`
- CIBA results are relayed by the worker and not verified in the module (reducers can't fetch JWKS); `decided_via` says which path decided.
- **Payments and logging:** `record_payment(...)`, `update_payment(payment_id, status, tx_hash)`, `log_agent_event(owner, agent, kind, message, ref_table, ref_id, data_json)`
