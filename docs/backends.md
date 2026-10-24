# Backends

Several ready-to-test backends run at once, so the team can test in one batch. `cd agents && npm run status` checks all the maincloud ones in a few seconds (worker version, upload URL health, data counts, recent errors).

**One-command test per backend:**
| Backend | Command (from `agents/`) | Expected |
|---|---|---|
| Live + Demo health | `npm run status` | `UP` for each, upload `healthy` |
| Demo, as a judge's phone | `npm run smoke -- moove-demo 4RZ9G8` | `PASS` for join by code, 9 items priced and sorted, upload round trip, and room/user private |
| Live, as a phone | `npm run smoke -- moove <a room's join code>` | same, for that room |
| Whole pipeline, local | `npm run e2e -- --replay` (needs `spacetime start`) | `22/22 passed` |

`smoke` joins the room as a test user (token in `agents/.user-token.smoke.<db>`) and uploads one 222-byte PNG. It spends no Claude, Apify or payments. Before #41 step 2 is on a database, its privacy check FAILs on purpose.

| Backend | Database | Worker | Upload URL | Use it for |
|---|---|---|---|---|
| **Live** | maincloud `moove` | Christian's laptop, `run-worker.sh`, port 8787 | read `service_config.upload_base_url` (Cloudflare tunnel, changes when the laptop restarts; the newest is always on #2) | Team testing with real scans. Has every scan done so far, junk included. |
| **Demo** | maincloud `moove-demo` | Christian's laptop, `run-worker.sh`, port 8797 | `service_config.upload_base_url` on `moove-demo` (its own tunnel) | Clean judge demo. Seeded "Bedroom", 9 priced and sorted items. **Join code `4RZ9G8`.** |
| **E2E** | local `moove-e2e` (wiped every run) | spawned by the test, port 8790 | `http://localhost:8790` | Automated pipeline test: `cd agents && npm run e2e -- --replay` (PASS/FAIL table). Also runs in CI. |
| **Your local** | local `moove-<you>` | `npm start` with your own `SPACETIME_DB_NAME` / `UPLOAD_PORT` | `http://<LAN IP>:<port>` | Lane development without touching maincloud. |

## Pointing the app at a backend
- In the app: **Settings → Database → Live (`moove`) / Demo (`moove-demo`)**, with no rebuild. The app reads the upload URL from the database's `service_config` (#132), so tunnel restarts need no config. `ios/Config/Local.xcconfig` (`MOOVE_SPACETIME_HOST`, `MOOVE_SPACETIME_DB`, `MOOVE_UPLOAD_BASE_URL`) only sets the defaults and fallback.
- To see the demo room on a second phone: Items → **Join a room** → `4RZ9G8`.

## Running a worker (Christian)
From the main checkout `agents/` (keep it on `main`, because the supervisor re-runs whatever is checked out):
```sh
# live
SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_WORKER_TOKEN_FILE=.worker-token.maincloud \
  PUBLIC_UPLOAD_BASE_URL=<tunnel> VISA_PROVIDER=simulated scripts/run-worker.sh
# demo
SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_DB_NAME=moove-demo SPACETIME_WORKER_TOKEN_FILE=.worker-token.moove-demo \
  UPLOAD_PORT=8797 UPLOAD_DIR=uploads-demo X402_PORT=8403 PUBLIC_UPLOAD_BASE_URL=<tunnel 2> VISA_PROVIDER=simulated scripts/run-worker.sh
```
Each worker writes its own `upload_base_url` into its database on start. A republish disconnects workers, and the supervisor restarts them. After merging agent code: `git pull && npm ci`, then kill the worker child (the PID listening on 8787 / 8797) so it restarts on the new code.

## Re-seeding the demo
`SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_DB_NAME=moove-demo npm run seed:demo -- --maincloud --force --wait`. This creates a new room and prints its join code; update this file.

Commerce story (opt-in): add `SEED_COMMERCE=1` to also seed a Herman Miller office chair set to sell (priced ~$350 from the committed replay, so the listing agent drafts it over the $100 threshold and asks approval; the draft is one live Claude call). Without `--force` it only adds the chair to the existing Bedroom, so the join code stays the same.
