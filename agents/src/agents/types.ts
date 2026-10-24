import type { Conn } from '../spacetime.js';

// Each agent module exports one of these. start() registers row callbacks on the
// connection (e.g. conn.db.item.onInsert / onUpdate) and processes rows already in the cache.
export interface Agent {
  name: string;
  start(conn: Conn): void | Promise<void>;
}
