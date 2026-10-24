# Deploying the agent worker

The worker (`agents/`) normally runs on Christian's laptop behind a cloudflared tunnel. This doc moves it
to a host so the demo doesn't depend on the laptop (Coinbase judging rewards a hosted agent; MLH has a
DigitalOcean prize). Nothing here has been deployed yet: these are the steps, prepared but not run.

What gets deployed is one container, built from `agents/Dockerfile`:
- `node:22-slim`, `npm ci` **with** dev deps (the worker runs TypeScript through `tsx`, a devDependency), then `node --import tsx src/index.ts`.
- One public HTTP port, `UPLOAD_PORT` (8787): `POST /upload`, `GET /files/<name>`, and `GET /healthz` -> `200 {"ok":true}` for platform health checks. The x402 comps paywall stays on `127.0.0.1:8402` inside the container and is never exposed.
- One persistent directory, `/app/uploads` (photos, USDZ scans, CapturedRoom JSON, simulated listing pages). Mount a volume there or every redeploy loses the files the database points at.
- The worker identity comes from the **`SPACETIME_WORKER_TOKEN` secret**, which is read before the token file. On connect the worker still tries to write `.worker-token`; on a read-only filesystem that only logs a warning.
- `.dockerignore` keeps `.env*`, `.worker-token*`, `uploads/` and `node_modules/` out of the image. Secrets only ever reach the container as environment variables.

**Only one worker may run against a database at a time.** Two workers with the same identity would both
pick up the same pending rows. Always stop the laptop worker before starting the hosted one (see Cutover).

## Environment variables

Set secrets with the platform's secret store (`fly secrets set`, DO "Encrypt" checkbox, or a `chmod 600`
env file on a Droplet), never in `fly.toml`, an app spec in git, or the image.

| Variable | Secret | Hosted value / notes |
|---|---|---|
| `SPACETIME_WORKER_TOKEN` | **yes** | Contents of `agents/.worker-token.maincloud` on Christian's machine. This *is* the worker identity: whoever holds it can write as the worker. |
| `SPACETIME_URI` | no | `wss://maincloud.spacetimedb.com` |
| `SPACETIME_DB_NAME` | no | `moove` |
| `SPACETIME_WORKER_TOKEN_FILE` | no | Leave unset (`.worker-token`). Only written as a convenience; the env var wins. |
| `PUBLIC_UPLOAD_BASE_URL` | no | The public https URL of the deployment, no trailing slash, e.g. `https://moove-agents.fly.dev`. Upload URLs written into the DB start with this, and eBay needs https photos. |
| `UPLOAD_PORT` | no | `8787` (set in the image; the platform routes its public port to it) |
| `UPLOAD_DIR` | no | `/app/uploads` (set in the image; mount the volume here) |
| `UPLOAD_MAX_BYTES` | no | `52428800` (50 MB, sized for USDZ scans). |
| `ANTHROPIC_API_KEY` | **yes** | Vision + listing agents. |
| `MODEL_VISION`, `MODEL_FAST`, `MODEL_AGENT` | no | Defaults `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5`. |
| `APIFY_TOKEN` | **yes** | Pricing comps. Without it pricing uses only cached `fixtures/comps/` (baked into the image). |
| `APIFY_SOURCES`, `APIFY_MAX_USD_PER_RUN`, `MARKET_CITY_FB`, `MARKET_CITY_CRAIGSLIST` | no | Defaults `ebay,fb`, `0.10`, `sanfrancisco`, `sfbay`. |
| `CDP_API_KEY_ID`, `CDP_API_KEY_SECRET`, `CDP_WALLET_SECRET` | **yes** | Real Base Sepolia x402 payments. Without them payments are recorded `simulated: true`. |
| `AGENT_SPEND_CAP_USDC`, `X402_MAX_PER_CALL_USDC`, `X402_SIMULATE`, `X402_PORT`, `PRICING_PAY_X402` | no | Defaults `5`, `0.10`, unset, `8402`, `1`. |
| `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_REFRESH_TOKEN` | **yes** | Real sandbox listings (all `EBAY_*` policy/location keys must be set too). Otherwise listings are simulated. |
| `EBAY_FULFILLMENT_POLICY_ID`, `EBAY_PAYMENT_POLICY_ID`, `EBAY_RETURN_POLICY_ID`, `EBAY_LOCATION_KEY`, `EBAY_ENV`, `EBAY_MARKETPLACE_ID`, `EBAY_FALLBACK_IMAGE_URL` | no | From `npm run ebay:setup`. (`EBAY_RUNAME` is only used by that script.) |
| `LISTING_SIM_SOLD_AFTER_SEC` | no | `0` |
| `AUTH0_CIBA_CLIENT_SECRET` | **yes** | Phone approvals (CIBA). |
| `AUTH0_DOMAIN`, `AUTH0_CIBA_CLIENT_ID`, `AUTH0_AUDIENCE` | no | Leave all Auth0 vars empty to use only the in-app approvals inbox. (`AUTH0_CLIENT_ID/SECRET` belong to iOS; the worker doesn't use them.) |
| `APPROVAL_THRESHOLD_CENTS_DEFAULT`, `APPROVAL_SIM_AUTO_APPROVE_SEC` | no | `10000`, `0`. |

Easiest way to carry over the laptop config: start from `.env.local` (copy it by hand on Christian's
machine, don't paste it anywhere shared), then override `SPACETIME_URI`, `SPACETIME_DB_NAME`,
`PUBLIC_UPLOAD_BASE_URL`, `UPLOAD_DIR`, and add `SPACETIME_WORKER_TOKEN`.

## Build and smoke-test locally

```sh
cd agents
docker build -t moove-agents .
# Against your own local DB (never maincloud from a test):
# Test uploads go in a temp dir, not under agents/ (it would be baked into the next image build).
docker run --rm --network host --read-only --tmpfs /tmp -v "$(mktemp -d):/app/uploads" \
  -e SPACETIME_URI=ws://localhost:3000 -e SPACETIME_DB_NAME=<your-db> \
  -e UPLOAD_PORT=8796 -e PUBLIC_UPLOAD_BASE_URL=http://localhost:8796 -e PRICING_PAY_X402=0 moove-agents
curl -s localhost:8796/healthz   # {"ok":true}
```

`--read-only` needs `--tmpfs /tmp` because tsx keeps its transform cache in `/tmp`. The Apify cache also
writes `fixtures/comps/`, so on a read-only root a live (uncached) Apify lookup fails; the hosted options
below all have a writable root filesystem, so this only matters for that flag.

## Option A1: DigitalOcean Droplet (recommended DO path)

A $6/mo Droplet (1 GB, Ubuntu 24.04) with Docker and a Block Storage volume. This is the DO option with
real persistent storage.

1. Create the Droplet (Marketplace image "Docker on Ubuntu", region SFO3) and a 1 GB volume attached to it
   (Volumes -> Create, "Automatically format & mount"). It mounts at `/mnt/<volume_name>`.
2. Copy the code up and build on the box:
   ```sh
   ssh root@<droplet-ip>
   git clone https://github.com/christianazinn/moove && cd moove/agents
   docker build -t moove-agents .
   ```
3. Create `/root/moove.env` (`chmod 600 /root/moove.env`) with the variables from the table, one
   `KEY=value` per line. Put the token in it without echoing it: from Christian's laptop,
   ```sh
   { printf 'SPACETIME_WORKER_TOKEN='; cat agents/.worker-token.maincloud; echo; } | ssh root@<droplet-ip> 'cat >> /root/moove.env'
   ```
4. HTTPS: the iOS app and eBay need https. Either run a cloudflared tunnel on the Droplet pointing at
   `http://localhost:8787` (same as the laptop setup), or put Caddy in front:
   ```sh
   docker run -d --name caddy --restart unless-stopped --network host -v caddy_data:/data caddy:2 \
     caddy reverse-proxy --from <your-domain> --to localhost:8787
   ```
   Then set `PUBLIC_UPLOAD_BASE_URL=https://<your-domain-or-tunnel-host>` in `/root/moove.env`.
5. Run it (after the cutover step "stop the laptop worker"):
   ```sh
   docker run -d --name moove-agents --restart unless-stopped -p 127.0.0.1:8787:8787 \
     --env-file /root/moove.env -v /mnt/<volume_name>/uploads:/app/uploads moove-agents
   docker logs -f moove-agents   # expect "[spacetime] connected as c200..." and "started approval"
   ```
   (`-p 127.0.0.1:...` keeps the plain-http port private behind the tunnel or Caddy. Publish `-p 8787:8787`
   only if you want raw http on the IP too.)
6. Update: `cd ~/moove && git pull && cd agents && docker build -t moove-agents . && docker rm -f moove-agents` and rerun step 5.

## Option A2: DigitalOcean App Platform

Simplest DO setup, but **App Platform has no persistent volumes**: the container filesystem is wiped on
every deploy and restart, so uploaded photos and USDZ files the DB points at disappear. Use it only if
losing uploads on redeploy is acceptable (e.g. a final judging-day deploy you don't touch again), or use
the Droplet.

1. Apps -> Create App -> GitHub `christianazinn/moove`, branch `main`, **Source directory `agents`**. It
   detects the Dockerfile.
2. Component type **Web Service**, HTTP port `8787`, instance count **1** (never more: one worker per DB),
   smallest instance ($5). Health check: HTTP path `/healthz`.
3. Environment variables (component level): everything from the table. Tick **Encrypt** for every row
   marked secret, including `SPACETIME_WORKER_TOKEN` (paste the file contents on Christian's machine).
4. Deploy, note the `https://<app>.ondigitalocean.app` URL, set `PUBLIC_UPLOAD_BASE_URL` to it, and
   redeploy (the first deploy doesn't know its URL yet; stop the laptop worker before this one).

App Platform redeploys are rolling: the new container starts and passes its health check before the old
one gets SIGTERM, so for a few seconds two workers run against the DB (the worker exits as soon as it gets
SIGTERM, which keeps the overlap short). Don't redeploy while an item is mid-pipeline, or prefer the Droplet.

## Option B: Fly.io

`agents/fly.toml` is ready: one machine in `sjc`, never auto-stopped, a `moove_uploads` volume at
`/app/uploads`, the HTTP service on 8787 with a `/healthz` check, and the non-secret env.

```sh
cd agents
fly auth login
fly apps create moove-agents            # if taken, pick another and edit `app` + PUBLIC_UPLOAD_BASE_URL in fly.toml
fly volumes create moove_uploads --region sjc --size 1
# Secrets (run on Christian's machine; nothing is printed):
fly secrets set --stage SPACETIME_WORKER_TOKEN="$(cat .worker-token.maincloud)"
fly secrets set --stage ANTHROPIC_API_KEY=... APIFY_TOKEN=... CDP_API_KEY_ID=... CDP_API_KEY_SECRET=... CDP_WALLET_SECRET=...
# (plus EBAY_*, AUTH0_* and any non-default tunables from the table)
# After stopping the laptop worker:
fly deploy --ha=false
fly logs                                 # expect "[spacetime] connected as c200..."
```

`--ha=false` keeps it at one machine (a volume can only attach to one anyway). `--stage` stores the
secrets without triggering a deploy, so nothing starts before the cutover.

## Cutover (Christian)

1. **Stop the laptop worker** (Ctrl-C the `npm start`/`npm run dev` on port 8787). Leave the laptop's
   `agents/uploads/` and `.worker-token.maincloud` in place as the rollback.
2. Set `SPACETIME_WORKER_TOKEN` on the host to the contents of `agents/.worker-token.maincloud`, using the
   platform's secret store (commands above). Never paste it into chat, an issue, or a committed file.
3. Optional, to keep existing photos working: copy the laptop's uploads onto the volume
   (Droplet: `rsync -a agents/uploads/ root@<ip>:/mnt/<volume_name>/uploads/`; Fly: `fly ssh sftp shell`
   then `put`). Rows already in the DB keep their old base URL (the tunnel hostname). They only resolve if
   that hostname now points at the host, e.g. by moving the named cloudflared tunnel to the Droplet.
   Otherwise old photos 404 (vision and pricing have already run on them, so only the app's thumbnails
   are affected).
4. Deploy (Option A or B).
5. Verify:
   ```sh
   BASE=https://<public-host>
   curl -s $BASE/healthz                                    # {"ok":true}
   curl -s -o /dev/null -w '%{http_code}\n' $BASE/files/nope.png   # 404
   curl -s -X POST -H 'content-type: image/png' --data-binary @some.png $BASE/upload   # 201 {"url":"https://<public-host>/files/<uuid>.png"}
   curl -s -o /dev/null -w '%{http_code}\n' <that url>        # 200
   ```
   In the logs: `[spacetime] connected as <the same identity the laptop used>`, then `started vision ...
   started approval`. A `register_worker failed` line means the token is wrong or missing: fix the secret,
   don't reset the DB.
6. Point the iOS app at the new host: `MOOVE_UPLOAD_BASE_URL` in `ios/Config/Local.xcconfig` (or the shared
   `ios/Config/Moove.xcconfig`) -> `https:/$()/<public-host>`, and rebuild.
7. Rollback: stop the hosted worker (`docker rm -f moove-agents`, `fly scale count 0`, or App Platform ->
   Destroy/disable), then start the laptop worker again. Never run both.
