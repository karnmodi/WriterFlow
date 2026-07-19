import closeWithGrace from "close-with-grace";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { buildApp } from "./app.js";

const config = loadConfig();
const pool = createPool(config);
const app = buildApp({ config, pool });

closeWithGrace({ delay: 5000 }, async ({ err }) => {
  if (err) {
    app.log.error({ err: { message: err.message } }, "closing due to error");
  }
  await app.close();
  await pool.end();
});

try {
  await app.listen({ port: config.PORT, host: "0.0.0.0" });
} catch (err) {
  app.log.error({ err: { message: (err as Error).message } }, "failed to start");
  process.exit(1);
}
