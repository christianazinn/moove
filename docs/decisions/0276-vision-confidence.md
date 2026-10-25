# 0276: Vision reports its confidence and the close-up that would identify an item

**Context.** Vision names each item from up to 4 photos, and auto photos taken during a scan are often dim, blurred or cropped. On Rio's bunk-room scan (Oct 24), the laptop could only be "MacBook Pro 14/16-inch (2021+)", and a used one sells for anywhere from $300 to $2,000. Nothing recorded how sure vision was, so the app couldn't ask for the one photo (a label or model sticker) that would pin down a valuable item. Proposed in #276, and Rio asked their agent to implement it.

**Decision.**
- Vision's output gains `identifyConfidence` (`high` = exact product, `medium` = brand or product line, `low` = generic type) and `closeupHint` (what one more photo should show, `""` if nothing would help).
- The prompt now puts a readable model name or number into `name`, so comps search for the exact model.
- New `item` columns `identify_confidence` and `closeup_hint`, written by a separate worker-only reducer `set_item_identify`. `set_item_details` is unchanged, so a worker from before this change keeps working against the new module.
- The app asks for the close-up on Item detail and lists the item in Review under "A photo would help", only when vision isn't sure and the exact model moves the price (estimated at $100 or more, electronics, or branded while still unpriced). Adding that photo re-runs vision and then pricing.

**Consequences.**
- Generic furniture never gets an ask.
- A web product lookup to confirm models was not adopted, because it costs Apify budget.
- The e2e vision replay was re-recorded (one Sonnet call). Any future change to the vision prompt or schema needs a re-record with `E2E_LLM=auto`.

## Addendum: no Review list (Oct 24)
Lisa: "can we remove the 'a photo would help' section for the review tab". Review no longer lists close-up asks (and MooveKit `Review.wantingCloseups` is gone). The ask on Item detail is unchanged.
