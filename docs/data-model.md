# Data model (draft contract)

This is the draft. **Task #2** turns it into `spacetime/src/` and keeps this file in sync. Changes after the freeze (~Fri 11 PM) go in their own PR and must be announced to the team.

Conventions:
- IDs are `u64` auto-inc unless noted.
- Money is stored as integer **cents** (`priceCents`), with USDC amounts in its smallest unit (`amountAtomic`, 6 decimals).
- Dimensions are in meters.
- Timestamps use SpacetimeDB `Timestamp`.
- Every row a user owns has `owner: Identity`.

| Table | Key fields |
|---|---|
| `users` | identity (pk), auth0Sub, name, email, approvalThresholdCents, createdAt |
| `rooms` | id, owner, name, home: `old`\|`new` |
| `scans` | id, owner, roomId, usdzUrl, capturedRoomJsonUrl, createdAt |
| `items` | id, owner, roomId, scanObjectId?, name, category, widthM, heightM, depthM, photoUrls[], material?, brand?, condition?, estValueCents?, disposition: `keep`\|`sell`\|`donate`\|`trash`\|`undecided`, dispositionSource: `auto`\|`user`, dispositionReason?, fragile, maybeSentimental, updatedAt |
| `comps` | id, itemId, source: `fb`\|`craigslist`\|`ebay`\|other, title, priceCents, url, fetchedAt |
| `listings` | id, itemId, platform: `ebay`, title, description, priceCents, status: `draft`\|`awaiting_approval`\|`posted`\|`sold`\|`failed`, externalId?, url?, simulated |
| `approvals` | id, owner, kind: `listing`\|`purchase`, refId, amountCents, status: `pending`\|`approved`\|`denied`\|`expired`, requestedAt, decidedAt? |
| `shoppingList` | id, owner, name, category, reason?, status: `open`\|`searching`\|`found`\|`bought`, chosenDealId? |
| `deals` | id, shoppingItemId, source, title, priceCents, url, sellerInfo?, fraudScore?, fraudReasons[] |
| `payments` | id, owner, agent, rail: `x402`\|`visa`, purpose, payee, amountAtomic or amountCents, txHash?, status, simulated, createdAt |
| `newHome` | id, owner, name, source: `demo`\|`zillow`\|`manual`, floorPlanJson (rooms: polygon + dims) |
| `layouts` | id, newHomeId, name, placementsJson (itemId → room, x, y, rotation) |
| `agentEvents` | id, owner, agent, kind: `plan`\|`tool_call`\|`result`\|`payment`\|`approval`\|`error`, message, refTable?, refId?, dataJson?, createdAt |

## Reducers (first pass)
- **Users:** `registerUser`, `setApprovalThreshold`
- **Capture:** `createRoom`, `createScan`, `upsertItemsFromScan`, `addItemPhoto`
- **Items, user side:** `setDisposition` (user sets `dispositionSource=user`), `toggleSentimental`
- **Items, worker side:** `setItemDetails` (vision), `addComps`, `setEstValue`, `setAutoDisposition` (must no-op if `dispositionSource=user` or `maybeSentimental`)
- **Listings:** `createListingDraft`, `updateListingStatus`
- **Approvals:** `requestApproval`, `decideApproval`
- **Shopping:** `addShoppingItem`, `addDeal`, `chooseDeal`
- **Records:** `recordPayment`, `logAgentEvent`
- **New home:** `createNewHome`, `saveLayout`

Worker-only reducers should check `ctx.sender` against the worker's identity.
