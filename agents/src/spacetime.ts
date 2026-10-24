import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import type { Identity } from 'spacetimedb';
import { DbConnection, tables } from './module_bindings/index.js';
import { config } from './config.js';

export type Conn = DbConnection;

function savedToken(): string | undefined {
  if (config.workerToken) return config.workerToken;
  if (existsSync(config.workerTokenFile)) return readFileSync(config.workerTokenFile, 'utf8').trim();
  return undefined;
}

// Connects as the worker identity, registers it, and subscribes to every table.
// Resolves once the initial subscription has been applied (the local cache is populated).
export function connect(): Promise<{ conn: Conn; identity: Identity }> {
  return new Promise((resolve, reject) => {
    const conn = DbConnection.builder()
      .withUri(config.spacetimeUri)
      .withDatabaseName(config.spacetimeDb)
      .withToken(savedToken())
      .withAutomaticReconnect()
      .onConnect((conn, identity, token) => {
        writeFileSync(config.workerTokenFile, token);
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
      .onAutomaticReconnect((_conn, _identity, token) => writeFileSync(config.workerTokenFile, token))
      .onConnectError((_ctx, err) => reject(err))
      .onDisconnect((_ctx, err) => console.warn('[spacetime] disconnected', err ?? ''))
      .build();
  });
}
