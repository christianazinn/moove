# Backends

Several ready-to-test backends run at once, so the team can test in one batch. `cd agents && npm run status` checks all the maincloud ones in a few seconds (worker version, upload URL health, data counts, recent errors).

| Backend | Database | Worker | Upload URL | Use it for |
|---|---|---|---|---|
| **Live** | maincloud `moove` | Christian's laptop, `run-worker.sh`, port 8787 | read `service_config.upload_base_url` (Cloudflare tunnel, changes when the laptop restarts; the newest is always on #2) | Team testing with real scans. Has every scan done so far, junk included. |
| **Demo** | maincloud `moove-demo` | Christian's laptop, `run-worker.sh`, port 8797 | `service_config.upload_base_url` on `moove-demo` (its own tunnel) | Clean judge demo. Seeded "Bedroom", 9 priced and sorted items. **Join code `4RZ9G8`.** |
| **E2E** | local `moove-e2e` (wiped every run) | spawned by the test, port 8790 | `http://localhost:8790` | Automated pipeline test: `cd agents && npm run e2e -- --replay` (15 stages, PASS/FAIL table). Also runs in CI. |
| **Your local** | local `moove-<you>` | `npm start` with your own `SPACETIME_DB_NAME` / `UPLOAD_PORT` | `http://<LAN IP>:<port>` | Lane development without touching maincloud. |

## Pointing the app at a backend
- `ios/Config/Local.xcconfig`: `MOOVE_SPACETIME_HOST = https:/$()/maincloud.spacetimedb.com`, `MOOVE_SPACETIME_DB = moove` or `moove-demo`. Rebuild.
- Upload URL: until the app reads `service_config` (#122), set `MOOVE_UPLOAD_BASE_URL` to the database's `upload_base_url`:
  `spacetime sql -s maincloud moove-demo "SELECT key, value FROM service_config"`, or run `npm run status`.
- To see the demo room on a second phone: Inventory → **Join a room** → `4RZ9G8` (once #78 room sharing is on main).

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
