import pg from "pg";
import type { AppConfig } from "./config.js";

export function createPool(config: Pick<AppConfig, "DATABASE_URL" | "DATABASE_POOL_MAX">): pg.Pool {
  return new pg.Pool({
    connectionString: config.DATABASE_URL,
    max: config.DATABASE_POOL_MAX,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000
  });
}

/**
 * Runs `fn` inside one transaction with `app.tenant_id` set transaction-locally
 * (`SET LOCAL`, cleared automatically at COMMIT/ROLLBACK), per
 * V2-ARCHITECTURE.md §8's row-level-security requirement: tenant context is
 * bound per-transaction, never per-connection, so a pooled connection can
 * never leak a stale tenant into the next caller.
 */
export async function withTenantContext<T>(
  pool: pg.Pool,
  tenantId: string,
  fn: (client: pg.PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

/** For migration-identity/system work that intentionally has no tenant scope. */
export async function withoutTenantContext<T>(
  pool: pg.Pool,
  fn: (client: pg.PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    return await fn(client);
  } finally {
    client.release();
  }
}
