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
| `scan` | room_id, usdz_url, captured_room_json_url, **sweep_status**: `none`\|`pending`\|`running`\|`done`\|`failed` |
| `scan_photo` | scan_id, url: wide room photos for the photo sweep (max 12 per scan) |
| `item` | room_id, scan_id, scan_object_id, name, category, width_m, height_m, depth_m, photo_urls[], material, brand, condition, **details_status**, est_value_cents, est_low_cents, est_high_cents, **pricing_status**, **disposition**, **disposition_source**: `auto`\|`user`, disposition_reason, fragile, maybe_sentimental, **model_url**, **model_source**: `capture`\|`sam3d`\|`''`, **model_status** |, **attributes_json** (JSON array of RoomPlan attributes like `ChairType.swivel`, default `[]`), **colors_json** (`{"primary":"#RRGGBB","secondary":"#RRGGBB"}`, default `''`) for the voxel look (#110)
| `comp` | item_id, source (`fb`\|`craigslist`\|`ebay`\|…), title, price_cents, url |
| `listing` | item_id, platform (`ebay`), title, description, price_cents, status, external_id, url, simulated |
| `approval` | kind: `listing`\|`purchase`, ref_id, amount_cents, summary, status, **decided_via**: `''` (pending)\|`app`\|`ciba`, ciba_subject (the Auth0 `sub` the worker reported) |
| `shopping_item` | name, category, reason, status, chosen_deal_id |
| `deal` | shopping_item_id, source, title, price_cents, url, seller_info, fraud_score (0-1), ai_text_score (0-1), fraud_reasons[] |
| `payment` | agent, rail: `x402`\|`visa`, purpose, payee, amount_usd_micros, tx_hash, status, simulated, ref_table, ref_id |
| `new_home` | name, source: `demo`\|`zillow`\|`manual`, floor_plan_json |
| `layout` | new_home_id, name, placements_json |
| `agent_event` | agent, kind: `plan`\|`tool_call`\|`result`\|`payment`\|`approval`\|`error`, message, ref_table, ref_id, data_json |
| `service_config` (pk `key`) | value: runtime settings the worker announces on every start: `upload_base_url` (where to POST `/upload`), `worker_version` (git sha), `worker_started_at` (ISO). Read it instead of hard-coding the upload URL (#122). |

Status values:
- `details_status` / `pricing_status` / `model_status`: `pending`\|`running`\|`done`\|`failed`. The worker picks up `pending` rows. The SAM 3D agent only takes items that have a photo.
- `disposition`: `undecided`\|`keep`\|`sell`\|`donate`\|`trash`
- `listing.status`: `draft`\|`awaiting_approval`\|`rejected`\|`posted`\|`sold`\|`failed`
- `approval.status`: `pending`\|`approved`\|`denied`\|`expired`. Since #42 nothing sets `expired`; decisions are only `approved`\|`denied`.
- `shopping_item.status`: `open`\|`searching`\|`found`\|`bought`
- `payment.status`: `pending`\|`settled`\|`failed`

## Views (#41 part B)
- **`my_room`**: rooms you own or joined through `room_member` (base `room` rows, including `join_code`).
- **`my_user`**: your own `user` row.

**Step 1 (now):** additive. Clients should subscribe with `SELECT * FROM my_room` / `SELECT * FROM my_user` instead of filtering the base tables. **Step 2 (after the iOS switch):** `room` and `user` become private, so join codes, emails and Auth0 subjects stop being world-readable, and the worker gets a worker-only users view for CIBA. One-off SQL queries against views return no rows (SDK behavior); use subscriptions.

## Input limits (#146)
Enforced in the module, so they hold for every client:
- **Item sizes:** finite numbers, 0–30 m (`width_m`, `height_m`, `depth_m`) on every import, re-scan and `add_item`.
- **Imports:** at most **200 objects** per `import_scan` / `import_scan_v2` / `create_scan` call.
- **Lengths:** item `name` / `category` ≤ 120, `scan_object_id` ≤ 64, room names ≤ 80, scan and model URLs ≤ 2048 (a too-long photo URL is dropped, not fatal).
- **`service_config.upload_base_url`:** a bare `https://host[:port]` origin (no userinfo, path or query), or `http://` only for localhost / 127.x / 10.x / 192.168.x / 172.16–31.x.
- **Worker role:** pinned per database for maincloud `moove` and `moove-demo` (`PINNED_WORKERS`); every other database (local dev, e2e) keeps first-caller-wins.

## Reducers
**App (owner), and the worker can call these too:**
- **Users:** `register_user(auth0_sub, name, email)` (`auth0_sub`/`email` come from the token, see above), `set_approval_threshold(cents)` (`-1` = always ask, else `0..10000000` = $100,000)
- **Voxel look (#110):** **`import_scan_v2(room_name, home, usdz_url, captured_room_json_url, objects[])`**: same as `import_scan`, but each object also has `attributes: string[]` (RoomPlan raw values, `Type.value`, at most 32; `[]` for extra-object detections). `import_scan` is unchanged for older app builds. `set_item_attributes(item_id, attributes[])` and `set_item_colors(item_id, colors_json)` (`''` clears) need room access or the worker.
- **Capture:** **`import_scan(room_name, home, usdz_url, captured_room_json_url, objects[])`**: the app's one-shot import that creates room, scan and items atomically. `objects[]` = {scan_object_id, name ('' means use category), category, width_m, height_m, depth_m, photo_url ('' if none)}. Also `create_room(name, home)`, `join_room(code)`, `rotate_join_code(room_id)` and `remove_member(room_id, member)` (room owner only), and `create_scan(room_id, ...)` to re-scan (it updates items by `scan_object_id`), `add_item(room_id, object)`, `add_item_photo(item_id, url)` (re-queues vision), `delete_item`
- **Room photo sweep:** `add_scan_photo(scan_id, url)`: after a scan, attach a few wide room photos (upload each to the worker's `/upload` first). Each one sets `sweep_status = pending`, and the worker sweeps once photos stop arriving (~8 s). It renames scanned items it recognizes and adds items RoomPlan missed (`scan_object_id = "photo:<scan_id>"`: no RoomPlan box, size is an estimate).
- **3D models (#65):** `set_item_model(item_id, url, source)`: the app after Object Capture (`capture`, USDZ) or the SAM 3D agent (`sam3d`, GLB). `url` must be http(s), or `''` to clear. A `sam3d` result never replaces a `capture` model. `add_item_photo` re-queues SAM 3D unless the item has a captured model.
- **Review:** `set_disposition(item_id, disposition)` (marks it `user`; auto-sort never overrides it), `set_sentimental(item_id, value)`, `set_fragile(item_id, value)` (absolute setters, not toggles), `rename_item`
- **Approvals:** `decide_approval(approval_id, status)`: **owner only** (not the worker), `status` must be `approved`\|`denied`, records `decided_via = 'app'` (#42)
- **Shopping:** `add_shopping_item(owner, name, category, reason)`, `set_shopping_status`, `remove_shopping_item`, `choose_deal(shopping_item_id, deal_id)`
- **New home:** `create_new_home(name, source, floor_plan_json)`, `save_layout(new_home_id, name, placements_json)`

**Worker only:**
- `register_worker(label)`
- **Service config (worker):** `set_service_config(key, value)` (keys: `upload_base_url` (http(s) origin), `worker_version`, `worker_started_at`)
- **Photo sweep (worker):** `set_sweep_status(scan_id, status)`, `apply_sweep_match(item_id, name, category, material, brand, condition, fragile, maybe_sentimental, photo_url)` (a changed name/brand re-queues pricing), `add_sweep_item(scan_id, name, category, width_m, height_m, depth_m, material, brand, condition, fragile, maybe_sentimental, photo_url)` (`details_status = done`, so no second vision call)
- **Item enrichment:** `set_item_stage(item_id, stage, field: details|pricing|model)`, `set_item_details(...)`, `add_comps(item_id, comps[])`, `set_est_value(item_id, est_value_cents, est_low_cents, est_high_cents)`
- **Sorting:** `set_auto_disposition(item_id, disposition, reason)`. It no-ops on user-set items and forces `undecided` on `maybe_sentimental` ones.
- **Listings, approvals, deals:** `create_listing_draft(...)`, `update_listing(listing_id, status, external_id, url, price_cents)` (`''`/`-1` keep the current value; worker-only since #44), `request_approval(owner, kind, ref_id, amount_cents, summary)` (the listing, or deal for `purchase`, must belong to `owner` and `amount_cents` must equal its `price_cents`), `record_ciba_decision(approval_id, status, ciba_subject)` (`approved`\|`denied`; `ciba_subject` must equal the owner's `user.auth0_sub`; records `decided_via = 'ciba'`), `add_deal(...)`, `set_deal_fraud(deal_id, fraud_score, ai_text_score, reasons[])`
- CIBA results are relayed by the worker and not verified in the module (reducers can't fetch JWKS); `decided_via` says which path decided.
- **Payments and logging:** `record_payment(...)`, `update_payment(payment_id, status, tx_hash)`, `log_agent_event(owner, agent, kind, message, ref_table, ref_id, data_json)`
