#!/usr/bin/env bash
# Keeps a Cloudflare quick tunnel to a worker's upload port alive and tells the worker its URL.
#   scripts/tunnel.sh <port> <url-file>        e.g. scripts/tunnel.sh 8787 .tunnel-url
# Writes the tunnel's https URL to <url-file>. Every 60 s it checks <url>/healthz through the tunnel;
# after 3 failures (laptop sleep, network change) it restarts cloudflared, which gets a NEW url, writes
# it, and kills the worker listening on <port> so run-worker.sh (started with
# PUBLIC_UPLOAD_BASE_URL_FILE=<url-file>) restarts it and the worker announces the new URL in
# service_config. Needs `cloudflared` on PATH (or CLOUDFLARED=/path/to/cloudflared).
set -u
port=${1:?port}
urlfile=${2:?url file}
cf=${CLOUDFLARED:-cloudflared}
log=$(mktemp -t tunnel.XXXX.log)
child=0
trap 'echo "[tunnel] stopping"; [ "$child" -gt 0 ] && kill "$child" 2>/dev/null; exit 0' INT TERM

restart_worker() {
  local pid
  pid=$(ss -ltnp 2>/dev/null | grep ":$port " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | head -1)
  if [ -n "$pid" ]; then echo "[tunnel] restarting worker $pid so it picks up the new URL"; kill "$pid"; fi
}

while true; do
  : > "$log"
  "$cf" tunnel --no-autoupdate --url "http://localhost:$port" > "$log" 2>&1 &
  child=$!
  url=""
  for _ in $(seq 1 60); do
    url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$log" | tail -1)
    [ -n "$url" ] && break
    sleep 1
  done
  if [ -z "$url" ]; then echo "[tunnel] no URL from cloudflared; retrying in 30s"; kill "$child" 2>/dev/null; sleep 30; continue; fi
  prev=$(cat "$urlfile" 2>/dev/null || true)
  echo "$url" > "$urlfile"
  echo "[tunnel] $url -> localhost:$port"
  [ "$url" != "$prev" ] && [ -n "$prev" ] && restart_worker
  fails=0
  while kill -0 "$child" 2>/dev/null; do
    sleep 60
    if curl -sf -m 15 "$url/healthz" > /dev/null; then fails=0; else fails=$((fails + 1)); echo "[tunnel] health check failed ($fails/3)"; fi
    [ "$fails" -ge 3 ] && break
  done
  echo "[tunnel] tunnel unhealthy or exited; restarting"
  kill "$child" 2>/dev/null
  wait "$child" 2>/dev/null
  sleep 5
done
