import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import { LocalDevSigningKeyProvider } from "../src/jwt/keys.js";
import { fakeConfig } from "./helpers/fakeConfig.js";

describe("health routes", () => {
  it("GET /healthz always returns ok without touching the pool", async () => {
    const pool = { query: vi.fn() };
    const app = buildApp({ config: fakeConfig(), pool: pool as never, signingKeys: new LocalDevSigningKeyProvider() });
    const response = await app.inject({ method: "GET", url: "/healthz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok" });
    expect(pool.query).not.toHaveBeenCalled();
    await app.close();
  });

  it("GET /readyz returns ready when the DB responds", async () => {
    const pool = { query: vi.fn().mockResolvedValue({ rows: [{ "?column?": 1 }] }) };
    const app = buildApp({ config: fakeConfig(), pool: pool as never, signingKeys: new LocalDevSigningKeyProvider() });
    const response = await app.inject({ method: "GET", url: "/readyz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ready" });
    await app.close();
  });

  it("GET /readyz returns 503 without dependency detail when the DB is unreachable", async () => {
    const pool = { query: vi.fn().mockRejectedValue(new Error("connection refused at 10.0.0.5:5432")) };
    const app = buildApp({ config: fakeConfig(), pool: pool as never, signingKeys: new LocalDevSigningKeyProvider() });
    const response = await app.inject({ method: "GET", url: "/readyz" });
    expect(response.statusCode).toBe(503);
    const body: unknown = response.json();
    expect(body).toEqual({ status: "not_ready" });
    expect(JSON.stringify(body)).not.toContain("10.0.0.5");
    await app.close();
  });
});
