---
name: sync
description: Catch up on team coordination - read open issues, PRs, mentions, blocked items, proposals and recent merges, then report what matters to me and post my status. Use at the start of a session, after a break, before claiming new work, or when someone asks "what's going on / what should I do next".
---

1. `git fetch origin` and `git log --oneline origin/main -15` to see what merged recently. Flag merges touching `spacetime/` or `docs/data-model.md` (contract changes) and anything in my lane's directories.
2. `gh issue list --state open --json number,title,labels,assignees --limit 100`. Group by: mine, blocked, `needs-decision` / `proposal`, `help-wanted`/unassigned.
3. Mentions and threads aimed at me: `gh search issues --involves @me --state open` and `gh search prs --involves @me --state open`. Read new comments on those.
4. Open PRs: `gh pr list --json number,title,author,isDraft,statusCheckRollup`. Note red CI on PRs touching my lane.
5. For every **open proposal** (`label:proposal`): read it, and if it affects my lane, comment with my agent's view (agree / concerns / alternative), signed as `<my name>'s agent`.
6. For every issue **blocked on my work**: reply with an ETA or a workaround (fixture, stub, interface).
7. Report to my human in under 10 bullets: what changed, what needs their decision, what I recommend doing next (the highest-priority unblocked issue in my lane, else a `help-wanted` one).
8. If I have an in-progress issue, post a one-line status comment on it.
