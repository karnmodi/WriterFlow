#!/usr/bin/env tsx
/**
 * Cloud smoke: DB-side approve + APIM pairing token + /me + Fix Grammar SSE.
 *
 *   DATABASE_URL='postgres://writerflow_migrator:...@wfprod-pg.../writerflow?sslmode=require' \
 *   APIM_GATEWAY='https://wfprod-apim-dev.azure-api.net' \
 *   npx tsx scripts/cloud/cloud-e2e.ts
 */
import { readFileSync } from "node:fs";
import { randomBytes, randomUUID } from "node:crypto";
import pg from "pg";
import { authorizeDevice } from "../../services/api/src/pairing/service.js";
import { approveDevice } from "../../services/api/src/pairing/approve.js";
import { computeS256Challenge } from "../../services/api/src/crypto/pkce.js";
import { testEntraIdentity } from "../../services/api/test/helpers/testIdentity.js";

const APIM = (process.env.APIM_GATEWAY ?? "https://wfprod-apim-dev.azure-api.net").replace(/\/$/, "");
const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error("DATABASE_URL is required");
  process.exit(1);
}

async function fetchJson(method: string, url: string, body?: unknown, headers: Record<string, string> = {}) {
  const res = await fetch(url, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  let json: unknown = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    /* SSE or plain text */
  }
  return { status: res.status, text, json };
}

async function main() {
  const pool = new pg.Pool({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: true } });
  await pool.query("SELECT 1");
  console.log("postgres ok");

  const subject = `e2e-${randomBytes(4).toString("hex")}`;
  const identity = testEntraIdentity(subject, {
    displayName: "Cloud E2E",
    email: `${subject}@example.com`
  });

  const verifier = randomBytes(32).toString("base64url");
  const challenge = computeS256Challenge(verifier);
  const auth = await authorizeDevice(pool, "https://writerflow.aviusolutions.com", {
    installId: randomUUID(),
    deviceLabel: "cloud-e2e",
    codeChallenge: challenge,
    codeChallengeMethod: "S256"
  });
  console.log("authorize ok", auth.userCode);

  const approved = await approveDevice(pool, identity, auth.userCode);
  if (approved.kind !== "approved") {
    throw new Error(`approve failed: ${approved.kind}`);
  }
  console.log("approve ok device", approved.snapshot.device.id);

  const tokenRes = await fetchJson("POST", `${APIM}/v2/device/token`, {
    deviceCode: auth.deviceCode,
    codeVerifier: verifier
  });
  if (tokenRes.status !== 200) throw new Error(`device/token ${tokenRes.status}: ${tokenRes.text}`);
  const tokenBody = tokenRes.json as { accessToken: string; deviceId: string };
  const accessToken = tokenBody.accessToken;
  const deviceId = tokenBody.deviceId ?? approved.snapshot.device.id;
  console.log("token ok via APIM");

  const me = await fetchJson("GET", `${APIM}/v2/me`, undefined, { Authorization: `Bearer ${accessToken}` });
  if (me.status !== 200) throw new Error(`/me ${me.status}: ${me.text}`);
  console.log("/me ok", (me.json as { displayName: string }).displayName);

  const allFixtures = [
    "action-fix-grammar.json",
    "action-elaborate.json",
    "action-formal.json",
    "action-casual.json",
    "action-reply.json",
    "action-reply-empty.json",
    "action-custom.json",
    "action-custom-insert-mode.json",
    "action-prompt-builder-analyze.json",
    "action-prompt-builder-finalize.json"
  ];
  const requestedFixture = process.env["CLOUD_E2E_FIXTURE"];
  if (requestedFixture && !allFixtures.includes(requestedFixture)) {
    throw new Error(`Unknown CLOUD_E2E_FIXTURE: ${requestedFixture}`);
  }
  const fixtures = requestedFixture ? [requestedFixture] : allFixtures;
  for (const filename of fixtures) {
    const fixture = JSON.parse(
      readFileSync(new URL(`../../Docs/contracts/fixtures/requests/${filename}`, import.meta.url), "utf8")
    ) as { request: Record<string, unknown> };
    const envelope = { ...fixture.request, operationId: randomUUID() };
    const startedAt = performance.now();
    const inference = await fetch(`${APIM}/v2/inference/stream`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Idempotency-Key": randomUUID(),
        "X-WriterFlow-Version": "2.0.0-e2e",
        "X-WriterFlow-Device": deviceId
      },
      body: JSON.stringify(envelope)
    });
    const reader = inference.body?.getReader();
    if (!reader) throw new Error(`${filename} returned no response body`);
    const decoder = new TextDecoder();
    let inferenceText = "";
    let firstDeltaMs: number | null = null;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      inferenceText += decoder.decode(value, { stream: true });
      if (firstDeltaMs == null && inferenceText.includes('"type":"output.delta"')) {
        firstDeltaMs = Math.round(performance.now() - startedAt);
      }
    }
    inferenceText += decoder.decode();
    if (inference.status !== 200) {
      throw new Error(`${filename} failed (${inference.status}): ${inferenceText.slice(0, 500)}`);
    }
    if (!inferenceText.includes('"type":"completed"')) {
      throw new Error(`${filename} did not complete: ${inferenceText.slice(0, 500)}`);
    }
    console.log(`${filename} inference OK, first delta ${firstDeltaMs ?? "n/a"}ms`);
  }

  await pool.end();
  console.log("cloud e2e OK");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
