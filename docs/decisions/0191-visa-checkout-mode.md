# 0191: The worker announces its Visa checkout mode (service_config `visa_checkout`)

**Status:** accepted by lazy consensus (no objections by the 2026-10-24 11:01 UTC deadline on #191). Worker and app shipped by the commerce lane. **Module key: backend lane.** `visa_checkout` was added to `SERVICE_KEYS` in `spacetime/src/index.ts` and to `docs/data-model.md` in #235. Each database (maincloud `moove`, `moove-demo`, local) still needs that module republished. Until then it rejects the key and the app shows nothing new.

## Context
A pending purchase approval (e.g. the $429.99 wayfair sofa) showed no SIMULATED pill even when the worker's Visa rail was simulated. `deal` and `approval` carry no rail mode, the `payment` row (which has `simulated`) only exists after the approval, and older payments can't be trusted because the worker can restart with a different `VISA_PROVIDER`. That broke the "label anything simulated" rule. See #191.

## Decision
- On start, `announceService` (`agents/src/service.ts`) writes `service_config` `visa_checkout` from the same env the checkout uses (`visaCheckoutMode()` in `agents/src/integrations/visa.ts`, which mirrors `createVisaCheckout`):
  - `simulated`: `VISA_PROVIDER=simulated`, no `VISA_ACCEPTANCE_*` keys, or an unknown / not-implemented provider (`vic`).
  - `sandbox`: Visa Acceptance (CyberSource) sandbox with no simulated fallback. An explicit `VISA_PROVIDER=acceptance` without keys is also `sandbox`: those checkouts fail loudly and are never simulated.
  - `sandbox+fallback`: the sandbox, with a per-authorization fallback to simulated on 5xx/network errors (`VISA_FALLBACK_SIMULATED=1`, or on by default when the provider was picked from the keys).
- A module that rejects the key logs one warning line and the worker continues. There is no retry.
- App: MooveKit `ServiceConfig.visaCheckout` (nil when missing or unknown) and `Approval.purchaseRailTag(_:)`. Pending purchase approvals in Sell & Buy > Approvals show the filled SIMULATED pill and say "Simulated purchase, no money will move" to VoiceOver for `simulated`, and the outlined VISA SANDBOX tag (the #140 payment-row style) for `sandbox`. They show nothing extra for `sandbox+fallback`, since a purchase may still end up simulated and the payment row says which after checkout, or when the key is missing. Listing approvals keep using `listing.simulated`.
- The offline demo reports `simulated` (it never pays anyone), so the sofa approval shows the pill.

## Consequences
- This adds a key, not a table or column, so there's no binding regen. `docs/data-model.md` (owned by the backend lane) lists it as of #235.
- Workers have to restart to announce the key once the module accepts it.
- The mode is per worker process, not per approval: a restart with a different `VISA_PROVIDER` changes the label on approvals that are already pending. That's acceptable, since the label describes what approving would do now.
