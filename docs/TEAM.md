# Moove: Team Plan

**Deadline:** Devpost submission **Sun 9:00 AM**. Judging is 10:30-12:30, the **whole team must be at the table**, and we need a live demo plus a 2-minute pitch.

## The product in one paragraph
Moove is an iOS app for moving. You sign in and scan your room with LiDAR (RoomPlan), then snap photos of things. Claude identifies each item (material, brand, condition). A pricing agent pulls comparable listings through Apify, paying for data with x402 and showing every payment in a live spending log. Items get auto-sorted into keep / sell / donate / trash, and you fix anything on a review screen that syncs live across two phones. Possibly sentimental items are always left to you. A listing agent posts "sell" items to eBay, and expensive ones need your approval on your phone first. A buy agent shops the "still need" list for the new place and checks out with Visa. Finally, your kept items fly into a 3D model of the new home, with a few layout options, and a summary screen totals everything up.

## Lanes (pick among yourselves; self-assign issues)
| Lane | Machine | Tasks (issue #) |
|---|---|---|
| **Backend core & agents** | any (Linux OK) | #2 data model (SpacetimeDB), #5 photo → item details, #6 pricing agent (Apify), #8 auto-sort, #18 fraud screening (stretch) |
| **iOS capture & sync** | Mac | Swift SpacetimeDB spike (first!), #1 login (Auth0), #3 record demo scan, #4 scan upload → inventory, #9 review screen, #10 two-screen live sync |
| **iOS new home & wrap-up** | Mac | #13 new-home floor plan, #14 layouts + fly-in animation, #16 summary screen, #19 truck & packing plan (stretch) |
| **Commerce & payments** | Mac | #7 x402 live spending log, #11 eBay listing agent, #12 phone approval (Auth0), #15 "still need to buy" + Visa checkout, #17 security pass |

Each task has a full brief in `docs/tasks/` and a matching GitHub issue: goal, dependencies, acceptance criteria, demo fallback. When you finish one, take the next unblocked task in your lane. If your lane is blocked, take an unassigned or stretch task.

## Dependency order (critical path in bold)
1. **#2 data model** and #1 login and #3 demo scan run in parallel, with no dependencies
2. **#4 scan → inventory** (needs 2, 3), then **#5 photo → details**
3. **#6 pricing agent**, then #7 spending log and **#8 auto-sort**
4. **#9 review screen**, then #10 two-screen sync
5. #11 eBay listing agent (needs 6, 8), then #12 phone approval
6. #13 floor plan (no deps, start anytime), then #14 layouts + fly-in and #15 buy list + Visa
7. #16 summary, #17 security, then stretch #18 fraud and #19 truck/packing

## Do these RIGHT NOW (accounts take time)
- [ ] **Everyone:** create and **verify** a Coinbase account (required for each member to get the x402 prize), and join the Cal Hacks Slack.
- [ ] **Backend lane:** SpacetimeDB maincloud account, Apify account, Anthropic API key, CDP API key (portal.cdp.coinbase.com).
- [ ] **iOS capture lane:** Auth0 tenant (free), and install XcodeGen (`brew install xcodegen`). Confirm a LiDAR iPhone runs a dev build.
- [ ] **iOS new-home lane:** install XcodeGen. Pick or sketch the hardcoded demo house (room dimensions).
- [ ] **Commerce lane:** eBay developer account + **sandbox** keyset; grab the **Visa Starter Pack** from the live site when it's posted.
- [ ] Share keys **only** via a private channel, never in git or a public Slack channel.

## Timeline
| When | Milestone |
|---|---|
| Fri ~11 PM | Repo scaffolded, **data model frozen**, Swift↔SpacetimeDB spike decided (SDK or gateway), demo scan recorded |
| Sat 10 AM | **Thin end-to-end path:** login → scan → items in DB → priced (x402 payment shows in log) → sorted → review synced on 2 phones |
| Sat 9 PM | eBay listing + approval, buy list + Visa checkout, fly-in animation. **Devpost draft submitted.** |
| Sun 3 AM | **Feature freeze.** Only polish, bug fixes, demo fallbacks from here. |
| Sun 7 AM | Demo video recorded, Devpost final (track write-ups, Coinbase builder feedback, architecture diagram) |
| Sun 9 AM | **Submission deadline** |

## How we coordinate (after kickoff, it's decentralized)
This plan is a starting point. Each of us and our Claude agents can change it:
- **`/sync`**: start every session with it. Your agent catches up on issues, mentions, proposals and merges, replies to anything aimed at your lane, and tells you what to do next.
- **`/new-task`**: your agent files issues for new work it discovers (bugs, follow-ups, splits).
- **`/propose`**: disagree with the plan, or need to change another lane's interface or the data model? Your agent opens a `proposal` issue with a deadline. Silence by the deadline means accepted; if there's an objection, the most-affected lane owner decides. Only `needs-decision` items come to us humans. Outcomes go in `docs/decisions/`.
- Agents talk to each other **on GitHub issues**, with @mentions, signed "<name>'s agent". Blocked? Label it `blocked`, say on what, and use a stub or fixture meanwhile.
- PRs self-merge on green CI. **Humans don't need to review.** Humans only weigh in on `needs-decision` items and product direction.

## How we work (git)
1. Pick an issue on GitHub and self-assign it. In Claude Code, run **`/claim-task <#>`**. That assigns you and creates a branch `<name>/<#>-<slug>` from the latest `main`.
2. Commit small and often. Open a **draft PR** early so others can see what you're doing.
3. When it works, run **`/ship`**. It rebases on `main`, runs checks, pushes, opens or updates the PR with `Closes #<n>`, and merges once CI is green. No reviewer needed.
4. `main` is protected: no direct pushes. Keep branches to a few hours; long-lived branches cause conflicts.
5. **Changing the data model?** Make it its own small PR and post in the team chat. Everyone's code depends on it.
6. Before you sleep or step away: push, and leave a one-line status comment on your issue.

Without Claude: `git switch main && git pull && git switch -c <name>/<#>-<slug>`, then `gh pr create --draft`, then `gh pr merge --squash --auto` when ready.

## Demo plan (draft)
Our own room is the "old home". (1) Show the scan and inventory. (2) Show pricing with the live spending log ticking as x402 payments happen. (3) Edit the sort on phone A, and phone B updates live. (4) The listing agent drafts an eBay listing, and the approval prompt pops on the phone. (5) The buy agent finds a deal and checks out with Visa. (6) **Fly-in to the new house.** (7) Summary. Every step needs a fixture fallback so the demo can't die on wifi.

## Sponsor tracks we're targeting
Coinbase x402 (Payment Agents) · Spacetime · Apify · Visa (Reimagining Shopping) · Anthropic · Auth0 (MLH), plus overall prizes. Requirements and submission checklist are in `docs/tracks.md`.
