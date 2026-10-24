---
name: new-task
description: File a new Moove task - write a brief in docs/tasks/ and open a matching GitHub issue with labels. Use when work is discovered that isn't covered by an existing issue (a follow-up, a bug, a split-out subtask, a stretch idea), or when someone says "make an issue/task for X".
---

1. Check for duplicates first: `gh issue list --state open --search "<keywords>"`. If one exists, comment on it instead.
2. Pick the lane (`backend`, `ios-capture`, `ios-newhome`, `commerce`) and leave it unassigned (people self-assign); add `help-wanted` if it is up for grabs.
3. Create the issue: `gh issue create --title "<title>" --label "task,lane:<lane>" --body-file <tmp>`. The body follows the brief format in `docs/tasks/` (Goal, Context, Scope, Tables touched, Acceptance criteria, Demo fallback, Depends on).
4. Add the brief as `docs/tasks/<NN>-<slug>.md` where NN is the **issue number** (same frontmatter as the other briefs), and commit it on your current branch, or on a tiny `docs/<NN>-brief` branch shipped with `/ship`.
5. If it blocks or is blocked by other issues, comment on those issues with a link (`Blocks #x` / `Blocked by #y`) and add the `blocked` label where relevant.
6. If it belongs to someone else's lane, @mention them in the issue body. Don't assign other people without asking.
