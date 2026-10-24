# Decision log

One file per accepted proposal: `NNNN-<slug>.md`, where NNNN is the GitHub issue number of the proposal. Use the `/propose` skill. Format:

```
# <title>
Status: accepted | superseded by NNNN
Context: why this came up
Decision: what we're doing
Consequences: what changes, which lanes/files
```

Initial decisions (from kickoff, Fri Oct 23):
- **iOS-only client**, no web app.
- **SpacetimeDB** is the backend (over Convex). The Swift client is a risk, with a worker-gateway fallback.
- **Agents, not our own marketplace:** eBay sandbox for selling, Apify for comps and deals, x402/CDP for agent payments, Visa for checkout (stubbed until the Starter Pack).
- **Git:** PR + green CI + self-merge. No required reviewer.
