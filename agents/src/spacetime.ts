import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import type { Identity } from 'spacetimedb';
import { DbConnection, tables } from './module_bindings/index.js';
import type { User } from './module_bindings/types.js';
import { config } from './config.js';

export type Conn = DbConnection;

// `user` is private (#41 part B): the worker reads every row through the `worker_user` view,
// which has no index accessors, so look owners up by scanning it.
export function findUser(conn: Conn, identity: Identity): User | undefined {
  for (const u of conn.db.workerUser.iter()) if (u.identity.isEqual(identity)) return u;
  return undefined;
}

function savedToken(): string | undefined {
  if (config.workerToken) return config.workerToken;
  if (existsSync(config.workerTokenFile)) return readFileSync(config.workerTokenFile, 'utf8').trim();
  return undefined;
}

// Persists the token for the next restart. Best effort: a hosted worker gets its identity from
// SPACETIME_WORKER_TOKEN and may run on a read-only filesystem, so a failed write only logs.
export function saveToken(file: string, token: string): boolean {
  try {
    writeFileSync(file, token);
    return true;
  } catch (err) {
    console.warn(`[spacetime] couldn't save the worker token to ${file} (${(err as Error)?.message ?? err}); only SPACETIME_WORKER_TOKEN keeps this identity across restarts`);
    return false;
  }
}

// If the connection stays down this long (e.g. after the laptop sleeps, automatic reconnect can
// keep failing forever), exit so run-worker.sh restarts the worker with a fresh connection.
// 0 disables the watchdog.
export const DISCONNECT_EXIT_SEC = Number(process.env.WORKER_DISCONNECT_EXIT_SEC ?? 120);

export function disconnectWatchdog(exit: () => void = () => process.exit(1), limitSec = DISCONNECT_EXIT_SEC) {
  let timer: NodeJS.Timeout | undefined;
  return {
    down() {
      if (limitSec <= 0 || timer) return;
      timer = setTimeout(() => {
        console.error(`[spacetime] still disconnected after ${limitSec}s; exiting so the supervisor restarts the worker`);
        exit();
      }, limitSec * 1000);
    },
    up() {
      clearTimeout(timer);
      timer = undefined;
    },
  };
}

// Writes in flight at a drop (or sent while down) are rejected, not retried, so items can stay
// 'running' forever. After an automatic reconnect, exit so run-worker.sh restarts the worker and the
// startup recovery (running -> pending, stale holds, 'posting' listings) runs.
export function exitAfterReconnect(exit: () => void = () => process.exit(1)) {
  console.warn('[spacetime] reconnected; exiting so the supervisor restarts the worker and startup recovery runs');
  setImmediate(exit);
}

// Connects as the worker identity, registers it, and subscribes to every table.
// Resolves once the initial subscription has been applied (the local cache is populated).
export function connect(): Promise<{ conn: Conn; identity: Identity }> {
  const watchdog = disconnectWatchdog();
  return new Promise((resolve, reject) => {
    const conn = DbConnection.builder()
      .withUri(config.spacetimeUri)
      .withDatabaseName(config.spacetimeDb)
      .withToken(savedToken())
      .withAutomaticReconnect()
      .onConnect((conn, identity, token) => {
        saveToken(config.workerTokenFile, token);
        console.log(`[spacetime] connected as ${identity.toHexString()}`);
        // Subscribe only once registration succeeds, so a non-worker identity rejects connect() cleanly.
        conn.reducers
          .registerWorker({ label: 'moove-agents' })
          .then(() =>
            conn
              .subscriptionBuilder()
              .onApplied(() => resolve({ conn, identity }))
              .onError(ctx => reject(ctx.event ?? new Error('subscription failed')))
              .subscribe(Object.values(tables))
          )
          .catch(err => {
            console.error(`[spacetime] register_worker failed (${(err as Error)?.message ?? err}): this identity isn't the registered worker. Restore agents/${config.workerTokenFile} (or SPACETIME_WORKER_TOKEN), or reset the local DB with \`npm run publish:local:reset\` in spacetime/.`);
            reject(err);
          });
      })
      .onAutomaticReconnect((_conn, _identity, token) => {
        watchdog.up();
        saveToken(config.workerTokenFile, token);
        exitAfterReconnect();
      })
      .onConnectError((_ctx, err) => reject(err))
      .onDisconnect((_ctx, err) => {
        console.warn('[spacetime] disconnected', err ?? '');
        watchdog.down();
      })
      .build();
  });
}
