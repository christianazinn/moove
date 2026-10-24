---
name: ship
description: Ship the current Moove branch - rebase on main, run lane checks, push, open/update the PR linked to its issue, and squash-merge once CI is green. Use when someone says "ship", "merge", "open a PR", or "I'm done".
---

1. Refuse to run on `main`. The branch should look like `<name>/<n>-<slug>`, and `<n>` is the issue.
2. Make sure everything is committed (ask before committing anything unrelated). Never commit `.env*` files except `.env.example`.
3. `git fetch origin && git rebase origin/main`. Resolve conflicts carefully, and if a conflict is in another lane's files, ask the user.
4. Run checks for the directories touched:
   - `spacetime/`, `agents/`: `npm run typecheck` and `npm test` (if present)
   - `ios/MooveKit/`: `swift test` (if a Swift toolchain is available)
   - `ios/`: `xcodegen && xcodebuild -scheme Moove -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` (macOS only)
   Fix failures before continuing.
5. `git push --force-with-lease -u origin HEAD` (it's your own branch, so this is fine after a rebase).
6. If no PR exists, run `gh pr create --fill --body` using `.github/pull_request_template.md`, with `Closes #<n>`. Otherwise update the PR body if scope changed. If the change touched the data model, say so loudly in the PR and remind the user to tell the team.
7. `gh pr merge --squash --auto --delete-branch`. Report the PR URL and CI status (`gh pr checks`).
8. If CI fails, show the failing log (`gh run view --log-failed`) and fix it.
