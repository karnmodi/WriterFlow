import pino from "pino";
import pg from "pg";

const logger = pino({ level: process.env["LOG_LEVEL"] ?? "info" });

if (!process.env["DATABASE_URL"]) {
  logger.error("DATABASE_URL is required");
  process.exit(1);
}

const pool = new pg.Pool({ connectionString: process.env["DATABASE_URL"] });

let shuttingDown = false;
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info({ signal }, "worker shutting down");
    void pool.end().finally(() => process.exit(0));
  });
}

logger.info("worker skeleton started — dispatch/reconciliation jobs land in Stage 5.5");
