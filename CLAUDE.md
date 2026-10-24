# Moove

Cal Hacks 13.0 project (Oct 23-25, 2026). **Devpost deadline: Sun 9:00 AM.** Live demo required at judging.

Moove is an **iOS-only app** (no web client) that runs your move. Scan your room with LiDAR, and Moove inventories, prices and sorts everything (keep/sell/donate/trash). Agents then sell what you don't want, buy what the new place needs, and pay for things on your behalf. At the end, everything you kept flies into a 3D model of your new home.

Read these before writing code:
- `docs/TEAM.md`: lanes, owners, timeline, workflow (the human handout)
- `docs/architecture.md`: components and how they talk
- `docs/data-model.md`: SpacetimeDB tables + reducers. **This is the contract between lanes.**
- `docs/tasks/NN-*.md`: the brief for the task you're working on (same text as the GitHub issue)
- `docs/tracks.md`: sponsor-track requirements. Check it before cutting a corner a judge would care about.

## Repo map
| Path | What | Owner lane |
|---|---|---|
| `ios/` | SwiftUI app (XcodeGen `project.yml`) + `MooveKit/` Swift package (models + pure algorithms) | ios-capture, ios-newhome, commerce (screens) |
| `spacetime/` | SpacetimeDB **TypeScript** module: tables + reducers. No outbound I/O. | backend |
| `agents/` | Node/TS worker: a SpacetimeDB client running all agents and integrations (Claude, Apify, x402/CDP, eBay, Visa, Auth0 CIBA) + file upload endpoint | backend, commerce |
| `docs/` | Planning docs, task briefs, track notes | everyone |
| `scripts/` | Repo tooling (issue creation, etc.) | backend |

Each of `ios/`, `spacetime/`, `agents/` has its own `CLAUDE.md` with lane conventions. Read it when working there.

## Git workflow (everyone, including Claude)
- **Never commit directly to `main`.** It is protected: PRs only, CI must pass.
- Claim work with `/claim-task <issue#>`, which assigns the issue and creates a branch `<name>/<issue#>-<slug>` off the latest `main`.
- Keep branches short-lived (a few hours at most). Commit small and often. Open a **draft PR early**.
- Ship with `/ship`: rebase on `origin/main`, run the lane's checks, push, open/update the PR with `Closes #<n>`, and **squash-merge yourself once CI is green**. No reviewer required.
- Rebase rather than merge `main` into your branch. Never force-push someone else's branch.
- Stay inside your task's directories. If you need to change another lane's code, keep it minimal and call it out in the PR description.
- **Contract changes** (any table/reducer change in `spacetime/`) go in their own small PR. Regenerate TS bindings, update `ios/MooveKit` models and `docs/data-model.md` in the same PR, and tell the team.
- Before you stop working, push and update the issue with a one-line status.

## Coordination (decentralized, agents talk through GitHub)
The kickoff plan is a starting point, not a mandate. After kickoff, **agents coordinate with each other through GitHub issues and PRs**, and humans step in only for product-direction calls.
- **`/sync`** at the start of every session and before claiming new work. It reads new issues, mentions, proposals, blocked items and recent merges, and responds to anything aimed at your lane.
- **`/new-task`** whenever you discover work not covered by an issue (follow-ups, bugs, split-out subtasks). Don't leave TODOs only in code or chat.
- **`/propose`** for anything that affects other lanes or the shared docs (scope, architecture, contract, ownership). It works by lazy consensus with a deadline, and outcomes are recorded in `docs/decisions/`. Disagreeing with the plan is fine. Propose, don't silently diverge.
- **Talk on the issue, not in private.** To ask another lane for something, comment on their issue (or open one) and @mention the owner. Sign comments as `<name>'s agent`. Add the `blocked` label when you are blocked and say exactly on what. Unblock yourself with a stub or fixture instead of waiting.
- **Lanes are defaults, not walls.** If your lane is done or blocked, take a `help-wanted` issue, or another lane's unassigned issue (comment first).
- **Docs are living.** Anyone may improve `docs/` and any `CLAUDE.md` through a normal PR. Keep them true to what's actually built.
- **Labels:** `task`, `lane:<lane>`, `blocked`, `proposal`, `needs-decision` (humans needed), `contract-change`, `help-wanted`, `stretch`.

## Hard rules
- **No secrets in git.** Keys go in `.env.local` (gitignored) or the worker's environment. Document every new key in `.env.example`. CI runs gitleaks.
- **Label anything simulated.** Payments and listings that aren't real must say so in the data (`simulated: true`) and in the UI. This is a Coinbase track rule and good practice.
- **Every agent step writes an `agentEvents` row** (plan, tool call, result, payment, error), so the app can show what agents did. Judges for Coinbase, Visa and Spacetime reward visible agent work.
- **Sentimental items are never auto-decided.** `maybeSentimental` items must be left for the user.
- Spending needs guardrails: per-agent spend caps, plus user approval above a threshold (Auth0 async authorization, task #12).
- Use Claude models via env vars (`MODEL_VISION`, `MODEL_FAST`, `MODEL_AGENT`). Defaults: `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5`.
- SDKs here are moving targets (SpacetimeDB, x402/CDP, Auth0 for AI Agents, Swift SpacetimeDB SDK). **Check current docs before writing integration code**, rather than relying on memory.
- Keep demo fallbacks working: fixture data and a hardcoded demo house so the live demo never depends on a flaky scrape or network.

## Shared database
- **Maincloud:** DB `moove` at `wss://maincloud.spacetimedb.com` (dashboard: https://spacetimedb.com/moove). This is the team's shared/demo DB. Only Christian's CLI identity can publish to it, so ask on GitHub for a republish after contract changes.
- The agent worker identity is already registered there. Only one worker should run against maincloud at a time (Christian's machine, token in `agents/.worker-token.maincloud`). For your own agent work, use a local `spacetime start` + `npm run publish:local`.

## Commands
Each lane fills these in as it initializes its directory. Keep this section current.
- `spacetime/` (needs the CLI: `curl -sSf https://install.spacetimedb.com | sh`): `npm install`, then `npm run typecheck`, `npm run build`, `spacetime start` (local server on :3000), `npm run publish:local` (or `publish:local:reset` to wipe data), `npm run generate` (regenerates `agents/src/module_bindings`, which are committed; never hand-edit them), and `npm run publish:cloud` (maincloud). Poke at it with `spacetime call -s local moove create_room '"Bedroom"' '"old"'` or `spacetime sql -s local moove "SELECT * FROM item"`.
- `agents/`: `npm install`, `npm run dev` (watch mode) or `npm start`, and `npm run typecheck`. It connects to `SPACETIME_URI` (default `ws://localhost:3000`) and DB `moove`. Its identity is stored in `agents/.worker-token` (gitignored). The first identity to call `register_worker` owns the worker role, so keep that token, or `npm run publish:local:reset` in `spacetime/` to start over. Add agents to the array in `src/index.ts` (see the `Agent` interface in `src/agents/types.ts`). Log every step with `logEvent()` from `src/events.ts`. Hosted deploy (Docker, DO, Fly.io): `docs/deploy.md`.
- `ios/`: `cd ios && xcodegen && open Moove.xcodeproj`. `cd ios/MooveKit && swift test` (also works on Linux).
