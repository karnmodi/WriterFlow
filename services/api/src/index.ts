import closeWithGrace from "close-with-grace";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { buildApp } from "./app.js";
import { createSigningKeyProvider } from "./jwt/keyVaultProvider.js";
import { EntraIdTokenVerifier } from "./entra/verifier.js";
import { createInferenceProvider } from "./inference/createProvider.js";

const config = loadConfig();
const pool = createPool(config);
const signingKeys = await createSigningKeyProvider(process.env);
// null (POST /v2/web-session/token returns 503) until the Entra External ID
// tenant exists and ENTRA_* is configured — cloud apply pending.
const entraVerifier =
  config.ENTRA_TENANT_ISSUER && config.ENTRA_JWKS_URI && config.ENTRA_WEB_CLIENT_ID
    ? EntraIdTokenVerifier.remote(config.ENTRA_JWKS_URI, config.ENTRA_TENANT_ISSUER, config.ENTRA_WEB_CLIENT_ID)
    : null;
const inferenceProvider = createInferenceProvider(process.env);
const app = buildApp({ config, pool, signingKeys, entraVerifier, inferenceProvider });

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
