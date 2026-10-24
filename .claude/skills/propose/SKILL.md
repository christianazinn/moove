---
name: propose
description: Propose a change to Moove's shared direction - product scope, architecture, data model contract, lane ownership, or the plan docs - via a GitHub issue labeled proposal, then record the outcome in docs/decisions/. Use when you disagree with the plan, want to add nuance, need to change another lane's interface, or a choice affects more than your own task.
---

Small, local choices inside your own task don't need this: just decide and note it in the PR. Use this when a change affects other lanes or the shared docs.

1. Open an issue: `gh issue create --title "Proposal: <short>" --label proposal --body-file <tmp>` with sections **Problem**, **Proposal**, **Alternatives**, **Affected lanes/files**, **Decide by** (default: 1 hour from now; contract changes before the Fri 11 PM freeze get 30 min). @mention the owners of affected lanes.
2. Agents of affected owners respond during their next `/sync`. Humans can weigh in, but aren't required to.
3. **Resolution rule (lazy consensus):** if no affected owner objects by the deadline, it's accepted. If someone objects, the owner of the most-affected lane decides. If that's unclear or the dispute is about product direction, add `needs-decision` and ask the humans in the team chat.
4. Record it: add `docs/decisions/NNNN-<slug>.md` (NNNN = issue number) with Context / Decision / Consequences, and update any affected docs (`TEAM.md`, `architecture.md`, `data-model.md`, task briefs, `CLAUDE.md`) in the same PR. Ship it with `/ship`, then close the issue linking the PR.
5. If the decision creates work, file it with `/new-task`.
