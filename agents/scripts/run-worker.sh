#!/usr/bin/env bash
# Keeps the agent worker running: restarts it whenever it exits (a crash, or the disconnect a
# maincloud republish causes), with a short backoff that resets after a healthy run.
#   agents/scripts/run-worker.sh            # uses .env.local + the environment as usual
#   PUBLIC_UPLOAD_BASE_URL_FILE=<file>       # re-read the upload URL from this file on every start (scripts/tunnel.sh)
#   STOP: Ctrl-C (or kill this script's PID); the worker gets SIGTERM and exits right away.
# After a contract change, pull + npm ci first: a restart reuses whatever code is checked out.
set -u
cd "$(dirname "$0")/.."

child=0
trap 'echo "[run-worker] stopping"; [ "$child" -gt 0 ] && kill "$child" 2>/dev/null; wait "$child" 2>/dev/null; exit 0' INT TERM

delay=2
while true; do
  started=$(date +%s)
  # scripts/tunnel.sh writes the current tunnel URL here; re-read it on every start so a restarted
  # tunnel's new URL reaches the worker (which announces it in service_config).
  if [ -n "${PUBLIC_UPLOAD_BASE_URL_FILE:-}" ] && [ -s "$PUBLIC_UPLOAD_BASE_URL_FILE" ]; then
    export PUBLIC_UPLOAD_BASE_URL="$(cat "$PUBLIC_UPLOAD_BASE_URL_FILE")"
  fi
  echo "[run-worker] starting worker ($(git rev-parse --short HEAD 2>/dev/null || echo '?'))"
  npx tsx src/index.ts &
  child=$!
  wait "$child"
  code=$?
  ran=$(( $(date +%s) - started ))
  # A run that lasted a while was healthy: restart quickly. Crash loops back off up to 60 s.
  if [ "$ran" -gt 120 ]; then delay=2; else delay=$(( delay * 2 > 60 ? 60 : delay * 2 )); fi
  echo "[run-worker] worker exited with code $code after ${ran}s; restarting in ${delay}s"
  sleep "$delay"
done
