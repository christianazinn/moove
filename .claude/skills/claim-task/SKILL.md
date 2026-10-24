---
name: claim-task
description: Claim a Moove GitHub issue - assign it to me, create a properly named branch off latest main, and load the task brief and dependency status. Use when someone says "claim", "take", or "start" an issue/task number.
---

Argument: an issue number `<n>`.

1. `git fetch origin` and make sure the working tree is clean (if not, stop and ask).
2. `gh issue view <n> --json title,body,labels,assignees,state`. If it's assigned to someone else, stop and ask.
3. `gh issue edit <n> --add-assignee @me`.
4. Branch name: `<first-name-lowercase>/<n>-<short-kebab-slug-of-title>`. Use `git config user.name` for the first name. Run `git switch -c <branch> origin/main`.
5. Read `docs/tasks/<NN>-*.md` (NN is zero-padded), the lane's `CLAUDE.md`, and `docs/data-model.md`.
6. For each dependency listed in the brief, check `gh issue view <dep> --json state,assignees` and report which are done, in progress or unassigned. If a dependency isn't merged, suggest working against fixtures or stubs.
7. Comment on the issue: `gh issue comment <n> --body "Claimed - branch <branch>"`.
8. Summarize the goal, acceptance criteria and a short implementation plan, then start working.
