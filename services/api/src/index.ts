import closeWithGrace from "close-with-grace";
import { loadConfig } from "./config.js";
import { createPool } from "./db.js";
import { buildApp } from "./app.js";
import { LocalDevSigningKeyProvider } from "./jwt/keys.js";
import { EntraIdTokenVerifier } from "./entra/verifier.js";
import { DevEchoProvider } from "./inference/devEchoProvider.js";

const config = loadConfig();
const pool = createPool(config);
// TODO(Stage 5.1 Azure skeleton, cloud apply pending): swap for a Key
// Vault-backed SigningKeyProvider once Key Vault is provisioned — see
// services/api/src/jwt/keys.ts's SigningKeyProvider interface.
const signingKeys = new LocalDevSigningKeyProvider();
// null (POST /v2/web-session/token returns 503) until the Entra External ID
// tenant exists and ENTRA_* is configured — cloud apply pending.
const entraVerifier =
  config.ENTRA_TENANT_ISSUER && config.ENTRA_JWKS_URI && config.ENTRA_WEB_CLIENT_ID
    ? EntraIdTokenVerifier.remote(config.ENTRA_JWKS_URI, config.ENTRA_TENANT_ISSUER, config.ENTRA_WEB_CLIENT_ID)
    : null;
// TODO(Stage 5.4 Azure model plane, cloud apply pending): swap for a real
// Azure OpenAI-backed InferenceProvider once a resource is provisioned —
// see services/api/src/inference/provider.ts's InferenceProvider interface.
const inferenceProvider = new DevEchoProvider();
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
