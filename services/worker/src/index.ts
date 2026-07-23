import pino from "pino";
import pg from "pg";
import { reconcileAccounting } from "./accounting.js";

const logger = pino({ level: process.env["LOG_LEVEL"] ?? "info" });

if (!process.env["DATABASE_URL"]) {
  logger.error("DATABASE_URL is required");
  process.exit(1);
}

const pool = new pg.Pool({ connectionString: process.env["DATABASE_URL"] });

let shuttingDown = false;
let reconciliationRunning = false;
const runReconciliation = async (): Promise<void> => {
  if (shuttingDown || reconciliationRunning) return;
  reconciliationRunning = true;
  try {
    const result = await reconcileAccounting(pool);
    if (result.expiredReservations > 0 || result.correctedBalances > 0) {
      logger.warn({ event: "accounting.ledger_mismatch", ...result }, "accounting projections reconciled");
    }
  } catch (error) {
    logger.error({ error: { message: (error as Error).message } }, "accounting reconciliation failed");
  } finally {
    reconciliationRunning = false;
  }
};
const reconciliationTimer = setInterval(() => {
  void runReconciliation();
}, 30_000);

for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    if (shuttingDown) return;
    shuttingDown = true;
    clearInterval(reconciliationTimer);
    logger.info({ signal }, "worker shutting down");
    void pool.end().finally(() => process.exit(0));
  });
}

logger.info("worker started");
void runReconciliation();
