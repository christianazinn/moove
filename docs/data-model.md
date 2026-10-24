# Data model (the contract)

**Source of truth: `spacetime/src/index.ts`.** This file summarizes it. Change both in the same PR, run `npm run generate` in `spacetime/` to refresh `agents/src/module_bindings/`, update the `ios/MooveKit` models, and announce the change (label: `contract-change`).

## Conventions
- **Names:** TS code uses camelCase (`ctx.db.shoppingItem`, `photoUrls`). On the wire, in SQL and in generated clients, names are **snake_case**: tables `shopping_item`, `agent_event`, `new_home`; columns `photo_urls`; reducers `create_scan`, `set_auto_disposition`.
- **"Enums" are plain strings**, validated in reducers. We avoid sum types and options so the community Swift SDK only has to decode primitives, strings, arrays and products. Allowed values are listed below.
- **Unknown values use sentinels:** `''` for strings, `-1` for numbers (`est_value_cents`, `fraud_score`, `ai_text_score`), `0` for ids (`scan_id`, `chosen_deal_id`).
- **Money:** prices are `i64` cents. Payments use `amount_usd_micros` (`i64`, USD × 1e6), so x402 USDC (6 decimals) and card amounts share one column.
- **Types:** ids are `u64` auto-inc (pass `0` on insert). Dimensions are `f64` meters. Times are `Timestamp`. Ownership is `owner: Identity`.
- **Room access:** room items are readable and editable by the owner, by `room_member`s (who join with `join_room(code)`), and by the worker. Other tables are owner-only.
- **All tables are public** for now, so clients subscribe with `WHERE owner = ...`. Tightening this is part of the security pass (#17).
- **Worker auth:** the agent worker calls `register_worker` once. The first caller wins, and after that only registered workers can add more. Worker-only reducers reject everyone else.

## Tables
| Table | Columns (beyond `id`, `owner`, timestamps) |
|---|---|
| `user` (pk `identity`) | auth0_sub, name, email, approval_threshold_cents (default 10000 = $100) |
| `worker` (pk `identity`) | label |
| `room` | name, home: `old`\|`new`, join_code (6 chars, unique) |
| `room_member` | room_id, member (Identity), for shared access (#10) |
| `scan` | room_id, usdz_url, captured_room_json_url |
| `item` | room_id, scan_id, scan_object_id, name, category, width_m, height_m, depth_m, photo_urls[], material, brand, condition, **details_status**, est_value_cents, est_low_cents, est_high_cents, **pricing_status**, **disposition**, **disposition_source**: `auto`\|`user`, disposition_reason, fragile, maybe_sentimental, **model_url**, **model_source**: `capture`\|`sam3d`\|`''`, **model_status** |
| `comp` | item_id, source (`fb`\|`craigslist`\|`ebay`\|…), title, price_cents, url |
| `listing` | item_id, platform (`ebay`), title, description, price_cents, status, external_id, url, simulated |
| `approval` | kind: `listing`\|`purchase`, ref_id, amount_cents, summary, status |
| `shopping_item` | name, category, reason, status, chosen_deal_id |
| `deal` | shopping_item_id, source, title, price_cents, url, seller_info, fraud_score (0-1), ai_text_score (0-1), fraud_reasons[] |
| `payment` | agent, rail: `x402`\|`visa`, purpose, payee, amount_usd_micros, tx_hash, status, simulated, ref_table, ref_id |
| `new_home` | name, source: `demo`\|`zillow`\|`manual`, floor_plan_json |
| `layout` | new_home_id, name, placements_json |
| `agent_event` | agent, kind: `plan`\|`tool_call`\|`result`\|`payment`\|`approval`\|`error`, message, ref_table, ref_id, data_json |

Status values:
- `details_status` / `pricing_status` / `model_status`: `pending`\|`running`\|`done`\|`failed`. The worker picks up `pending` rows. The SAM 3D agent only takes items that have a photo.
- `disposition`: `undecided`\|`keep`\|`sell`\|`donate`\|`trash`
- `listing.status`: `draft`\|`awaiting_approval`\|`rejected`\|`posted`\|`sold`\|`failed`
- `approval.status`: `pending`\|`approved`\|`denied`\|`expired`
- `shopping_item.status`: `open`\|`searching`\|`found`\|`bought`
- `payment.status`: `pending`\|`settled`\|`failed`

## Reducers
**App (owner), and the worker can call these too:**
- **Users:** `register_user(auth0_sub, name, email)`, `set_approval_threshold(cents)`
- **Capture:** **`import_scan(room_name, home, usdz_url, captured_room_json_url, objects[])`**: the app's one-shot import that creates room, scan and items atomically. `objects[]` = {scan_object_id, name ('' means use category), category, width_m, height_m, depth_m, photo_url ('' if none)}. Also `create_room(name, home)`, `join_room(code)`, and `create_scan(room_id, ...)` to re-scan (it updates items by `scan_object_id`), `add_item(room_id, object)`, `add_item_photo(item_id, url)` (re-queues vision), `delete_item`
- **3D models (#65):** `set_item_model(item_id, url, source)`: the app after Object Capture (`capture`, USDZ) or the SAM 3D agent (`sam3d`, GLB). `url` must be http(s), or `''` to clear. A `sam3d` result never replaces a `capture` model. `add_item_photo` re-queues SAM 3D unless the item has a captured model.
- **Review:** `set_disposition(item_id, disposition)` (marks it `user`; auto-sort never overrides it), `set_sentimental(item_id, value)`, `set_fragile(item_id, value)` (absolute setters, not toggles), `rename_item`
- **Listings and approvals:** `update_listing(listing_id, status, external_id, url, price_cents)` (`''`/`-1` keep the current value), `decide_approval(approval_id, status)`
- **Shopping:** `add_shopping_item(owner, name, category, reason)`, `set_shopping_status`, `remove_shopping_item`, `choose_deal(shopping_item_id, deal_id)`
- **New home:** `create_new_home(name, source, floor_plan_json)`, `save_layout(new_home_id, name, placements_json)`

**Worker only:**
- `register_worker(label)`
- **Item enrichment:** `set_item_stage(item_id, stage, field: details|pricing|model)`, `set_item_details(...)`, `add_comps(item_id, comps[])`, `set_est_value(item_id, est_value_cents, est_low_cents, est_high_cents)`
- **Sorting:** `set_auto_disposition(item_id, disposition, reason)`. It no-ops on user-set items and forces `undecided` on `maybe_sentimental` ones.
- **Listings, approvals, deals:** `create_listing_draft(...)`, `request_approval(owner, kind, ref_id, amount_cents, summary)`, `add_deal(...)`, `set_deal_fraud(deal_id, fraud_score, ai_text_score, reasons[])`
- **Payments and logging:** `record_payment(...)`, `update_payment(payment_id, status, tx_hash)`, `log_agent_event(owner, agent, kind, message, ref_table, ref_id, data_json)`
