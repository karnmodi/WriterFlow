import { afterEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/app.js";
import { LocalDevSigningKeyProvider } from "../src/jwt/keys.js";
import { fakeConfig } from "./helpers/fakeConfig.js";

describe("APIM origin authentication", () => {
  let app: FastifyInstance | undefined;

  afterEach(async () => {
    await app?.close();
  });

  it("rejects direct access to v2 routes when the origin credential is configured", async () => {
    app = buildApp({
      config: fakeConfig({ APIM_ORIGIN_SECRET: "a".repeat(32) }),
      pool: {} as never,
      signingKeys: new LocalDevSigningKeyProvider(),
      entraVerifier: null
    });

    const response = await app.inject({
      method: "POST",
      url: "/v2/device/authorize",
      payload: {}
    });

    expect(response.statusCode).toBe(403);
    expect(response.json()).toMatchObject({ code: "FORBIDDEN" });
  });
});
